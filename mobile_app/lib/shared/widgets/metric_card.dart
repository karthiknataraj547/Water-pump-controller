import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color accentColor;
  final String? subtitle;

  const MetricCard({
    Key? key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    this.accentColor = AppTheme.primary,
    this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Subtle icon with soft background
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(isDark ? 0.1 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: accentColor.withOpacity(0.85),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
