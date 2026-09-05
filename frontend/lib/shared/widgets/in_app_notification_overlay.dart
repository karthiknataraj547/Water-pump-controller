import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/hardware/hardware_state_service.dart';

class InAppNotificationOverlay extends StatefulWidget {
  final Widget child;

  const InAppNotificationOverlay({Key? key, required this.child}) : super(key: key);

  @override
  State<InAppNotificationOverlay> createState() => _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<InAppNotificationData>? _subscription;
  InAppNotificationData? _currentNotification;
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    _subscription = pushNotificationService.inAppNotificationStream.listen((data) {
      _showBanner(data);
    });
  }

  void _showBanner(InAppNotificationData data) {
    _dismissTimer?.cancel();
    setState(() {
      _currentNotification = data;
    });
    _animController.forward(from: 0.0);

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _animController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _currentNotification = null;
            });
          }
        });
      }
    });
  }

  void _dismissNow() {
    _dismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _currentNotification = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        widget.child,
        if (_currentNotification != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                final val = _slideAnimation.value;
                return Transform.translate(
                  offset: Offset(0, -50 * (1 - val)),
                  child: Opacity(
                    opacity: val.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Dismissible(
                key: ValueKey(_currentNotification!.id),
                direction: DismissDirection.up,
                onDismissed: (_) => _dismissNow(),
                child: _buildGlassBanner(context, _currentNotification!, isDark),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGlassBanner(
      BuildContext context, InAppNotificationData notif, bool isDark) {
    final isEmergency = notif.type == 'critical' ||
        notif.type == 'emergency' ||
        notif.level == AlertLevel.danger;
    final isMotor = notif.type.contains('motor');

    Color primaryAccent = AppTheme.accent;
    IconData icon = Icons.info_outline_rounded;

    if (isEmergency) {
      primaryAccent = AppTheme.danger;
      icon = Icons.warning_amber_rounded;
    } else if (isMotor) {
      primaryAccent = const Color(0xFF0284C7);
      icon = Icons.power_settings_new_rounded;
    } else if (notif.level == AlertLevel.warning) {
      primaryAccent = AppTheme.warning;
      icon = Icons.error_outline_rounded;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F172A).withOpacity(0.85)
                : Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isEmergency
                  ? AppTheme.danger.withOpacity(0.6)
                  : (isDark ? Colors.white24 : primaryAccent.withOpacity(0.3)),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryAccent.withOpacity(isDark ? 0.25 : 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryAccent.withOpacity(0.4)),
                ),
                child: Icon(icon, color: primaryAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          notif.title,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Now',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : const Color(0xFF64748B),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notif.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _dismissNow,
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
