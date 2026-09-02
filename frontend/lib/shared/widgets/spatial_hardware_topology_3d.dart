import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SpatialHardwareTopology3D extends StatefulWidget {
  final bool isGatewayOnline;
  final bool isSubNodeOnline;
  final String gatewayMac;
  final String subNodeMac;
  final int rssiDbm;
  final int packetsReceived;

  const SpatialHardwareTopology3D({
    Key? key,
    required this.isGatewayOnline,
    required this.isSubNodeOnline,
    this.gatewayMac = 'AO:A3:B3:AA:69:E2',
    this.subNodeMac = '84:F3:EB:21:4D:10',
    this.rssiDbm = -54,
    this.packetsReceived = 142,
  }) : super(key: key);

  @override
  State<SpatialHardwareTopology3D> createState() => _SpatialHardwareTopology3DState();
}

class _SpatialHardwareTopology3DState extends State<SpatialHardwareTopology3D>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF090E1C).withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF00E5FF).withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.12),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Topology Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.hub_rounded, color: Color(0xFF00E5FF), size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'SPATIAL NODE TOPOLOGY',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.rssiDbm} dBm • EXCELLENT',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. 3D Spatial Radio Network Stage
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateX(-0.08),
            child: SizedBox(
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animated RF Radio Wavefront Canvas
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      return CustomPaint(
                        size: const Size(double.infinity, 140),
                        painter: _SpatialRadioWavePainter(
                          pulseProgress: _pulseController.value,
                          isLinkActive: widget.isSubNodeOnline && widget.isGatewayOnline,
                        ),
                      );
                    },
                  ),

                  // Node Cards (Left: Main Gateway, Right: Sub Sensor Node)
                  Row(
                    children: [
                      // Gateway Node (ESP32)
                      Expanded(
                        child: _buildNodeCard(
                          title: 'MAIN GATEWAY',
                          subtitle: 'ESP32 (MQTT HUB)',
                          mac: widget.gatewayMac,
                          isOnline: widget.isGatewayOnline,
                          icon: Icons.developer_board_rounded,
                          accentColor: const Color(0xFF00E5FF),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Sub-Node (ESP8266)
                      Expanded(
                        child: _buildNodeCard(
                          title: 'SUB SENSOR NODE',
                          subtitle: 'ESP8266 (ESP-NOW)',
                          mac: widget.subNodeMac,
                          isOnline: widget.isSubNodeOnline,
                          icon: Icons.sensors_rounded,
                          accentColor: const Color(0xFF00E676),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 3. Live Radio Metrics Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricChip(
                label: 'CHANNEL',
                value: 'CH 1..13 (AUTO)',
                color: Colors.white,
              ),
              _buildMetricChip(
                label: 'PACKETS SYNCED',
                value: '${widget.packetsReceived} PKTS',
                color: const Color(0xFF00E5FF),
              ),
              _buildMetricChip(
                label: 'PROTOCOL',
                value: 'ESP-NOW 2.4G',
                color: const Color(0xFF00E676),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard({
    required String title,
    required String subtitle,
    required String mac,
    required bool isOnline,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111A30).withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOnline ? accentColor.withOpacity(0.6) : Colors.red.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOnline ? accentColor : Colors.red).withOpacity(0.2),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: accentColor, size: 20),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? const Color(0xFF00E676) : Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: isOnline ? const Color(0xFF00E676) : Colors.red,
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mac,
            style: TextStyle(
              color: accentColor.withOpacity(0.9),
              fontSize: 8,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF131D33),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF24324F)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpatialRadioWavePainter extends CustomPainter {
  final double pulseProgress;
  final bool isLinkActive;

  _SpatialRadioWavePainter({
    required this.pulseProgress,
    required this.isLinkActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isLinkActive) return;

    final startX = 140.0;
    final endX = size.width - 140.0;
    final centerY = size.height / 2;

    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(startX, centerY), Offset(endX, centerY), linePaint);

    // Dynamic Pulsing Packets streaming across space
    for (int i = 0; i < 3; i++) {
      final progress = (pulseProgress + (i * 0.33)) % 1.0;
      final packetX = startX + ((endX - startX) * progress);
      final packetY = centerY + math.sin(progress * 2 * math.pi) * 8;

      final packetGlow = Paint()
        ..color = const Color(0xFF00E5FF).withOpacity((1.0 - progress) * 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(packetX, packetY), 5.0, packetGlow);

      final packetCore = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(packetX, packetY), 2.5, packetCore);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
