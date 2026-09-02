import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({Key? key, required this.status}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String label;

    switch (status.toUpperCase()) {
      case 'ONLINE':
      case 'NORMAL':
        badgeColor = const Color(0xFF10B981);
        label = 'ONLINE';
        break;
      case 'WARNING':
        badgeColor = const Color(0xFFF59E0B);
        label = 'WARNING';
        break;
      case 'CRITICAL':
      case 'EMERGENCY':
      case 'EMERGENCY_STOP':
        badgeColor = const Color(0xFFEF4444);
        label = 'CRITICAL';
        break;
      case 'OFFLINE':
      default:
        badgeColor = const Color(0xFF6B7280);
        label = 'OFFLINE';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withOpacity(0.8),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
