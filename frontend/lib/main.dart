import 'dart:async';
import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final router = GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) async {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: AppConstants.keyAccessToken);
      final isLoggingIn = state.matchedLocation == '/login';

      if (token == null && !isLoggingIn) {
        return '/login';
      }
      if (token != null && isLoggingIn) {
        return '/dashboard';
      }
      return null;
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
    hardwareStateService.initialize();
    overflowAlertService.initialize();
  });
}

class HydroPulseApp extends StatelessWidget {
  final GoRouter router;
  const HydroPulseApp({Key? key, required this.router}) : super(key: key);

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
          routerConfig: router,
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
  int _previousIndex = 0;
  StreamSubscription<LiveAppAlert>? _alertSub;

  @override
  void initState() {
    super.initState();
    hardwareStateService.addListener(_onHardwareStateChanged);
    internetConnectivityService.addListener(_onInternetStateChanged);

    // Live Notification Alerts Stream
    _alertSub = hardwareStateService.alertStream.listen((alert) {
      if (!mounted) return;
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
    _previousIndex = widget.navigationShell.currentIndex;
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outline.withOpacity(0.3),
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          height: 64,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: colorScheme.primary.withOpacity(isDark ? 0.12 : 0.08),
          selectedIndex: selectedIndex,
          onDestinationSelected: _onItemTapped,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          animationDuration: const Duration(milliseconds: 400),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.waves_outlined, size: 22, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
              selectedIcon: Icon(Icons.waves_rounded, color: colorScheme.primary, size: 23),
              label: 'Hydro Hub',
            ),
            NavigationDestination(
              icon: Icon(Icons.water_drop_outlined, size: 22, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
              selectedIcon: Icon(Icons.water_drop_rounded, color: colorScheme.primary, size: 23),
              label: 'Tank Control',
            ),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined, size: 22, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
              selectedIcon: Icon(Icons.hub_rounded, color: colorScheme.primary, size: 23),
              label: 'Nodes',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, size: 22, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
              selectedIcon: Icon(Icons.query_stats_rounded, color: colorScheme.primary, size: 23),
              label: 'Telemetry',
            ),
            NavigationDestination(
              icon: Icon(Icons.bolt_outlined, size: 22, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
              selectedIcon: Icon(Icons.bolt_rounded, color: AppTheme.accent, size: 23),
              label: 'Autonomous',
            ),
          ],
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
