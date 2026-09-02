import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/hardware/hardware_state_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  String _selectedRange = 'today';
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    hardwareStateService.addListener(_onHardwareStateChanged);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    hardwareStateService.removeListener(_onHardwareStateChanged);
    super.dispose();
  }

  void _onHardwareStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = hardwareStateService.isHardwareOnline;
    final sensorData = hardwareStateService.sensorData;
    final pumpStatus = hardwareStateService.pumpStatus;
    final device = hardwareStateService.activeDevice;
    final waterLevel = sensorData?.waterLevelPct ?? 0.0;
    final flowRate = sensorData?.flowRateLpm ?? 0.0;
    final isPumpOn = pumpStatus?.isRunning ?? false;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Telemetry & Analytics',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              isOnline ? 'LIVE' : 'OFFLINE',
              style: TextStyle(
                color: isOnline ? AppTheme.accent : AppTheme.danger,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeController,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Timeframe Selector
              _buildTimeframeSelector(),
              const SizedBox(height: 18),

              // 2. Water Level Gauge Card
              _buildWaterLevelGaugeCard(waterLevel, sensorData != null),
              const SizedBox(height: 14),

              // 3. Real-time Metrics Grid
              _buildRealTimeMetricsGrid(
                waterLevel: waterLevel,
                flowRate: flowRate,
                isPumpOn: isPumpOn,
                isOnline: isOnline,
                sensorData: sensorData,
                device: device,
              ),
              const SizedBox(height: 16),

              // 4. Water Level Trend Chart (Historical & Live)
              _buildTrendChart(),
              const SizedBox(height: 14),

              // 5. Water Quality Insights
              _buildWaterQualityCard(sensorData),
              const SizedBox(height: 14),

              // 6. System Health Overview
              _buildSystemHealthCard(isOnline, device, sensorData),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _buildRangeChip('today', 'Today', Icons.today_rounded),
          _buildRangeChip('week', 'Week', Icons.date_range_rounded),
          _buildRangeChip('month', 'Month', Icons.calendar_month_rounded),
        ],
      ),
    );
  }

  Widget _buildRangeChip(String key, String label, IconData icon) {
    final isSelected = _selectedRange == key;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRange = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: isSelected ? Colors.white : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaterLevelGaugeCard(double level, bool hasData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Water Tank Level',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Real-time ultrasonic reading',
                      style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (hasData ? AppTheme.accent : AppTheme.warning).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (hasData ? AppTheme.accent : AppTheme.warning).withOpacity(0.3),
                      width: 0.5),
                ),
                child: Text(
                  hasData ? 'LIVE DATA' : 'NO SENSOR',
                  style: TextStyle(
                    color: hasData ? AppTheme.accent : AppTheme.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            width: 140,
            child: CustomPaint(
              painter: _WaterGaugePainter(
                level: hasData ? level : 0,
                hasData: hasData,
                isDark: isDark,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasData ? '${level.toStringAsFixed(0)}%' : '—',
                      style: textTheme.headlineLarge?.copyWith(
                        fontSize: hasData ? 32 : 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hasData
                          ? '${(level / 100 * 5000).toStringAsFixed(0)} L'
                          : 'No Data',
                      style: textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealTimeMetricsGrid({
    required double waterLevel,
    required double flowRate,
    required bool isPumpOn,
    required bool isOnline,
    required dynamic sensorData,
    required dynamic device,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _buildMetricItem(
            icon: Icons.water_drop_rounded,
            label: 'Flow Rate',
            value: sensorData != null ? flowRate.toStringAsFixed(1) : '—',
            unit: 'L/min',
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricItem(
            icon: Icons.science_rounded,
            label: 'TDS Purity',
            value: sensorData != null ? '${sensorData.tdsPpm}' : '—',
            unit: 'PPM',
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: textTheme.bodySmall?.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    final points = hardwareStateService.getHistoricalTelemetry(_selectedRange);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final spots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].waterLevelPct));
    }

    final double maxX = spots.isNotEmpty ? (spots.length - 1).toDouble() : 5.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Water Level Trend',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    _selectedRange == 'today'
                        ? 'Continuous readings since hardware paired'
                        : (_selectedRange == 'week' ? 'Past 7 Days Level History' : '30-Day Historical Curve'),
                    style: textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('Level %',
                        style: TextStyle(color: colorScheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 25,
                      getTitlesWidget: (val, _) => Text(
                        '${val.toInt()}',
                        style: textTheme.bodySmall?.copyWith(fontSize: 9),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: math.max(1, (spots.length / 5).floorToDouble()),
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                        final t = points[idx].timestamp;
                        final label = _selectedRange == 'today'
                            ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
                            : '${t.day}/${t.month}';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            style: textTheme.bodySmall?.copyWith(fontSize: 9),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: maxX > 0 ? maxX : 1,
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots.isNotEmpty ? spots : [const FlSpot(0, 50), const FlSpot(1, 50)],
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: colorScheme.primary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colorScheme.primary.withOpacity(0.2),
                          colorScheme.primary.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaterQualityCard(dynamic sensorData) {
    final tds = sensorData?.tdsPpm ?? 0;
    final temp = sensorData?.temperatureC ?? 0.0;
    final hasData = sensorData != null;
    final qualityLabel = hasData ? sensorData.waterQualityString : 'N/A';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    Color qualityColor;
    if (!hasData) {
      qualityColor = isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary;
    } else if (tds < 150) {
      qualityColor = AppTheme.accent;
    } else if (tds < 300) {
      qualityColor = AppTheme.warning;
    } else {
      qualityColor = AppTheme.danger;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: qualityColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.eco_rounded, color: qualityColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Water Quality Index', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text('TDS & Temperature analysis', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: qualityColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  qualityLabel,
                  style: TextStyle(color: qualityColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildQualityBar('TDS Level', hasData ? '$tds PPM' : '—',
              hasData ? (tds / 500).clamp(0.0, 1.0) : 0.0, qualityColor),
          const SizedBox(height: 10),
          _buildQualityBar(
              'Temperature',
              hasData ? '${temp.toStringAsFixed(1)}°C' : '—',
              hasData ? (temp / 50).clamp(0.0, 1.0) : 0.0,
              AppTheme.warning),
        ],
      ),
    );
  }

  Widget _buildQualityBar(String label, String value, double progress, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 11)),
            Text(value, style: textTheme.bodyMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemHealthCard(bool isOnline, dynamic device, dynamic sensorData) {
    final battV = sensorData?.batteryVoltage ?? 0.0;
    final battPct = sensorData?.batteryPct ?? 0;
    final hasBatt = sensorData != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_rounded, color: colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text('System Health', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          _buildHealthRow(
              'Gateway Node',
              isOnline ? 'Connected' : 'Offline',
              isOnline ? AppTheme.accent : AppTheme.danger),
          _buildHealthRow(
              'Sensor Node',
              sensorData != null ? 'ESP-NOW Active' : 'No Link',
              sensorData != null ? AppTheme.accent : AppTheme.warning),
          _buildHealthRow(
              'MQTT Broker',
              hardwareStateService.isMqttConnected ? 'Connected' : 'Disconnected',
              hardwareStateService.isMqttConnected ? AppTheme.accent : AppTheme.danger),
          _buildHealthRow(
              'Sensor Battery',
              hasBatt ? '${battV.toStringAsFixed(2)}V ($battPct%)' : 'N/A',
              hasBatt ? (battPct > 20 ? AppTheme.accent : AppTheme.danger) : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary)),
          _buildHealthRow(
              'Firmware',
              device?.firmwareVersion ?? '—',
              isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
        ],
      ),
    );
  }

  Widget _buildHealthRow(String label, String value, Color valueColor) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 12)),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: valueColor),
              ),
              const SizedBox(width: 6),
              Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// Custom painter for the water gauge arc
class _WaterGaugePainter extends CustomPainter {
  final double level;
  final bool hasData;
  final bool isDark;

  _WaterGaugePainter({required this.level, required this.hasData, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final sweepAngle = math.pi * 1.5;
    final startAngle = math.pi * 0.75;

    // Background arc
    final bgPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    if (!hasData) return;

    final valueAngle = sweepAngle * (level / 100.0).clamp(0.0, 1.0);

    Color arcColor;
    if (level > 80) {
      arcColor = AppTheme.accent;
    } else if (level > 40) {
      arcColor = AppTheme.primary;
    } else if (level > 20) {
      arcColor = AppTheme.warning;
    } else {
      arcColor = AppTheme.danger;
    }

    final valuePaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueAngle,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaterGaugePainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.hasData != hasData || oldDelegate.isDark != isDark;
  }
}
