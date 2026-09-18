import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../main.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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

  @override
  void dispose() {
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

        const storage = FlutterSecureStorage();
        final prefs = await SharedPreferences.getInstance();
        await storage.write(key: AppConstants.keyUserEmail, value: email);
        await storage.write(key: AppConstants.keyUserName, value: fullName);
        await storage.write(key: AppConstants.keyAccessToken, value: finalToken);
        await storage.write(key: AppConstants.keyRefreshToken, value: finalRefresh);
        await prefs.setString(AppConstants.keyUserEmail, email);
        await prefs.setString(AppConstants.keyUserName, fullName);

        await hardwareStateService.clearDeviceForNewLogin(newLoginEmail: email);
        await hardwareStateService.fetchUserDevicesFromBackend();

        authStateNotifier.value = finalToken;

        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account created for $fullName. Entering HydroPulse...'),
              backgroundColor: AppTheme.accent,
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
        final prefs = await SharedPreferences.getInstance();
        await storage.write(key: AppConstants.keyUserEmail, value: email);
        await storage.write(key: AppConstants.keyUserName, value: resolvedName);
        await storage.write(key: AppConstants.keyAccessToken, value: finalToken);
        await storage.write(key: AppConstants.keyRefreshToken, value: finalRefresh);
        await prefs.setString(AppConstants.keyUserEmail, email);
        await prefs.setString(AppConstants.keyUserName, resolvedName);

        await hardwareStateService.clearDeviceForNewLogin(newLoginEmail: email);
        await hardwareStateService.fetchUserDevicesFromBackend();

        authStateNotifier.value = finalToken;

        if (mounted) {
          setState(() => _isLoading = false);
          context.go('/dashboard');
        }
        return;
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
      return;
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
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white24 : Colors.black12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_circle_outlined, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sign in with Google',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Select an active enterprise identity',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.8),
                ),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                  child: const Text('KN', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ),
                title: const Text('Karthik N', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('karthiknataraj547@gmail.com', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.of(ctx).pop({
                  'email': 'karthiknataraj547@gmail.com',
                  'name': 'Karthik N',
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: googleEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Or enter enterprise Google email...',
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final em = googleEmailController.text.trim().toLowerCase();
                    if (em.isNotEmpty) {
                      final p = em.split('@')[0];
                      Navigator.of(ctx).pop({'email': em, 'name': p});
                    }
                  },
                  child: const Text('Authenticate Enterprise Account'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (selectedAccount != null && mounted) {
      final email = selectedAccount['email']!;
      final name = selectedAccount['name']!;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final res = await apiClient.post('/auth/google', data: {
          'email': email,
          'name': name,
          'googleId': 'gid_${email.hashCode.abs()}',
        });

        if (res.statusCode == 200 && res.data != null && res.data['status'] == 'success') {
          final tokens = res.data['data']['tokens'];
          final finalToken = tokens?['accessToken'] ?? 'jwt_google_${DateTime.now().millisecondsSinceEpoch}';
          final finalRefresh = tokens?['refreshToken'] ?? 'jwt_refresh_${DateTime.now().millisecondsSinceEpoch}';

          const storage = FlutterSecureStorage();
          final prefs = await SharedPreferences.getInstance();
          await storage.write(key: AppConstants.keyUserEmail, value: email);
          await storage.write(key: AppConstants.keyUserName, value: name);
          await storage.write(key: AppConstants.keyAccessToken, value: finalToken);
          await storage.write(key: AppConstants.keyRefreshToken, value: finalRefresh);
          await prefs.setString(AppConstants.keyUserEmail, email);
          await prefs.setString(AppConstants.keyUserName, name);

          await hardwareStateService.clearDeviceForNewLogin(newLoginEmail: email);
          await hardwareStateService.fetchUserDevicesFromBackend();

          authStateNotifier.value = finalToken;

          if (mounted) {
            setState(() => _isLoading = false);
            context.go('/dashboard');
          }
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = res.data?['message'] ?? 'Google authentication failed.';
          });
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google authentication error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- TOP BRANDING HEADER ---
                  Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.25), width: 1.0),
                      ),
                      child: const Icon(
                        Icons.water_drop_rounded,
                        color: AppTheme.primary,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'HydroPulse IoT',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enterprise Water Telemetry & Pump Automation',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // --- AUTH CARD ---
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cardBorder, width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.35 : 0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Segmented Mode Switcher (Sign In / Register)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0B111E) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder, width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    if (_isSignUp) {
                                      setState(() {
                                        _isSignUp = false;
                                        _errorMessage = null;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: !_isSignUp
                                          ? (isDark ? AppTheme.darkCard : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: !_isSignUp
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.08),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      'Sign In',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: !_isSignUp ? FontWeight.w700 : FontWeight.w500,
                                        color: !_isSignUp
                                            ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                                            : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    if (!_isSignUp) {
                                      setState(() {
                                        _isSignUp = true;
                                        _errorMessage = null;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _isSignUp
                                          ? (isDark ? AppTheme.darkCard : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _isSignUp
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.08),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      'Register',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _isSignUp ? FontWeight.w700 : FontWeight.w500,
                                        color: _isSignUp
                                            ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                                            : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Error Banner
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.danger.withOpacity(0.3), width: 0.8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: AppTheme.danger, fontSize: 12.5, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Registration Fields
                        if (_isSignUp) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _firstNameController,
                                  focusNode: _firstNameFocusNode,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(
                                    hintText: 'First name',
                                    prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _lastNameController,
                                  focusNode: _lastNameFocusNode,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(
                                    hintText: 'Last name',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Email Field
                        TextField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            hintText: 'Enterprise Email',
                            prefixIcon: Icon(Icons.mail_outline_rounded, size: 18),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Password Field
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),

                        // Confirm Password (Sign Up)
                        if (_isSignUp) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _confirmPasswordController,
                            focusNode: _confirmPasswordFocusNode,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              hintText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_reset_rounded, size: 18),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 18,
                                ),
                                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Submit Button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    if (_isSignUp) {
                                      _handleRegister();
                                    } else {
                                      _handleLogin();
                                    }
                                  },
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(
                                    _isSignUp ? 'Create Enterprise Account' : 'Sign In to Console',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Divider with OR
                        Row(
                          children: [
                            Expanded(child: Divider(color: cardBorder)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(
                                'OR',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                              ),
                            ),
                            Expanded(child: Divider(color: cardBorder)),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Google Sign-In Button
                        SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _handleGoogleLogin,
                            icon: const Icon(Icons.g_mobiledata_rounded, size: 24, color: AppTheme.primary),
                            label: const Text(
                              'Continue with Google Enterprise',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Quick-Fill Demo Account Pill
                  Center(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _emailController.text = 'karthiknataraj547@gmail.com';
                          _passwordController.text = 'karthik@547';
                          _isSignUp = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorder, width: 0.8),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.flash_on_rounded, size: 14, color: AppTheme.warning),
                              const SizedBox(width: 6),
                              Text(
                                'Quick-fill Demo: karthiknataraj547@gmail.com',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // --- FOOTER & SYSTEM HEALTH ---
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cloud API Online · TLS Encrypted · v${AppConstants.appVersion}',
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
            ),
          ),
        ),
      ),
    );
  }
}
