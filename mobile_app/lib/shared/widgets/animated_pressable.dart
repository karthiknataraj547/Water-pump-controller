import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable micro-animation wrapper that gives tactile, spring-physics scale
/// and elevation feedback when pressed.
class AnimatedPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;
  final bool enableHaptic;
  final BorderRadius? borderRadius;

  const AnimatedPressable({
    Key? key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.94,
    this.duration = const Duration(milliseconds: 120),
    this.enableHaptic = true,
    this.borderRadius,
  }) : super(key: key);

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = true);
    _controller.forward();
    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
