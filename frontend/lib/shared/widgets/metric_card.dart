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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: accentColor, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accentColor.withOpacity(0.9),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
