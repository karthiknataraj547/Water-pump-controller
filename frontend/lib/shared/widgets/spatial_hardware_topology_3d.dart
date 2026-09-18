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
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final isOnline = widget.isGatewayOnline;
    final isSubOnline = widget.isSubNodeOnline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with System Architecture Title & Signal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_outlined, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'NETWORK SIGNAL TOPOLOGY',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isOnline ? AppTheme.accent : AppTheme.slate).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isOnline ? '${widget.rssiDbm} dBm · Wi-Fi' : 'NO LINK',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isOnline ? AppTheme.accent : AppTheme.slate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Topology Flow Schematic (Cloud -> Gateway -> Sub Node)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF090E17) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder, width: 0.8),
            ),
            child: Row(
              children: [
                // Node 1: Cloud MQTT Broker
                _buildTopologyNode(
                  'Cloud Broker',
                  'broker.hivemq.com',
                  Icons.cloud_outlined,
                  AppTheme.primary,
                  isDark,
                ),

                // Link 1
                Expanded(child: _buildTopologyLink(isOnline, isDark)),

                // Node 2: Main Gateway (ESP32)
                _buildTopologyNode(
                  'ESP32 Gateway',
                  widget.gatewayMac.length > 10 ? widget.gatewayMac.substring(0, 10) : widget.gatewayMac,
                  Icons.developer_board_rounded,
                  isOnline ? AppTheme.accent : AppTheme.slate,
                  isDark,
                ),

                // Link 2
                Expanded(child: _buildTopologyLink(isSubOnline, isDark)),

                // Node 3: Tank Sub-Node (ESP8266)
                _buildTopologyNode(
                  'Tank Sensor',
                  widget.subNodeMac.length > 10 ? widget.subNodeMac.substring(0, 10) : widget.subNodeMac,
                  Icons.sensors_rounded,
                  isSubOnline ? AppTheme.primaryLight : AppTheme.slate,
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Technical Link Readout Strip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMicroStat('LINK PROTOCOL', 'ESP-NOW & MQTT TLS', isDark),
              _buildMicroStat('PACKET SEQUENCE', '#${widget.packetsReceived}', isDark),
              _buildMicroStat('SIGNAL QUALITY', isOnline ? 'Optimal (-54 dBm)' : 'Offline', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopologyNode(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3), width: 1.0),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildTopologyLink(bool isActive, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: List.generate(5, (index) {
              return Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: isActive
                      ? (index % 2 == 0 ? AppTheme.accent : AppTheme.accent.withOpacity(0.3))
                      : (isDark ? Colors.white12 : Colors.black12),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 12,
            color: isActive ? AppTheme.accent : (isDark ? Colors.white24 : Colors.black26),
          ),
        ],
      ),
    );
  }

  Widget _buildMicroStat(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
      ],
    );
  }
}
