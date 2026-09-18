import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/hardware/hardware_state_service.dart';
import 'core/alerts/overflow_alert_service.dart';
import 'core/constants/app_constants.dart';
import 'core/network/internet_connectivity_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/tank_control/presentation/tank_control_screen.dart';
import 'features/hardware/presentation/hardware_screen.dart';
import 'features/analytics/presentation/analytics_screen.dart';
import 'features/automation/presentation/automation_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/pump_control/presentation/pump_control_screen.dart';
import 'features/provisioning/presentation/provisioning_wizard_screen.dart';
import 'features/notifications/presentation/notifications_screen.dart';
import 'shared/widgets/animated_pressable.dart';
import 'core/update/app_update_service.dart';
import 'core/notifications/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final authStateNotifier = ValueNotifier<String?>(null);
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

const safeSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  ),
);

Future<String?> readStoredAccessToken() async {
  try {
    final token = await safeSecureStorage.read(key: AppConstants.keyAccessToken).timeout(
      const Duration(milliseconds: 600),
      onTimeout: () => null,
    );
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }
  } catch (e) {
    debugPrint('[Auth] FlutterSecureStorage read error: $e');
  }

  // Resilient fallback to SharedPreferences
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyAccessToken);
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }
  } catch (_) {}
  return null;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: authStateNotifier,
    redirect: (context, state) {
      final token = authStateNotifier.value;
      final isLoggingIn = state.matchedLocation == '/login';

      if ((token == null || token.isEmpty) && !isLoggingIn) {
        return '/login';
      }
      if (token != null && token.isNotEmpty && isLoggingIn) {
        return '/dashboard';
      }
      return null;
    },
    errorBuilder: (context, state) {
      return Scaffold(
        backgroundColor: const Color(0xFF070B14),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.water_drop_rounded, color: Color(0xFF00E5FF), size: 56),
                const SizedBox(height: 16),
                const Text(
                  'HydroPulse Loading Recovery',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  state.error?.toString() ?? 'Routing recovery in progress',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => context.go('/login'),
                  child: const Text('Open Login Screen'),
                ),
              ],
            ),
          ),
        ),
      );
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) {
          final token = authStateNotifier.value;
          return (token != null && token.isNotEmpty) ? '/dashboard' : '/login';
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          // 1. Hydro Hub Dashboard Branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // 2. Tank Control Branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tank-control',
                builder: (context, state) => const TankControlScreen(),
              ),
            ],
          ),
          // 3. Hardware Nodes Branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/hardware',
                builder: (context, state) => const HardwareScreen(),
              ),
            ],
          ),
          // 4. Analytics Telemetry Branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
          // 5. Automation Rules Branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/automation',
                builder: (context, state) => const AutomationScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/pump-control',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PumpControlScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/provisioning',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ProvisioningWizardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NotificationsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            );
          },
        ),
      ),
    ],
  );

  runApp(ProviderScope(child: HydroPulseApp(router: router)));
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final token = await readStoredAccessToken();
      if (token != null && token.isNotEmpty) {
        authStateNotifier.value = token;
      }
    } catch (e) {
      debugPrint('[Auth] Initial token lookup failure: $e');
    }

    try {
      hardwareStateService.initialize();
      overflowAlertService.initialize();
      appUpdateService.initialize(navigatorKey: rootNavigatorKey);
      pushNotificationService.initialize();
    } catch (e) {
      debugPrint('[Init] Post-frame services initialization notice: $e');
    }
  });
}

class HydroPulseApp extends StatefulWidget {
  final GoRouter router;
  const HydroPulseApp({Key? key, required this.router}) : super(key: key);

  @override
  State<HydroPulseApp> createState() => _HydroPulseAppState();
}

class _HydroPulseAppState extends State<HydroPulseApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        debugPrint('[AppLifecycle] Resumed - Performing real-time update check...');
        appUpdateService.checkForUpdatesGlobally();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeNotifier.instance,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'HydroPulse IoT',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeNotifier.instance.themeMode,
          routerConfig: widget.router,
        );
      },
    );
  }
}

class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainScaffold({Key? key, required this.navigationShell}) : super(key: key);

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  StreamSubscription<LiveAppAlert>? _alertSub;

  @override
  void initState() {
    super.initState();
    hardwareStateService.addListener(_onHardwareStateChanged);
    internetConnectivityService.addListener(_onInternetStateChanged);

    // Live Notification Alerts Stream
    _alertSub = hardwareStateService.alertStream.listen((alert) {
      if (!mounted) return;
      if (!pushNotificationService.isNotificationAllowed(alert.type)) return;
      if (alert.type == 'motor') return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                alert.level == AlertLevel.danger
                    ? Icons.warning_rounded
                    : (alert.level == AlertLevel.warning ? Icons.info_rounded : Icons.check_circle_rounded),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      alert.message,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: alert.level == AlertLevel.danger
              ? AppTheme.danger
              : (alert.level == AlertLevel.warning ? AppTheme.accentAmber : AppTheme.waterBlueDark),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    });
  }

  @override
  void dispose() {
    hardwareStateService.removeListener(_onHardwareStateChanged);
    internetConnectivityService.removeListener(_onInternetStateChanged);
    _alertSub?.cancel();
    super.dispose();
  }

  void _onHardwareStateChanged() {
    if (mounted) setState(() {});
  }

  void _onInternetStateChanged() {
    if (mounted) setState(() {});
  }

  void _onItemTapped(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  Widget _buildNoInternetBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(isDark ? 0.9 : 0.85),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'No Internet Connection',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.navigationShell.currentIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final hasHardware = hardwareStateService.activeDevice != null;
    final isOnline = internetConnectivityService.isConnected;

    // IF NO HARDWARE ADDED: Hide bottom navigation bar completely & show empty state body
    if (!hasHardware) {
      return Scaffold(
        body: Column(
          children: [
            if (!isOnline) _buildNoInternetBanner(isDark),
            Expanded(child: _NoGatewayLinkedView(isDark: isDark, colorScheme: colorScheme)),
          ],
        ),
        bottomNavigationBar: null,
      );
    }

    // IF HARDWARE IS ADDED: Show full navigation bar with all 5 tabs
    return Scaffold(
      body: Column(
        children: [
          if (!isOnline) _buildNoInternetBanner(isDark),
          Expanded(child: widget.navigationShell),
        ],
      ),
      bottomNavigationBar: _AnimatedShiftingBottomBar(
        selectedIndex: selectedIndex,
        onTabSelected: _onItemTapped,
        isDark: isDark,
        colorScheme: colorScheme,
      ),
    );
  }
}

// ============================================================================
// ANIMATED SHIFTING BOTTOM BAR WITH SLIDING PILL INDICATOR
// ============================================================================
class _AnimatedNavTabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _AnimatedNavTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _AnimatedShiftingBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool isDark;
  final ColorScheme colorScheme;

  const _AnimatedShiftingBottomBar({
    Key? key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.isDark,
    required this.colorScheme,
  }) : super(key: key);

  static const List<_AnimatedNavTabItem> _tabs = [
    _AnimatedNavTabItem(
      icon: Icons.waves_outlined,
      selectedIcon: Icons.waves_rounded,
      label: 'Hydro Hub',
    ),
    _AnimatedNavTabItem(
      icon: Icons.water_drop_outlined,
      selectedIcon: Icons.water_drop_rounded,
      label: 'Tank Control',
    ),
    _AnimatedNavTabItem(
      icon: Icons.developer_board_outlined,
      selectedIcon: Icons.developer_board_rounded,
      label: 'Device',
    ),
    _AnimatedNavTabItem(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.query_stats_rounded,
      label: 'Telemetry',
    ),
    _AnimatedNavTabItem(
      icon: Icons.bolt_outlined,
      selectedIcon: Icons.bolt_rounded,
      label: 'Autonomous',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(isDark ? 0.22 : 0.15),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.30 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / _tabs.length;
              return Stack(
                children: [
                  // Animated Shifting Pill Indicator with spring / easeOutCubic curve
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: selectedIndex * tabWidth + 5,
                    top: 6,
                    width: tabWidth - 10,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(isDark ? 0.16 : 0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(isDark ? 0.35 : 0.25),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(isDark ? 0.20 : 0.08),
                            blurRadius: 8,
                            spreadRadius: 0.5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Interactive Tab Items
                  Row(
                    children: List.generate(_tabs.length, (index) {
                      final tab = _tabs[index];
                      final isSelected = selectedIndex == index;
                      final isAccentTab = index == 4; // Autonomous tab
                      final activeColor = isAccentTab ? AppTheme.accent : colorScheme.primary;

                      return Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTabSelected(index);
                          },
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedScale(
                                  scale: isSelected ? 1.15 : 1.0,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    isSelected ? tab.selectedIcon : tab.icon,
                                    size: 21,
                                    color: isSelected
                                        ? activeColor
                                        : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 250),
                                  style: TextStyle(
                                    fontSize: isSelected ? 11 : 10,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected
                                        ? activeColor
                                        : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                                    letterSpacing: 0.15,
                                  ),
                                  child: Text(
                                    tab.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// NO GATEWAY LINKED VIEW (RENDERED WHEN NO HARDWARE IS ADDED)
// ============================================================================
class _NoGatewayLinkedView extends StatefulWidget {
  final bool isDark;
  final ColorScheme colorScheme;

  const _NoGatewayLinkedView({
    Key? key,
    required this.isDark,
    required this.colorScheme,
  }) : super(key: key);

  @override
  State<_NoGatewayLinkedView> createState() => _NoGatewayLinkedViewState();
}

class _NoGatewayLinkedViewState extends State<_NoGatewayLinkedView> {
  String _userName = 'HydroPulse User';
  String _userEmail = '';
  String _initials = 'HP';
  AppVersionInfo? _latestVersionInfo;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadUserAccount();
    _checkAppUpdateStatus();
  }

  Future<void> _loadUserAccount() async {
    try {
      final name = await safeSecureStorage.read(key: AppConstants.keyUserName);
      final email = await safeSecureStorage.read(key: AppConstants.keyUserEmail);
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
          }
          if (email != null && email.isNotEmpty) {
            _userEmail = email.trim();
          }
          final parts = _userName.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
            _initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
          } else if (_userName.isNotEmpty) {
            _initials = _userName.substring(0, _userName.length >= 2 ? 2 : 1).toUpperCase();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _checkAppUpdateStatus({bool isManual = false}) async {
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

  Future<void> _handleLogout(BuildContext context) async {
    await safeSecureStorage.deleteAll();
    await hardwareStateService.onUserLogout();
    authStateNotifier.value = null;
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = widget.isDark;
    final colorScheme = widget.colorScheme;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;

    final isNewer = _latestVersionInfo != null &&
        appUpdateService.isVersionNewer(
          _latestVersionInfo!.version,
          AppUpdateService.currentVersion,
          remoteBuild: _latestVersionInfo!.buildNumber,
          currentBuild: AppUpdateService.currentBuildNumber,
        );

    return SafeArea(
      child: Column(
        children: [
          // 1. Top Bar with Brand, Settings shortcut, Theme toggle & Logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.water_drop_rounded, color: colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HydroPulse IoT',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Cloud Console v${AppUpdateService.currentVersion}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 22),
                      tooltip: 'Settings & Account',
                      onPressed: () => context.push('/settings'),
                    ),
                    IconButton(
                      icon: Icon(
                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        color: isDark ? AppTheme.warning : colorScheme.primary,
                        size: 22,
                      ),
                      tooltip: 'Toggle Theme',
                      onPressed: () => ThemeNotifier.instance.toggleTheme(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.danger),
                      tooltip: 'Sign Out',
                      onPressed: () => _handleLogout(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Scrollable Body containing Update Engine, Account, App Info & Add Hardware
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SYSTEM SETTINGS & APP UPDATES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ========================================================
                  // --- 1. APP UPDATE ENGINE & VERSION STATUS CARD ---
                  // ========================================================
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isNewer ? AppTheme.accent : cardBorder,
                        width: isNewer ? 1.5 : 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isNewer ? AppTheme.accent : Colors.black).withOpacity(isDark ? 0.25 : 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isNewer
                                          ? [const Color(0xFF00E5FF), const Color(0xFF0072FF)]
                                          : [colorScheme.primary.withOpacity(0.2), colorScheme.primary.withOpacity(0.1)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isNewer ? Icons.system_update_alt_rounded : Icons.system_update_rounded,
                                    color: isNewer ? Colors.white : colorScheme.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('App Version & Updates', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                    Text('Built-in OTA Update Engine', style: textTheme.bodySmall?.copyWith(fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: isNewer
                                    ? AppTheme.accent.withOpacity(0.2)
                                    : (isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isNewer ? AppTheme.accent : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                isNewer
                                    ? 'UPDATE READY'
                                    : 'v${AppUpdateService.currentVersion} • B${AppUpdateService.currentBuildNumber}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isNewer ? AppTheme.accent : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Update Status Alert Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isNewer
                                ? AppTheme.accent.withOpacity(0.1)
                                : (isDark ? const Color(0xFF0D1826) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isNewer ? AppTheme.accent.withOpacity(0.4) : cardBorder,
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
                        Divider(color: cardBorder, height: 1),
                        const SizedBox(height: 8),

                        _buildSettingRow('Installed Version', 'v${AppUpdateService.currentVersion}', context),
                        _buildSettingRow('Installed Build', '${AppUpdateService.currentBuildNumber}', context),
                        _buildSettingRow(
                          'Latest Cloud Release',
                          _latestVersionInfo != null
                              ? 'v${_latestVersionInfo!.version} (Build ${_latestVersionInfo!.buildNumber})'
                              : 'v${AppConstants.appVersion} (Build ${AppConstants.appBuildNumber})',
                          context,
                        ),
                        _buildSettingRow('Channel', 'Official Production Cloud (Vercel Edge)', context),
                        _buildSettingRow('Architecture', 'arm64-v8a / armeabi-v7a (Direct APK)', context),

                        // What's New Snippet if available
                        if (_latestVersionInfo != null && _latestVersionInfo!.changelog.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF090E18) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cardBorder, width: 0.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "What's New in v${_latestVersionInfo!.version}:",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ..._latestVersionInfo!.changelog.take(2).map((item) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('• ', style: TextStyle(color: AppTheme.accent, fontSize: 11)),
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.black54),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Action Buttons: Update Now or Check for Updates
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isNewer ? AppTheme.accent : colorScheme.primary,
                                  foregroundColor: isNewer ? Colors.black : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                ),
                                icon: _isCheckingUpdate
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Icon(
                                        isNewer ? Icons.download_rounded : Icons.refresh_rounded,
                                        size: 16,
                                      ),
                                label: Text(
                                  isNewer ? 'Download & Update Now' : 'Check for Updates',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                                onPressed: () {
                                  if (isNewer) {
                                    appUpdateService.showUpdateDialog(context, _latestVersionInfo!);
                                  } else {
                                    _checkAppUpdateStatus(isManual: true);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white70 : Colors.black87,
                                side: BorderSide(color: cardBorder, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                              ),
                              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                              label: const Text('Website APK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              onPressed: () async {
                                final uri = Uri.parse('https://water-pump-controller.vercel.app/releases/HydroPulse_v2.2.6_build30.apk');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ========================================================
                  // --- 2. ACCOUNT PROFILE CARD ---
                  // ========================================================
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cardBorder, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colorScheme.primary.withOpacity(0.12),
                              ),
                              child: Center(
                                child: Text(
                                  _initials,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName,
                                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _userEmail.isNotEmpty ? _userEmail : 'Authenticated User Session',
                                    style: textTheme.bodySmall?.copyWith(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: cardBorder, height: 1),
                        const SizedBox(height: 10),
                        _buildSettingRow('Cloud Sync', 'Database Session Synchronized', context),
                        _buildSettingRow('Role', 'Client Account Holder', context),
                        _buildSettingRow('Auth Protocol', 'PBKDF2-SHA512 Strict Server Auth', context),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white70 : Colors.black87,
                              side: BorderSide(color: cardBorder, width: 1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                            ),
                            icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                            label: const Text('Manage Account Preferences', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            onPressed: () => context.push('/settings'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ========================================================
                  // --- 3. APP INFORMATION & SYSTEM CARD ---
                  // ========================================================
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cardBorder, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('App Information', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                Text('Platform, Cloud Gateway & Protocols', style: textTheme.bodySmall?.copyWith(fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: cardBorder, height: 1),
                        const SizedBox(height: 10),
                        _buildSettingRow('Cloud Gateway', 'water-pump-controller.vercel.app', context),
                        _buildSettingRow('IoT MQTT Broker', 'broker.hivemq.com (Port 1883)', context),
                        _buildSettingRow('Architecture', 'FreeRTOS ESP32 • Flutter Cross-Platform', context),
                        _buildSettingRow('Network Link', 'Central Cloud Server Active', context),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white70 : Colors.black87,
                              side: BorderSide(color: cardBorder, width: 1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text('Open Full Settings & Diagnostics', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            onPressed: () => context.push('/settings'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ========================================================
                  // --- 4. HERO: ADD HARDWARE / GATEWAY BANNER ---
                  // ========================================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cardBorder, width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary.withOpacity(0.12),
                            border: Border.all(color: colorScheme.primary.withOpacity(0.3), width: 1.5),
                          ),
                          child: Center(
                            child: Icon(Icons.sensors_off_rounded, size: 32, color: colorScheme.primary),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'No Hardware Gateway Linked',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ready to monitor your agricultural borewell or overhead tank? Link your ESP32 controller over BLE to start live fluid simulation and automation.',
                          style: textTheme.bodySmall?.copyWith(
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        AnimatedPressable(
                          onTap: () => context.push('/provisioning'),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.3),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bluetooth_searching_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Add Device (Pair Hardware)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String label, String value, BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 11)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
