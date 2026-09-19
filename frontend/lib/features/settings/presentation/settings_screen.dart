import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../core/update/app_update_service.dart';
import '../../../main.dart';

enum SettingsCategoryFilter {
  all,
  account,
  updates,
  hardware,
  broker,
  notifications,
  system,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _userName = 'Loading Profile...';
  String _userEmail = '';
  String _deviceId = 'No Device Linked';
  String _initials = 'HP';
  AppVersionInfo? _latestVersionInfo;
  bool _isCheckingUpdate = false;

  SettingsCategoryFilter _activeFilter = SettingsCategoryFilter.all;

  // Track expanded state for each classified sub-tab
  final Map<String, bool> _expanded = {
    'account': true,
    'updates': true,
    'hardware': false,
    'broker': false,
    'notifications': false,
    'system': false,
  };

  @override
  void initState() {
    super.initState();
    hardwareStateService.addListener(_onStateChanged);
    _loadUserAccountDetails();
    _checkUpdateInfo();
  }

  @override
  void dispose() {
    hardwareStateService.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkUpdateInfo({bool isManual = false}) async {
    if (mounted) setState(() => _isCheckingUpdate = true);
    try {
      await appUpdateService.initVersion();
      final info = await appUpdateService.fetchLatestVersion();
      if (mounted) {
        setState(() {
          _latestVersionInfo = info;
          _isCheckingUpdate = false;
        });
      }
      if (isManual && mounted) {
        await appUpdateService.checkForUpdates(context, isManual: true);
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _loadUserAccountDetails() async {
    const storage = FlutterSecureStorage();
    final name = await storage.read(key: AppConstants.keyUserName);
    final email = await storage.read(key: AppConstants.keyUserEmail);
    final deviceId = await storage.read(key: AppConstants.keySelectedDeviceId);

    if (mounted) {
      setState(() {
        if (name != null && name.trim().isNotEmpty) {
          _userName = name.trim();
        } else if (email != null && email.isNotEmpty) {
          final prefix = email.split('@')[0];
          _userName = prefix.replaceAll(RegExp(r'[\._-]'), ' ');
          if (_userName.isNotEmpty) {
            _userName = '${_userName[0].toUpperCase()}${_userName.substring(1)}';
          }
        } else {
          _userName = 'HydroPulse User';
        }

        if (email != null && email.isNotEmpty) {
          _userEmail = email.trim();
        }

        if (deviceId != null && deviceId.isNotEmpty && deviceId != 'esp32_pump_main') {
          _deviceId = deviceId.trim();
        } else {
          _deviceId = 'No Hardware Linked';
        }

        final parts = _userName.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          _initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
        } else if (_userName.isNotEmpty) {
          _initials = _userName.substring(0, math.min(2, _userName.length)).toUpperCase();
        } else {
          _initials = 'HP';
        }
      });
    }
  }

  void _toggleCategory(String key) {
    setState(() {
      _expanded[key] = !(_expanded[key] ?? false);
    });
  }

  void _setAllExpanded(bool expand) {
    setState(() {
      for (final k in _expanded.keys) {
        _expanded[k] = expand;
      }
    });
  }

  bool _isCategoryVisible(SettingsCategoryFilter target) {
    if (_activeFilter == SettingsCategoryFilter.all) return true;
    return _activeFilter == target;
  }

  @override
  Widget build(BuildContext context) {
    final device = hardwareStateService.activeDevice;
    final isOnline = hardwareStateService.isHardwareOnline;
    final isMqttConnected = hardwareStateService.isMqttConnected;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isNewer = _latestVersionInfo != null &&
        appUpdateService.isVersionNewer(
          _latestVersionInfo!.version,
          AppUpdateService.currentVersion,
          remoteBuild: _latestVersionInfo!.buildNumber,
          currentBuild: AppUpdateService.currentBuildNumber,
        );

    final allExpanded = _expanded.values.every((v) => v);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings & Config', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('Classified System Sub-Tabs', style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              allExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: 22,
            ),
            tooltip: allExpanded ? 'Collapse All Sub-Tabs' : 'Expand All Sub-Tabs',
            onPressed: () => _setAllExpanded(!allExpanded),
          ),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? AppTheme.accentAmber : colorScheme.primary,
              size: 22,
            ),
            tooltip: 'Switch Theme',
            onPressed: () => ThemeNotifier.instance.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. CLASSIFIED SUB-TAB CAROUSEL FILTER
          _buildCategoryFilterBar(isDark, colorScheme),

          // 2. SCROLLABLE CLASSIFIED DOWNWARD SUB-TABS
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sub-header summary row
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, bottom: 12.0, right: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getFilterTitle(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        InkWell(
                          onTap: () => _setAllExpanded(!allExpanded),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              allExpanded ? 'Collapse All ⌄' : 'Expand All ⌃',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // SUB-TAB 1: ACCOUNT & USER PROFILE
                  if (_isCategoryVisible(SettingsCategoryFilter.account))
                    _buildSubTabCard(
                      keyId: 'account',
                      icon: Icons.person_pin_rounded,
                      iconColor: const Color(0xFF0284C7),
                      iconBg: const [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                      title: 'Account & Security Profile',
                      subtitle: _userName,
                      tagText: 'AUTHENTICATED',
                      tagColor: const Color(0xFF10B981),
                      isDark: isDark,
                      colorScheme: colorScheme,
                      child: _buildAccountSubTabBody(isDark, colorScheme, textTheme),
                    ),

                  // SUB-TAB 2: APP VERSION & IN-APP OTA ENGINE
                  if (_isCategoryVisible(SettingsCategoryFilter.updates))
                    _buildSubTabCard(
                      keyId: 'updates',
                      icon: isNewer ? Icons.system_update_alt_rounded : Icons.system_update_rounded,
                      iconColor: isNewer ? AppTheme.accent : const Color(0xFF8B5CF6),
                      iconBg: isNewer
                          ? const [Color(0xFF00E5FF), Color(0xFF0072FF)]
                          : const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                      title: 'App Updates & OTA Engine',
                      subtitle: 'v${AppUpdateService.currentVersion} • Build ${AppUpdateService.currentBuildNumber}',
                      tagText: isNewer ? 'UPDATE READY' : 'UP TO DATE',
                      tagColor: isNewer ? AppTheme.accent : const Color(0xFF10B981),
                      isDark: isDark,
                      colorScheme: colorScheme,
                      child: _buildUpdatesSubTabBody(isDark, colorScheme, textTheme, isNewer),
                    ),

                  // SUB-TAB 3: HARDWARE GATEWAY & BLE NODES
                  if (_isCategoryVisible(SettingsCategoryFilter.hardware))
                    _buildSubTabCard(
                      keyId: 'hardware',
                      icon: Icons.developer_board_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      iconBg: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                      title: 'Hardware Gateway & BLE Nodes',
                      subtitle: device != null ? 'ESP32 (${device.id})' : 'No Gateway Linked',
                      tagText: device != null ? (isOnline ? 'ONLINE' : 'OFFLINE') : 'UNPAIRED',
                      tagColor: device != null ? (isOnline ? const Color(0xFF10B981) : AppTheme.danger) : Colors.grey,
                      isDark: isDark,
                      colorScheme: colorScheme,
                      child: _buildHardwareSubTabBody(isDark, colorScheme, textTheme, device, isOnline),
                    ),

                  // SUB-TAB 4: CLOUD MQTT BROKER & SYNC
                  if (_isCategoryVisible(SettingsCategoryFilter.broker))
                    _buildSubTabCard(
                      keyId: 'broker',
                      icon: Icons.cloud_sync_rounded,
                      iconColor: const Color(0xFF06B6D4),
                      iconBg: const [Color(0xFF06B6D4), Color(0xFF0891B2)],
                      title: 'Cloud MQTT Broker & Telemetry',
                      subtitle: hardwareStateService.brokerHost,
                      tagText: isMqttConnected ? 'CONNECTED' : 'OFFLINE',
                      tagColor: isMqttConnected ? AppTheme.accent : AppTheme.danger,
                      isDark: isDark,
                      colorScheme: colorScheme,
                      child: _buildBrokerSubTabBody(isDark, colorScheme, textTheme, isMqttConnected),
                    ),

                  // SUB-TAB 5: SMART PUSH ALERTS & NOTIFICATIONS
                  if (_isCategoryVisible(SettingsCategoryFilter.notifications))
                    _buildSubTabCard(
                      keyId: 'notifications',
                      icon: Icons.notifications_active_rounded,
                      iconColor: const Color(0xFFEC4899),
                      iconBg: const [Color(0xFFEC4899), Color(0xFFDB2777)],
                      title: 'Smart Push Alerts & Rules',
                      subtitle: 'Motor, volume & safety threshold alerts',
                      tagText: '5 CHANNELS',
                      tagColor: const Color(0xFFEC4899),
                      isDark: isDark,
                      colorScheme: colorScheme,
                      child: _buildNotificationsSubTabBody(isDark, colorScheme, textTheme),
                    ),

                  // SUB-TAB 6: SYSTEM PREFERENCES & DIAGNOSTICS
                  if (_isCategoryVisible(SettingsCategoryFilter.system))
                    _buildSubTabCard(
                      keyId: 'system',
                      icon: Icons.tune_rounded,
                      iconColor: const Color(0xFF64748B),
                      iconBg: const [Color(0xFF64748B), Color(0xFF475569)],
                      title: 'System Preferences & Maintenance',
                      subtitle: 'Theme, memory cache & session logout',
                      tagText: 'STABLE',
                      tagColor: const Color(0xFF64748B),
                      isDark: isDark,
                      colorScheme: colorScheme,
                      child: _buildSystemSubTabBody(isDark, colorScheme, textTheme),
                    ),

                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TOP CLASSIFIED CATEGORY FILTER PILL BAR
  // ==========================================================================
  Widget _buildCategoryFilterBar(bool isDark, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
            width: 0.8,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Row(
          children: [
            _buildFilterPill(SettingsCategoryFilter.all, 'All', Icons.dashboard_outlined, isDark, colorScheme),
            _buildFilterPill(SettingsCategoryFilter.account, 'Account', Icons.person_outline_rounded, isDark, colorScheme),
            _buildFilterPill(SettingsCategoryFilter.updates, 'Updates', Icons.system_update_rounded, isDark, colorScheme),
            _buildFilterPill(SettingsCategoryFilter.hardware, 'Hardware', Icons.developer_board_rounded, isDark, colorScheme),
            _buildFilterPill(SettingsCategoryFilter.broker, 'Broker', Icons.cloud_outlined, isDark, colorScheme),
            _buildFilterPill(SettingsCategoryFilter.notifications, 'Alerts', Icons.notifications_none_rounded, isDark, colorScheme),
            _buildFilterPill(SettingsCategoryFilter.system, 'System', Icons.tune_rounded, isDark, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(
    SettingsCategoryFilter filter,
    String label,
    IconData icon,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final isSelected = _activeFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _activeFilter = filter;
            if (filter != SettingsCategoryFilter.all) {
              final key = _filterToKey(filter);
              if (key != null) _expanded[key] = true;
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _filterToKey(SettingsCategoryFilter filter) {
    switch (filter) {
      case SettingsCategoryFilter.account:
        return 'account';
      case SettingsCategoryFilter.updates:
        return 'updates';
      case SettingsCategoryFilter.hardware:
        return 'hardware';
      case SettingsCategoryFilter.broker:
        return 'broker';
      case SettingsCategoryFilter.notifications:
        return 'notifications';
      case SettingsCategoryFilter.system:
        return 'system';
      case SettingsCategoryFilter.all:
        return null;
    }
  }

  String _getFilterTitle() {
    switch (_activeFilter) {
      case SettingsCategoryFilter.all:
        return 'CLASSIFIED SUB-TABS (6 ACTIVE)';
      case SettingsCategoryFilter.account:
        return 'CLASSIFICATION: ACCOUNT & SECURITY';
      case SettingsCategoryFilter.updates:
        return 'CLASSIFICATION: OTA UPDATE ENGINE';
      case SettingsCategoryFilter.hardware:
        return 'CLASSIFICATION: HARDWARE & BLE';
      case SettingsCategoryFilter.broker:
        return 'CLASSIFICATION: CLOUD MQTT BROKER';
      case SettingsCategoryFilter.notifications:
        return 'CLASSIFICATION: PUSH ALERTS & RULES';
      case SettingsCategoryFilter.system:
        return 'CLASSIFICATION: SYSTEM & SECURITY';
    }
  }

  // ==========================================================================
  // REUSABLE CLASSIFIED DOWNWARD SUB-TAB CARD (ACCORDION)
  // ==========================================================================
  Widget _buildSubTabCard({
    required String keyId,
    required IconData icon,
    required Color iconColor,
    required List<Color> iconBg,
    required String title,
    required String subtitle,
    required String tagText,
    required Color tagColor,
    required bool isDark,
    required ColorScheme colorScheme,
    required Widget child,
  }) {
    final isExpanded = _expanded[keyId] ?? false;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 14.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isExpanded ? colorScheme.primary.withOpacity(0.4) : cardBorder,
          width: isExpanded ? 1.2 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // DOWNWARD HEADER TOGGLE BAR
          InkWell(
            onTap: () => _toggleCategory(keyId),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(18),
              bottom: Radius.circular(isExpanded ? 0 : 18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Row(
                children: [
                  // Icon badge with gradient
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: iconBg,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),

                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Status badge pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: tagColor.withOpacity(0.35), width: 0.8),
                    ),
                    child: Text(
                      tagText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: tagColor,
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Rotating Downward Chevron
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isDark ? Colors.white60 : Colors.black54,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // DOWNWARD EXPANDING SUB-TAB CONTENT
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              children: [
                Divider(color: cardBorder, height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: child,
                ),
              ],
            ),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SUB-TAB BODY 1: ACCOUNT & USER PROFILE
  // ==========================================================================
  Widget _buildAccountSubTabBody(bool isDark, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [colorScheme.primary, const Color(0xFF00E5FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_userName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(_userEmail.isNotEmpty ? _userEmail : 'Authenticated User Session', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Active Account Holder • Database Verified',
                      style: TextStyle(color: colorScheme.primary, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
        const SizedBox(height: 10),
        _buildInfoRow('Account Holder', _userName),
        _buildInfoRow('Email Address', _userEmail.isNotEmpty ? _userEmail : 'N/A'),
        _buildInfoRow('Active Paired Gateway', _deviceId),
        _buildInfoRow('User Role', 'System Administrator'),
        _buildInfoRow('Session Security', 'JWT Bearer Signed'),
        _buildInfoRow('Production Backend', 'Vercel Serverless Edge API'),
      ],
    );
  }

  // ==========================================================================
  // SUB-TAB BODY 2: APP VERSION & IN-APP OTA ENGINE
  // ==========================================================================
  Widget _buildUpdatesSubTabBody(
    bool isDark,
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isNewer,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Update Status Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isNewer
                ? AppTheme.accent.withOpacity(0.12)
                : (isDark ? const Color(0xFF0D1826) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isNewer ? AppTheme.accent.withOpacity(0.4) : (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isNewer ? Icons.notification_important_rounded : Icons.verified_rounded,
                color: isNewer ? AppTheme.accent : const Color(0xFF10B981),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isNewer
                          ? 'New Version v${_latestVersionInfo!.version} (Build ${_latestVersionInfo!.buildNumber}) Ready'
                          : 'HydroPulse is Fully Up to Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: isNewer ? AppTheme.accent : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    Text(
                      isNewer
                          ? 'Direct in-app OTA update package is ready to download and install.'
                          : 'Installed v${AppUpdateService.currentVersion} (Build ${AppUpdateService.currentBuildNumber}) matches official cloud release.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _buildInfoRow('Installed Version', 'v${AppUpdateService.currentVersion}'),
        _buildInfoRow('Installed Build', '${AppUpdateService.currentBuildNumber}'),
        _buildInfoRow(
          'Latest Cloud Release',
          _latestVersionInfo != null
              ? 'v${_latestVersionInfo!.version} (Build ${_latestVersionInfo!.buildNumber})'
              : 'v${AppConstants.appVersion} (Build ${AppConstants.appBuildNumber})',
        ),

        if (_latestVersionInfo != null && _latestVersionInfo!.changelog.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "What's New in v${_latestVersionInfo!.version}:",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.accent),
                ),
                const SizedBox(height: 6),
                ..._latestVersionInfo!.changelog.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: AppTheme.accent, fontSize: 11)),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isNewer ? AppTheme.accent : colorScheme.primary,
                  foregroundColor: isNewer ? Colors.black : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isCheckingUpdate
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        isNewer ? Icons.download_rounded : Icons.refresh_rounded,
                        size: 18,
                      ),
                label: Text(
                  isNewer ? 'Download & Install Update' : 'Check for Updates',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                onPressed: () async {
                  if (isNewer && _latestVersionInfo != null) {
                    appUpdateService.showUpdateDialog(context, _latestVersionInfo!);
                  } else {
                    await _checkUpdateInfo(isManual: true);
                    if (mounted && _latestVersionInfo != null) {
                      appUpdateService.showUpdateDialog(context, _latestVersionInfo!);
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
                side: BorderSide(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
              label: const Text('Download APK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              onPressed: () async {
                final target = _latestVersionInfo?.downloadUrl ?? 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.3.1_build35.apk';
                final uri = Uri.parse(target);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================================
  // SUB-TAB BODY 3: HARDWARE GATEWAY & BLE NODES
  // ==========================================================================
  Widget _buildHardwareSubTabBody(
    bool isDark,
    ColorScheme colorScheme,
    TextTheme textTheme,
    dynamic device,
    bool isOnline,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (device == null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 20, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No physical ESP32 gateway currently paired with your account.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
              label: const Text('Pair ESP32 Gateway (BLE Wizard)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              onPressed: () => context.push('/provisioning'),
            ),
          ),
        ] else ...[
          _buildInfoRow('Gateway Device ID', device.id as String),
          _buildInfoRow('MAC Address', device.macAddress as String),
          _buildInfoRow('Live Status', isOnline ? 'ONLINE' : 'OFFLINE'),
          _buildInfoRow('Firmware Version', device.firmwareVersion as String),
          _buildInfoRow('FreeRTOS Architecture', 'Dual Core (ESP32-WROOM)'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Hardware Hub', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () => context.go('/hardware'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Unpair Gateway', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ConfirmationDialog(
                        title: 'Remove Hardware?',
                        content: 'This will send a reset signal to the ESP32 (${device.id}), unpair it, and remove it from your dashboard.',
                        confirmText: 'Remove',
                        confirmColor: AppTheme.danger,
                        onConfirm: () async {
                          await hardwareStateService.removeDevice();
                          if (mounted) {
                            context.go('/dashboard');
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // SUB-TAB BODY 4: CLOUD MQTT BROKER & TELEMETRY
  // ==========================================================================
  Widget _buildBrokerSubTabBody(
    bool isDark,
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isMqttConnected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Broker Host', hardwareStateService.brokerHost),
        _buildInfoRow('TCP Port', hardwareStateService.brokerPort.toString()),
        _buildInfoRow('WebSocket Port', '8000 (WSS Tunnel)'),
        _buildInfoRow('Topics Configured', 'pump/#, devices/# (QoS 0)'),
        _buildInfoRow('Client Protocol', 'MQTT v3.1.1 over TLS'),
        _buildInfoRow('Connection Status', isMqttConnected ? 'Active & Synchronized' : 'Offline / Reconnecting'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(Icons.tune_rounded, size: 16, color: colorScheme.primary),
            label: Text('Manage Broker Configuration in Hardware Tab', style: TextStyle(color: colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w700)),
            onPressed: () => context.go('/hardware'),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // SUB-TAB BODY 5: SMART PUSH ALERTS & NOTIFICATIONS
  // ==========================================================================
  Widget _buildNotificationsSubTabBody(
    bool isDark,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final border = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Motor Started Alert', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: const Text('Push notification when pump turns ON', style: TextStyle(fontSize: 11)),
          value: hardwareStateService.notifyMotorStart,
          activeColor: AppTheme.accent,
          onChanged: (val) {
            hardwareStateService.updateNotificationSettings(motorStart: val);
          },
        ),
        Divider(color: border, height: 1),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Motor Stopped Alert', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: const Text('Push notification when pump turns OFF at full capacity', style: TextStyle(fontSize: 11)),
          value: hardwareStateService.notifyMotorStop,
          activeColor: AppTheme.accent,
          onChanged: (val) {
            hardwareStateService.updateNotificationSettings(motorStop: val);
          },
        ),
        Divider(color: border, height: 1),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Low Water Level Alert (<20%)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: const Text('Immediate notification when tank reaches critical low', style: TextStyle(fontSize: 11)),
          value: hardwareStateService.notifyLowLevel,
          activeColor: AppTheme.accentAmber,
          onChanged: (val) {
            hardwareStateService.updateNotificationSettings(lowLevel: val);
          },
        ),
        Divider(color: border, height: 1),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tank Full / Overflow Warning (90%+)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: const Text('Warning alert before tank overflow condition occurs', style: TextStyle(fontSize: 11)),
          value: hardwareStateService.notifyHighLevel,
          activeColor: colorScheme.primary,
          onChanged: (val) {
            hardwareStateService.updateNotificationSettings(highLevel: val);
          },
        ),
        Divider(color: border, height: 1),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Autonomous Smart Automation Alert', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: const Text('Alert when automated rule triggers pump cycle', style: TextStyle(fontSize: 11)),
          value: hardwareStateService.notifyAutoMode,
          activeColor: colorScheme.primary,
          onChanged: (val) {
            hardwareStateService.updateNotificationSettings(autoMode: val);
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // SUB-TAB BODY 6: SYSTEM PREFERENCES & DIAGNOSTICS
  // ==========================================================================
  Widget _buildSystemSubTabBody(
    bool isDark,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final border = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: isDark ? AppTheme.accentAmber : colorScheme.primary,
            size: 22,
          ),
          title: const Text('Interface Appearance Theme', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text(isDark ? 'Dark Mode (Cyan Neon Cybernetic)' : 'Light Mode (Clean Clean Glass)', style: const TextStyle(fontSize: 11)),
          trailing: Switch.adaptive(
            value: isDark,
            activeColor: AppTheme.accent,
            onChanged: (_) => ThemeNotifier.instance.toggleTheme(),
          ),
        ),
        Divider(color: border, height: 1),
        _buildInfoRow('Security Architecture', 'Dual-Authentication Token Store'),
        _buildInfoRow('Database Engine', 'Cloud Serverless NoSQL Database'),
        _buildInfoRow('Telemetry Latency', '< 100ms Active RTT'),
        const SizedBox(height: 14),
        Divider(color: border, height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 22),
          title: const Text('Sign Out of HydroPulse Account', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: const Text('Clear local session token and lock app', style: TextStyle(fontSize: 11)),
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => ConfirmationDialog(
                title: 'Sign Out?',
                content: 'Are you sure you want to sign out of your HydroPulse account?',
                confirmText: 'Sign Out',
                confirmColor: AppTheme.danger,
                onConfirm: () async {
                  const storage = FlutterSecureStorage();
                  await storage.deleteAll();
                  await hardwareStateService.onUserLogout();
                  authStateNotifier.value = null;
                  if (mounted) {
                    context.go('/login');
                  }
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
