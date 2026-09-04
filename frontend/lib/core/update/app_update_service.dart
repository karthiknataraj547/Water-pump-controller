import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../theme/app_theme.dart';
import '../constants/app_constants.dart';
import '../mqtt/mqtt_service.dart';

class AppVersionInfo {
  final String version;
  final int buildNumber;
  final String releaseDate;
  final String downloadUrl;
  final String websiteUrl;
  final String title;
  final List<String> changelog;
  final bool isCritical;

  AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    required this.downloadUrl,
    required this.websiteUrl,
    required this.title,
    required this.changelog,
    this.isCritical = false,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version']?.toString() ?? '2.0.4',
      buildNumber: json['build_number'] is int
          ? json['build_number']
          : int.tryParse(json['build_number']?.toString() ?? '7') ?? 7,
      releaseDate: json['release_date']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ??
          'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk',
      websiteUrl: json['website_url']?.toString() ??
          'https://github.com/karthiknataraj547/Water-pump-controller',
      title: json['title']?.toString() ?? 'HydroPulse Update Available',
      changelog: json['changelog'] is List
          ? (json['changelog'] as List).map((e) => e.toString()).toList()
          : <String>[],
      isCritical: json['is_critical'] == true,
    );
  }
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  // Dynamic installed version (defaults to active release v2.0.5 Build 8)
  String _currentVersion = '2.0.5';
  int _currentBuildNumber = 8;
  static String get currentVersion => _instance._currentVersion;
  static int get currentBuildNumber => _instance._currentBuildNumber;
  bool _initialized = false;

  // Global navigator key for showing dialog from anywhere (lifecycle, MQTT push, timers)
  GlobalKey<NavigatorState>? _navigatorKey;
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }
  BuildContext? get _globalContext => _navigatorKey?.currentContext;

  // Remote version endpoints
  static const String _githubRawVersionUrl =
      'https://raw.githubusercontent.com/karthiknataraj547/Water-pump-controller/main/version.json';
  static const String _vercelVersionUrl =
      'https://water-pump-controller.vercel.app/api/v1/app/version';

  bool _isChecking = false;
  bool get isChecking => _isChecking;
  bool _isDialogShowing = false;
  bool get isDialogShowing => _isDialogShowing;

  AppVersionInfo? _latestVersionInfo;
  AppVersionInfo? get latestVersionInfo => _latestVersionInfo;

  StreamSubscription<Map<String, dynamic>>? _mqttSub;
  Timer? _periodicTimer;

  /// Full lifecycle initialization for the App Update Engine
  void initialize({GlobalKey<NavigatorState>? navigatorKey}) {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    }
    initVersion();

    // 1. Listen for instant real-time OTA announcements over Cloud MQTT
    _mqttSub?.cancel();
    _mqttSub = mqttService.appUpdateStream.listen((data) {
      _handleIncomingMqttUpdate(data);
    });

    // 2. Schedule periodic background polling (every 15 minutes)
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      checkForUpdatesGlobally();
    });

    // 3. Perform initial startup check after smooth frame rendering
    Future.delayed(const Duration(seconds: 2), () {
      checkForUpdatesGlobally();
    });
  }

  /// Handles real-time MQTT OTA broadcasts from developer/console
  void _handleIncomingMqttUpdate(Map<String, dynamic> data) {
    try {
      final info = AppVersionInfo.fromJson(data);
      _latestVersionInfo = info;
      debugPrint('[AppUpdateService] MQTT OTA announcement received: v${info.version}+${info.buildNumber}');

      if (isVersionNewer(info.version, currentVersion,
          remoteBuild: info.buildNumber, currentBuild: currentBuildNumber)) {
        final ctx = _globalContext;
        if (ctx != null && ctx.mounted && !_isDialogShowing) {
          showUpdateDialog(ctx, info);
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error handling MQTT update payload: $e');
    }
  }

  /// Loads true version from the installed Android/iOS package
  Future<void> initVersion() async {
    if (_initialized) return;
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (pkg.version.isNotEmpty) {
        _currentVersion = pkg.version;
      }
      final parsedBuild = int.tryParse(pkg.buildNumber);
      if (parsedBuild != null) {
        _currentBuildNumber = parsedBuild;
      }
      _initialized = true;
      debugPrint('[AppUpdateService] Native package version: v$_currentVersion+$_currentBuildNumber');
    } catch (e) {
      debugPrint('[AppUpdateService] PackageInfo note: $e');
    }
  }

  /// Compares two semver strings: returns true if [remote] > [current] or build is newer
  bool isVersionNewer(String remote, String current, {int remoteBuild = 0, int currentBuild = 0}) {
    try {
      final remoteClean = remote.replaceAll(RegExp(r'[^0-9.]'), '');
      final currentClean = current.replaceAll(RegExp(r'[^0-9.]'), '');

      final rParts = remoteClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = currentClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final r = i < rParts.length ? rParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
      return remoteBuild > currentBuild;
    } catch (_) {
      return false;
    }
  }

  /// Checks for updates using GitHub raw (cache-busted) as primary, followed by backend
  Future<AppVersionInfo?> fetchLatestVersion() async {
    _isChecking = true;
    await initVersion();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // 1. Primary: GitHub Raw Manifest with timestamp cache-buster
    // Canonical real-time source of truth for developer pushes
    try {
      final cacheBusterUrl = '$_githubRawVersionUrl?t=$timestamp';
      final res = await _dio.get(
        cacheBusterUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        if (data is Map<String, dynamic>) {
          _latestVersionInfo = AppVersionInfo.fromJson(data);
          _isChecking = false;
          debugPrint('[AppUpdateService] Fetched from GitHub raw: v${_latestVersionInfo!.version}+${_latestVersionInfo!.buildNumber}');
          return _latestVersionInfo;
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] GitHub raw check notice: $e');
    }

    // 2. Secondary: Active Backend API endpoint
    try {
      final backendUrl = '${AppConstants.activeApiBaseUrl}/app/version?t=$timestamp';
      final res = await _dio.get(backendUrl);
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        if (data is Map<String, dynamic>) {
          _latestVersionInfo = AppVersionInfo.fromJson(data);
          _isChecking = false;
          return _latestVersionInfo;
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Active backend check notice: $e');
    }

    // 3. Tertiary: Cloud Backend (Vercel)
    try {
      final res = await _dio.get('$_vercelVersionUrl?t=$timestamp');
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        if (data is Map<String, dynamic>) {
          _latestVersionInfo = AppVersionInfo.fromJson(data);
          _isChecking = false;
          return _latestVersionInfo;
        }
      }
    } catch (_) {}

    _isChecking = false;
    return null;
  }

  /// Global update check: can be called from anywhere without explicit BuildContext
  Future<void> checkForUpdatesGlobally() async {
    if (_isChecking || _isDialogShowing) return;
    final latest = await fetchLatestVersion();

    if (latest != null &&
        isVersionNewer(latest.version, currentVersion,
            remoteBuild: latest.buildNumber, currentBuild: currentBuildNumber)) {
      final ctx = _globalContext;
      if (ctx != null && ctx.mounted && !_isDialogShowing) {
        showUpdateDialog(ctx, latest);
      }
    }
  }

  /// Explicit / Manual Check trigger with BuildContext
  Future<void> checkForUpdates(BuildContext context, {bool isManual = false}) async {
    await initVersion();
    final latest = await fetchLatestVersion();
    if (!context.mounted) return;

    if (latest != null &&
        isVersionNewer(latest.version, currentVersion,
            remoteBuild: latest.buildNumber, currentBuild: currentBuildNumber)) {
      showUpdateDialog(context, latest);
    } else if (isManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
              Text(
                'HydroPulse is up to date (v$currentVersion Build $currentBuildNumber)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: AppTheme.darkCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  /// Displays interactive in-app update popup dialog with detailed changelog
  void showUpdateDialog(BuildContext context, AppVersionInfo info) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: !info.isCritical,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
          elevation: 20,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Visual Header with Gradient Icon
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0072FF).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.system_update_alt_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Update Available!',
                                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0072FF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF0072FF).withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  'v${info.version} (Build ${info.buildNumber})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Current: v$currentVersion',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Release Title
                Text(
                  info.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                if (info.releaseDate.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Released on ${info.releaseDate}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Changelog Header & List Container ("what all the changes has been made")
                Row(
                  children: [
                    const Icon(Icons.format_list_bulleted_rounded, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      "What's New in this Version:",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white70 : Colors.black87,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0A101D) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                  ),
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: info.changelog.isEmpty
                      ? const Text('Bug fixes, performance improvements, and system enhancements.')
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: info.changelog.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 8,
                            thickness: 0.5,
                            color: Colors.white10,
                          ),
                          itemBuilder: (context, idx) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 3),
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 14,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      info.changelog[idx],
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 20),

                // Primary Action Button: In-App Download & Install
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    startInAppDownloadAndInstall(context, info);
                  },
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text('Download & Update Now (v${info.version})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),

                // Remind Later Option (if non-critical)
                if (!info.isCritical) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Remind Me Later',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  /// In-App Direct APK Downloader with real-time byte progress and auto-installer trigger
  Future<void> startInAppDownloadAndInstall(BuildContext context, AppVersionInfo info) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cancelToken = CancelToken();

    double progress = 0.0;
    String status = 'Connecting to release server...';
    String byteInfo = '0.0 MB / 55.4 MB';
    bool isCompleted = false;
    String? errorMessage;
    String? localApkPath;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (builderCtx, setDialogState) {
            void downloadApk() async {
              try {
                final tempDir = await getTemporaryDirectory();
                final filePath = '${tempDir.path}/HydroPulse_v${info.version}.apk';
                localApkPath = filePath;

                final downloadDio = Dio();
                await downloadDio.download(
                  info.downloadUrl,
                  filePath,
                  cancelToken: cancelToken,
                  onReceiveProgress: (received, total) {
                    if (total != -1) {
                      setDialogState(() {
                        progress = received / total;
                        final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
                        final totMB = (total / (1024 * 1024)).toStringAsFixed(1);
                        byteInfo = '$recMB MB / $totMB MB';
                        status = 'Downloading HydroPulse v${info.version}...';
                      });
                    }
                  },
                );

                setDialogState(() {
                  progress = 1.0;
                  status = 'Download complete! Launching Android package installer...';
                  isCompleted = true;
                });

                // Launch native Android package installer
                final result = await OpenFilex.open(
                  filePath,
                  type: 'application/vnd.android.package-archive',
                );

                if (result.type != ResultType.done) {
                  debugPrint('[Update] OpenFilex notice: ${result.message}. Opening browser fallback...');
                  final uri = Uri.parse(info.downloadUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (e) {
                if (CancelToken.isCancel(e as dynamic)) {
                  debugPrint('[Update] Download cancelled by user');
                  return;
                }
                debugPrint('[Update] Direct in-app download notice: $e');
                setDialogState(() {
                  errorMessage = 'Direct download note: ${e.toString().split('\n').first}';
                });
                // Fallback to external browser launcher
                final uri = Uri.parse(info.downloadUrl);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (progress == 0.0 && errorMessage == null && !isCompleted) {
                downloadApk();
              }
            });

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check_circle_rounded : Icons.system_update_rounded,
                        color: AppTheme.accent,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isCompleted ? 'Ready to Install!' : 'Downloading Update',
                      style: Theme.of(builderCtx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      style: Theme.of(builderCtx).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 8,
                        backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text(
                          byteInfo,
                          style: Theme.of(builderCtx).textTheme.bodySmall?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (isCompleted)
                      ElevatedButton.icon(
                        onPressed: () {
                          if (localApkPath != null) {
                            OpenFilex.open(
                              localApkPath!,
                              type: 'application/vnd.android.package-archive',
                            );
                          }
                        },
                        icon: const Icon(Icons.install_mobile_rounded),
                        label: const Text('Open Package Installer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () {
                          cancelToken.cancel();
                          Navigator.of(builderCtx).pop();
                        },
                        child: const Text('Cancel Download'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

final appUpdateService = AppUpdateService();
