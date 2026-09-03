import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../constants/app_constants.dart';

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
      version: json['version'] ?? '2.0.1',
      buildNumber: json['build_number'] ?? 3,
      releaseDate: json['release_date'] ?? '',
      downloadUrl: json['download_url'] ??
          'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk',
      websiteUrl: json['website_url'] ??
          'https://github.com/karthiknataraj547/Water-pump-controller',
      title: json['title'] ?? 'New HydroPulse Version Available',
      changelog: json['changelog'] is List
          ? (json['changelog'] as List).map((e) => e.toString()).toList()
          : <String>[],
      isCritical: json['is_critical'] ?? false,
    );
  }
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  // Current installed version (matches pubspec.yaml)
  static const String currentVersion = '2.0.0';
  static const int currentBuildNumber = 2;

  // Remote version endpoints
  static const String _githubRawVersionUrl =
      'https://raw.githubusercontent.com/karthiknataraj547/Water-pump-controller/main/version.json';
  static const String _vercelVersionUrl =
      'https://water-pump-controller.vercel.app/api/v1/app/version';

  bool _isChecking = false;
  bool get isChecking => _isChecking;
  AppVersionInfo? _latestVersionInfo;
  AppVersionInfo? get latestVersionInfo => _latestVersionInfo;

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

  /// Checks for update from Backend / GitHub
  Future<AppVersionInfo?> fetchLatestVersion() async {
    _isChecking = true;

    // 1. Primary: Active Backend API endpoint
    try {
      final backendUrl = '${AppConstants.activeApiBaseUrl}/app/version';
      final res = await _dio.get(backendUrl);
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        _latestVersionInfo = AppVersionInfo.fromJson(data);
        _isChecking = false;
        return _latestVersionInfo;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Active backend check notice ($e). Trying cloud/GitHub fallback...');
    }

    // 2. Secondary: Vercel Cloud Backend
    try {
      final res = await _dio.get(_vercelVersionUrl);
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        _latestVersionInfo = AppVersionInfo.fromJson(data);
        _isChecking = false;
        return _latestVersionInfo;
      }
    } catch (_) {}

    // 3. Tertiary: GitHub Raw Manifest
    try {
      final res = await _dio.get(
        _githubRawVersionUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: {'Cache-Control': 'no-cache'},
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        _latestVersionInfo = AppVersionInfo.fromJson(data);
        _isChecking = false;
        return _latestVersionInfo;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] GitHub version check failed: $e');
    }

    _isChecking = false;
    return null;
  }

  /// Automatic or Manual Check trigger
  Future<void> checkForUpdates(BuildContext context, {bool isManual = false}) async {
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
              const Icon(Icons.check_circle, color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
              Text(
                'HydroPulse is up to date (v$currentVersion)',
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

  /// Displays interactive in-app update prompt
  void showUpdateDialog(BuildContext context, AppVersionInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.isCritical,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          elevation: 16,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Icon & Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: AppTheme.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update Available!',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'v${info.version}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Installed: v$currentVersion',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  info.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                // Changelog Box
                if (info.changelog.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkCardBorder
                            : AppTheme.lightCardBorder,
                        width: 0.5,
                      ),
                    ),
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: info.changelog.length,
                      itemBuilder: (context, idx) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Icon(Icons.arrow_right,
                                    size: 16, color: AppTheme.accent),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  info.changelog[idx],
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Action Buttons
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Downloading HydroPulse v${info.version} APK update...'),
                        backgroundColor: const Color(0xFF10B981),
                        duration: const Duration(seconds: 4),
                      ),
                    );

                    final uri = Uri.parse(info.downloadUrl);
                    bool launched = false;
                    try {
                      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('[Update] Launch error mode externalApplication: $e');
                    }
                    if (!launched) {
                      try {
                        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
                      } catch (e) {
                        debugPrint('[Update] Launch error mode platformDefault: $e');
                      }
                    }
                    if (!launched) {
                      try {
                        final webUri = Uri.parse(info.websiteUrl);
                        await launchUrl(webUri, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint('[Update] Launch error fallback to website: $e');
                      }
                    }
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download & Update Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),

                if (!info.isCritical) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Remind Me Later',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

final appUpdateService = AppUpdateService();
