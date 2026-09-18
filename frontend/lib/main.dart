import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
// INDUSTRIAL GROUNDED DOCKED BOTTOM BAR
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
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Hub',
    ),
    _AnimatedNavTabItem(
      icon: Icons.water_outlined,
      selectedIcon: Icons.water_rounded,
      label: 'Reservoir',
    ),
    _AnimatedNavTabItem(
      icon: Icons.memory_outlined,
      selectedIcon: Icons.memory_rounded,
      label: 'Hardware',
    ),
    _AnimatedNavTabItem(
      icon: Icons.query_stats_outlined,
      selectedIcon: Icons.query_stats_rounded,
      label: 'Telemetry',
    ),
    _AnimatedNavTabItem(
      icon: Icons.bolt_outlined,
      selectedIcon: Icons.bolt_rounded,
      label: 'Automation',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final borderCol = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final bgCol = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    return Container(
      decoration: BoxDecoration(
        color: bgCol,
        border: Border(top: BorderSide(color: borderCol, width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_tabs.length, (index) {
              final tab = _tabs[index];
              final isSelected = selectedIndex == index;
              const activeColor = AppTheme.primary;
              final inactiveColor = isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary;

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
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor.withOpacity(isDark ? 0.16 : 0.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isSelected ? tab.selectedIcon : tab.icon,
                            size: 20,
                            color: isSelected ? activeColor : inactiveColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? activeColor : inactiveColor,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// NO GATEWAY LINKED VIEW (INDUSTRIAL STANDBY HERO STATE)
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

  @override
  void initState() {
    super.initState();
    _loadUserAccount();
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
        });
      }
    } catch (_) {}
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
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;

    return SafeArea(
      child: Column(
        children: [
          // 1. Sleek Industrial Top Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.25), width: 0.8),
                      ),
                      child: const Icon(Icons.water_drop_rounded, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HydroPulse',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.slate,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Standby Mode',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        size: 20,
                        color: isDark ? AppTheme.warning : AppTheme.primary,
                      ),
                      tooltip: 'Toggle Theme',
                      onPressed: () => ThemeNotifier.instance.toggleTheme(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      tooltip: 'Settings & Updates',
                      onPressed: () => context.push('/settings'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.danger),
                      tooltip: 'Sign Out',
                      onPressed: () => _handleLogout(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(color: cardBorder, height: 1),

          // 2. Central Hero Standby Stage
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Hardware Controller Schematic Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorder, width: 0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Industrial Hardware Icon
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.08),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 1.2),
                              ),
                              child: const Icon(
                                Icons.developer_board_rounded,
                                size: 34,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Status Tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.slate.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.slate.withOpacity(0.25), width: 0.8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.link_off_rounded, size: 12, color: AppTheme.slate),
                                  SizedBox(width: 6),
                                  Text(
                                    'GATEWAY UNPAIRED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: AppTheme.slate,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            Text(
                              'No Pump Controller Connected',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: -0.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Connect a dual-core ESP32 hardware gateway via Bluetooth Low Energy (BLE) to activate real-time telemetry, volumetric fluid modeling, and automated safety lockouts.',
                              style: textTheme.bodySmall?.copyWith(
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                height: 1.5,
                                fontSize: 12.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 22),

                            // Primary Action Button: Pair Hardware
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                                label: const Text(
                                  'Pair Hardware Gateway',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                ),
                                onPressed: () => context.push('/provisioning'),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Secondary Action Button: Settings & Broker
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                  side: BorderSide(color: cardBorder, width: 0.8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.settings_outlined, size: 16),
                                label: const Text(
                                  'Open Settings & System Updates',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                                onPressed: () => context.push('/settings'),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Quick Account & System Summary Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder, width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                                  child: const Text('KN', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                                    Text(_userEmail.isNotEmpty ? _userEmail : 'Authenticated User', style: TextStyle(fontSize: 10.5, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary)),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Bottom Status Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              border: Border(top: BorderSide(color: cardBorder, width: 0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.accent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cloud API Connected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'v${AppConstants.appVersion} • B${AppConstants.appBuildNumber}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
