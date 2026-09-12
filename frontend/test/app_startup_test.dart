import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iot_water_pump_app/main.dart';
import 'package:iot_water_pump_app/features/auth/presentation/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Test HydroPulseApp initial pump into LoginScreen', (WidgetTester tester) async {
    final testRouter = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: HydroPulseApp(router: testRouter),
      ),
    );

    // Let the first frame render
    await tester.pump();

    // Verify LoginScreen rendered
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('HydroPulse IoT'), findsWidgets);
  });
}
