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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Safely determine initial token before router configuration
  String? initialToken;
  try {
    initialToken = await readStoredAccessToken();
  } catch (e) {
    debugPrint('[Auth] Initial token lookup failure: $e');
  }
  authStateNotifier.value = initialToken;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: (initialToken != null && initialToken.isNotEmpty) ? '/dashboard' : '/login',
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
  WidgetsBinding.instance.addPostFrameCallback((_) {
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
class _NoGatewayLinkedView extends StatelessWidget {
  final bool isDark;
  final ColorScheme colorScheme;

  const _NoGatewayLinkedView({
    Key? key,
    required this.isDark,
    required this.colorScheme,
  }) : super(key: key);

  Future<void> _handleLogout(BuildContext context) async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    await hardwareStateService.onUserLogout();
    authStateNotifier.value = null;
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            // Top Bar with Logo, Theme toggle & Logout
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.water_drop_rounded, color: colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'HydroPulse IoT',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        color: isDark ? AppTheme.warning : colorScheme.primary,
                        size: 22,
                      ),
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

            const Spacer(),

            // Animated Gateway Radar Graphics
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withOpacity(0.12),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.25),
                    blurRadius: 36,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.sensors_off_rounded,
                  size: 52,
                  color: colorScheme.primary,
                ),
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'You have not connected any device',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Link your ESP32 pump controller and tank sensors to monitor real-time water levels, actuators, and autonomous rules.',
              style: textTheme.bodyMedium?.copyWith(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Primary Button: Add Device
            AnimatedPressable(
              onTap: () => context.push('/provisioning'),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Add Device',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Help note
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                const SizedBox(width: 6),
                Text(
                  'Make sure your ESP32 Main Node has power and BLE is ready.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
