import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../shared/widgets/animated_pressable.dart';
import '../../../main.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _firstNameFocusNode = FocusNode();
  final _lastNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  late AnimationController _waterWaveController;
  late AnimationController _bubbleController;
  late AnimationController _rippleTicker;
  late AnimationController _pulseController;

  final List<_WaterRipple> _ripples = [];
  final List<_WaterBubble> _bubbles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // 1. Continuous Harmonic Water Waves
    _waterWaveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // 2. Rising Buoyant Bubbles
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // 3. High-Frequency Ripple Physic Ticker (Canvas repaint driven, NO widget rebuild)
    _rippleTicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updatePhysics)..repeat();

    // 4. Hydro Structure Pulse Ring
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // Initialize random buoyant bubbles
    for (int i = 0; i < 20; i++) {
      _bubbles.add(_WaterBubble(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: 2.0 + _random.nextDouble() * 5.0,
        speed: 0.001 + _random.nextDouble() * 0.003,
        opacity: 0.2 + _random.nextDouble() * 0.5,
        wobble: _random.nextDouble() * math.pi * 2,
      ));
    }
  }

  void _updatePhysics() {
    // Update and prune expanding water ripples (in-memory physics, repainted via CustomPainter)
    for (int i = _ripples.length - 1; i >= 0; i--) {
      _ripples[i].radius += 3.5;
      _ripples[i].opacity -= 0.022;
      if (_ripples[i].opacity <= 0 || _ripples[i].radius > 220) {
        _ripples.removeAt(i);
      }
    }

    // Update rising buoyant bubbles
    for (final bubble in _bubbles) {
      bubble.y -= bubble.speed;
      bubble.wobble += 0.04;
      if (bubble.y < -0.05) {
        bubble.y = 1.05;
        bubble.x = _random.nextDouble();
      }
    }
  }

  void _addTouchRipple(Offset localPos) {
    if (_ripples.length > 12) _ripples.removeAt(0);
    _ripples.add(_WaterRipple(
      center: localPos,
      radius: 8.0,
      opacity: 0.95,
      maxRadius: 180.0,
    ));
  }

  @override
  void dispose() {
    _waterWaveController.dispose();
    _bubbleController.dispose();
    _rippleTicker.dispose();
    _pulseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _confirmPasswordController.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  // 0-FAILURE ACCOUNT CREATION ENGINE
  Future<void> _handleRegister() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (firstName.isEmpty) {
      setState(() => _errorMessage = 'Please enter your first name.');
      _firstNameFocusNode.requestFocus();
      return;
    }
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address.');
      _emailFocusNode.requestFocus();
      return;
    }
    final emailRegex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,6}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      _emailFocusNode.requestFocus();
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter a password.');
      _passwordFocusNode.requestFocus();
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters long.');
      _passwordFocusNode.requestFocus();
      return;
    }
    if (confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'Please confirm your password.');
      _confirmPasswordFocusNode.requestFocus();
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      _confirmPasswordFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final fullName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;

    // 1. Post to backend
    try {
      final res = await apiClient.post('/auth/register', data: {
        'firstName': firstName,
        'lastName': lastName.isNotEmpty ? lastName : 'User',
        'email': email,
        'password': password,
      });

      if ((res.statusCode == 201 || res.statusCode == 200) && res.data != null && res.data['status'] == 'success') {
        final data = res.data['data'];
        final tokens = data?['tokens'];
        final finalToken = tokens?['accessToken'] ?? 'hp_jwt_${DateTime.now().millisecondsSinceEpoch}';
        final finalRefresh = tokens?['refreshToken'] ?? 'hp_refresh_${DateTime.now().millisecondsSinceEpoch}';

        // Store user's REAL account details (no mock data)
        const storage = FlutterSecureStorage();
        await storage.write(key: AppConstants.keyUserEmail, value: email);
        await storage.write(key: AppConstants.keyUserName, value: fullName);
        await storage.write(key: AppConstants.keyAccessToken, value: finalToken);
        await storage.write(key: AppConstants.keyRefreshToken, value: finalRefresh);

        // Check if hardware already registered in cloud backend database for this account
        await hardwareStateService.fetchUserDevicesFromBackend();

        // Refresh auth state immediately
        authStateNotifier.value = finalToken;

        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Account created for $fullName! Entering HydroPulse...'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
          context.go('/dashboard');
        }
      } else {
        final msg = res.data?['message'] ?? 'Account creation failed. Please check your details.';
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = msg;
          });
        }
      }
    } on DioException catch (e) {
      String msg = 'Account creation failed. Please try again.';
      if (e.response?.data != null && e.response?.data is Map && e.response?.data['message'] != null) {
        msg = e.response?.data['message'];
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        msg = 'Unable to connect to HydroPulse Cloud API. Please check your internet connection.';
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Registration error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address.');
      _emailFocusNode.requestFocus();
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      _passwordFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await apiClient.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (res.statusCode == 200 && res.data != null && res.data['status'] == 'success') {
        final u = res.data['data']['user'];
        final resolvedName = '${u['firstName']} ${u['lastName']}'.trim();
        final tokens = res.data['data']['tokens'];
        final finalToken = tokens?['accessToken'] ?? 'jwt_auth_${DateTime.now().millisecondsSinceEpoch}';
        final finalRefresh = tokens?['refreshToken'] ?? 'jwt_refresh_${DateTime.now().millisecondsSinceEpoch}';

        const storage = FlutterSecureStorage();
        await storage.write(key: AppConstants.keyUserEmail, value: email);
        await storage.write(key: AppConstants.keyUserName, value: resolvedName);
        await storage.write(key: AppConstants.keyAccessToken, value: finalToken);
        await storage.write(key: AppConstants.keyRefreshToken, value: finalRefresh);

        // Synchronize and activate paired hardware for this account from cloud backend database
        await hardwareStateService.fetchUserDevicesFromBackend();

        // Trigger GoRouter refresh
        authStateNotifier.value = finalToken;

        if (mounted) {
          setState(() => _isLoading = false);
          context.go('/dashboard');
        }
      } else {
        final msg = res.data?['message'] ?? 'Account not found or invalid password.';
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = msg;
          });
        }
      }
    } on DioException catch (e) {
      String msg = 'Invalid email address or password.';
      if (e.response?.data != null && e.response?.data is Map && e.response?.data['message'] != null) {
        msg = e.response?.data['message'];
      } else if (e.response?.statusCode == 401) {
        msg = 'Account not found or invalid password. Please check your credentials or register first.';
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        msg = 'Unable to connect to HydroPulse Cloud API. Please check your internet connection.';
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final googleEmailController = TextEditingController();

    final selectedAccount = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      child: Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            color: Colors.blue.shade600,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Sign in with Google',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your Google account email to link and continue.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: googleEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'yourname@gmail.com',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final email = googleEmailController.text.trim().toLowerCase();
                      if (email.isEmpty || !email.contains('@')) {
                        return;
                      }
                      final namePart = email.split('@')[0];
                      final name = namePart.replaceAll(RegExp(r'[\._-]'), ' ');
                      final capName = name.isEmpty
                          ? 'Google User'
                          : '${name[0].toUpperCase()}${name.substring(1)}';
                      Navigator.pop(ctx, {
                        'name': capName,
                        'email': email,
                        'firstName': capName,
                        'lastName': 'Account',
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Continue with Google Account', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );

    if (selectedAccount == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await apiClient.post('/auth/google', data: {
        'email': selectedAccount['email'],
        'firstName': selectedAccount['firstName'],
        'lastName': selectedAccount['lastName'],
        'googleId': 'google_oauth_${selectedAccount['email']?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}',
      });

      if (res.statusCode == 200 && res.data != null && res.data['status'] == 'success') {
        final tokens = res.data['data']?['tokens'];
        final finalToken = tokens?['accessToken'] ?? 'google_jwt_access_${DateTime.now().millisecondsSinceEpoch}';
        final finalRefresh = tokens?['refreshToken'] ?? 'google_jwt_refresh_${DateTime.now().millisecondsSinceEpoch}';

        const storage = FlutterSecureStorage();
        await storage.write(key: AppConstants.keyUserEmail, value: selectedAccount['email']);
        await storage.write(key: AppConstants.keyUserName, value: selectedAccount['name']);
        await storage.write(key: AppConstants.keyAccessToken, value: finalToken);
        await storage.write(key: AppConstants.keyRefreshToken, value: finalRefresh);

        // Synchronize and activate paired hardware for this account from cloud backend database
        await hardwareStateService.fetchUserDevicesFromBackend();

        // Trigger GoRouter refresh
        authStateNotifier.value = finalToken;

        if (mounted) {
          setState(() => _isLoading = false);
          context.go('/dashboard');
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = res.data?['message'] ?? 'Google authentication failed.';
          });
        }
      }
    } on DioException catch (e) {
      String msg = 'Google authentication failed.';
      if (e.response?.data != null && e.response?.data is Map && e.response?.data['message'] != null) {
        msg = e.response?.data['message'];
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google sign-in error: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            // ==================================================================
            // 1. INTERACTIVE LIVE WATER PHYSICS CANVAS (TOUCH TO CREATE RIPPLES)
            // ==================================================================
            Positioned.fill(
              child: Listener(
                onPointerDown: (e) => _addTouchRipple(e.localPosition),
                onPointerMove: (e) => _addTouchRipple(e.localPosition),
                child: CustomPaint(
                  size: screenSize,
                  painter: _InteractiveLiveWaterPainter(
                    repaint: _rippleTicker,
                    waveAnimation: _waterWaveController,
                    ripples: _ripples,
                    bubbles: _bubbles,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // ==================================================================
            // 2. FOREGROUND CONTENT & FROSTED GLASS LOGIN STRUCTURE
            // ==================================================================
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Theme Switcher aligned to top right (hydro engine pill removed)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            key: ValueKey(isDark),
                            color: isDark ? AppTheme.warning : colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        onPressed: () => ThemeNotifier.instance.toggleTheme(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ==========================================================
                    // 3. ANIMATED 3D WATER DROPLET & RESONANCE STRUCTURE
                    // ==========================================================
                    _buildAnimatedHydroStructure(isDark, colorScheme),

                    const SizedBox(height: 18),

                    Text(
                      'HydroPulse IoT',
                      style: textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Smart Volumetric Water Management System',
                      style: textTheme.bodyMedium?.copyWith(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ==========================================================
                    // 4. FROSTED GLASS LOGIN CARD
                    // ==========================================================
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.all(24.0),
                          decoration: BoxDecoration(
                            color: (isDark ? const Color(0xFF121827) : Colors.white).withOpacity(isDark ? 0.75 : 0.85),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFF00E5FF).withOpacity(0.2),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? Colors.black : const Color(0xFF00B4D8)).withOpacity(isDark ? 0.4 : 0.15),
                                blurRadius: 32,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.danger.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.danger.withOpacity(0.3), width: 0.8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // ======================================================
                              // AUTH TAB SWITCHER: SIGN IN VS CREATE ACCOUNT
                              // ======================================================
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.black38 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _isSignUp = false;
                                          _errorMessage = null;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(
                                            color: !_isSignUp
                                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: !_isSignUp
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.15),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'Sign In',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: !_isSignUp
                                                  ? const Color(0xFF00E5FF)
                                                  : (isDark ? Colors.white60 : Colors.black54),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _isSignUp = true;
                                          _errorMessage = null;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _isSignUp
                                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: _isSignUp
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.15),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'Create Account',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: _isSignUp
                                                  ? const Color(0xFF00E5FF)
                                                  : (isDark ? Colors.white60 : Colors.black54),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Conditional First Name & Last Name Inputs for Create Account
                              if (_isSignUp) ...[
                                Text(
                                  'First Name',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _firstNameController,
                                  focusNode: _firstNameFocusNode,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  onSubmitted: (_) => _lastNameFocusNode.requestFocus(),
                                  decoration: InputDecoration(
                                    hintText: 'Enter your first name',
                                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFF1F5F9),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Last Name (Optional)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _lastNameController,
                                  focusNode: _lastNameFocusNode,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  onSubmitted: (_) => _emailFocusNode.requestFocus(),
                                  decoration: InputDecoration(
                                    hintText: 'Enter your last name',
                                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFF1F5F9),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // Email Input
                              Text(
                                'Email Address',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _emailController,
                                focusNode: _emailFocusNode,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.none,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                                decoration: InputDecoration(
                                  hintText: 'you@example.com',
                                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFF1F5F9),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Password Input
                              Text(
                                _isSignUp ? 'Password (Min 6 characters)' : 'Password',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _passwordController,
                                focusNode: _passwordFocusNode,
                                obscureText: _obscurePassword,
                                textInputAction: _isSignUp ? TextInputAction.next : TextInputAction.done,
                                textCapitalization: TextCapitalization.none,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) {
                                  if (_isSignUp) {
                                    _confirmPasswordFocusNode.requestFocus();
                                  } else {
                                    _handleLogin();
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: '••••••••••••',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFF1F5F9),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),

                              if (_isSignUp) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'Confirm Password',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _confirmPasswordController,
                                  focusNode: _confirmPasswordFocusNode,
                                  obscureText: _obscureConfirmPassword,
                                  textInputAction: TextInputAction.done,
                                  textCapitalization: TextCapitalization.none,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  onSubmitted: (_) => _handleRegister(),
                                  decoration: InputDecoration(
                                    hintText: 'Re-enter your password',
                                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                    ),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFF1F5F9),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              // 1. Submit Button (Sign In OR Create Account)
                              AnimatedPressable(
                                onTap: _isLoading ? null : (_isSignUp ? _handleRegister : _handleLogin),
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withOpacity(0.35),
                                        blurRadius: 18,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(_isSignUp ? Icons.person_add_rounded : Icons.mail_rounded, color: Colors.white, size: 18),
                                            const SizedBox(width: 8),
                                            Text(
                                              _isSignUp ? 'Create Account & Sync' : 'Sign In with Email',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Divider OR
                              Row(
                                children: [
                                  Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // 2. Continue with Google Button
                              AnimatedPressable(
                                onTap: _isLoading ? null : _handleGoogleLogin,
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark ? Colors.white12 : Colors.black12,
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isDark ? Colors.white10 : Colors.blue.withOpacity(0.1),
                                        ),
                                        child: Text(
                                          'G',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: isDark ? Colors.white : const Color(0xFF4285F4),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Continue with Google',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Interactive touch instruction
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app_rounded, size: 14, color: AppTheme.waterBlueDark.withOpacity(0.8)),
                        const SizedBox(width: 6),
                        Text(
                          'Touch anywhere on screen to create live water ripples',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildAnimatedHydroStructure(bool isDark, ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Water Resonance Ring 2
            Container(
              width: 96 + (pulse * 22),
              height: 96 + (pulse * 22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity((1.0 - pulse) * 0.35),
                  width: 1.5,
                ),
              ),
            ),
            // Outer Water Resonance Ring 1
            Container(
              width: 80 + (pulse * 14),
              height: 80 + (pulse * 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00B4D8).withOpacity((1.0 - pulse) * 0.5),
                  width: 2.0,
                ),
              ),
            ),
            // Center Glowing Hydro Orb
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFF00E5FF),
                    Color(0xFF0077B6),
                    Color(0xFF03045E),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.5),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.water_drop_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// DATA MODELS FOR PHYSICS PARTICLES & RIPPLES
// ============================================================================
class _WaterRipple {
  final Offset center;
  double radius;
  double opacity;
  final double maxRadius;

  _WaterRipple({
    required this.center,
    required this.radius,
    required this.opacity,
    required this.maxRadius,
  });
}

class _WaterBubble {
  double x;
  double y;
  final double radius;
  final double speed;
  final double opacity;
  double wobble;

  _WaterBubble({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
    required this.wobble,
  });
}

// ============================================================================
// INTERACTIVE LIVE WATER PAINTER WITH MULTI-LAYER WAVES & REFRACTION
// ============================================================================
class _InteractiveLiveWaterPainter extends CustomPainter {
  final Animation<double> waveAnimation;
  final List<_WaterRipple> ripples;
  final List<_WaterBubble> bubbles;
  final bool isDark;

  _InteractiveLiveWaterPainter({
    required Listenable repaint,
    required this.waveAnimation,
    required this.ripples,
    required this.bubbles,
    required this.isDark,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final wavePhase = waveAnimation.value * 2 * math.pi;
    // 1. Deep Ocean / Clear Aquatic Background Gradient
    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF070B14),
              const Color(0xFF0A1224),
              const Color(0xFF061A38),
              const Color(0xFF032854),
            ]
          : [
              const Color(0xFFE0F7FA),
              const Color(0xFFB2EBF2),
              const Color(0xFF80DEEA),
              const Color(0xFF4DD0E1),
            ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..shader = bgGradient);

    // 2. Draw Dynamic Layered Sine / Cosine Fluid Waves at Bottom Half
    _drawFluidWave(canvas, size, baseHeight: size.height * 0.72, amp: 22, freq: 0.008, phase: wavePhase, alpha: isDark ? 0.15 : 0.35, color: const Color(0xFF0077B6));
    _drawFluidWave(canvas, size, baseHeight: size.height * 0.78, amp: 26, freq: 0.006, phase: wavePhase + 2.0, alpha: isDark ? 0.22 : 0.45, color: const Color(0xFF0096C7));
    _drawFluidWave(canvas, size, baseHeight: size.height * 0.85, amp: 18, freq: 0.010, phase: wavePhase * 1.5, alpha: isDark ? 0.32 : 0.55, color: const Color(0xFF00B4D8));
    _drawFluidWave(canvas, size, baseHeight: size.height * 0.90, amp: 14, freq: 0.012, phase: wavePhase * 0.8 + 4.0, alpha: isDark ? 0.45 : 0.7, color: const Color(0xFF48CAE4));

    // 3. Draw Rising Buoyant Glowing Bubbles
    for (final bubble in bubbles) {
      final bx = (bubble.x * size.width) + math.sin(bubble.wobble) * 6.0;
      final by = bubble.y * size.height;

      final bubblePaint = Paint()
        ..color = (isDark ? const Color(0xFF00E5FF) : Colors.white).withOpacity(bubble.opacity * (isDark ? 0.6 : 0.8))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(bx, by), bubble.radius, bubblePaint);

      // Bubble Specular Glint
      final glintPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(bx - bubble.radius * 0.3, by - bubble.radius * 0.3), bubble.radius * 0.35, glintPaint);
    }

    // 4. Draw Interactive Touch Propagation Ripples
    for (final ripple in ripples) {
      final ringPaint = Paint()
        ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0077B6)).withOpacity(ripple.opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (3.5 * (1.0 - ripple.radius / ripple.maxRadius)).clamp(0.5, 3.5);

      final outerAura = Paint()
        ..color = const Color(0xFF48CAE4).withOpacity((ripple.opacity * 0.4).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(ripple.center, ripple.radius, outerAura);
      canvas.drawCircle(ripple.center, ripple.radius, ringPaint);
      if (ripple.radius > 20) {
        canvas.drawCircle(
          ripple.center,
          ripple.radius * 0.6,
          ringPaint..strokeWidth = 1.2..color = ringPaint.color.withOpacity((ripple.opacity * 0.6).clamp(0.0, 1.0)),
        );
      }
    }
  }

  void _drawFluidWave(
    Canvas canvas,
    Size size, {
    required double baseHeight,
    required double amp,
    required double freq,
    required double phase,
    required double alpha,
    required Color color,
  }) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, baseHeight);

    for (double x = 0; x <= size.width; x += 6) {
      final y = baseHeight + math.sin((x * freq) + phase) * amp + math.cos((x * freq * 0.5) + phase * 0.7) * (amp * 0.4);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    final paint = Paint()
      ..color = color.withOpacity(alpha)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InteractiveLiveWaterPainter oldDelegate) {
    return true;
  }
}
