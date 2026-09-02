import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../shared/models/automation_rule_model.dart';
import '../../../shared/widgets/confirmation_dialog.dart';

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({Key? key}) : super(key: key);

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  List<AutomationRuleModel> _rules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRules();
  }

  Future<void> _fetchRules() async {
    setState(() => _isLoading = true);
    final devId = hardwareStateService.activeDevice?.id ?? 'esp32_pump_000000';

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('automation_rules_$devId');
      if (savedStr != null && savedStr.isNotEmpty) {
        final List list = jsonDecode(savedStr);
        _rules = list.map((e) => AutomationRuleModel.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading cached rules: $e');
    }

    if (_rules.isEmpty) {
      _rules = [
        AutomationRuleModel(
          id: 'rule_refill_default',
          deviceId: devId,
          name: 'Automatic Tank Refill',
          conditionType: 'WATER_LEVEL_BELOW',
          conditionValue: 25.0,
          actionType: 'START_PUMP',
          autoStopLevelPct: 95.0,
          maxRunMinutes: 30,
          isEnabled: true,
        ),
        AutomationRuleModel(
          id: 'rule_dry_run_guard',
          deviceId: devId,
          name: 'Dry Run Motor Protection',
          conditionType: 'WATER_LEVEL_BELOW',
          conditionValue: 5.0,
          actionType: 'STOP_PUMP',
          autoStopLevelPct: 100.0,
          maxRunMinutes: 1,
          isEnabled: true,
        ),
      ];
      _persistRulesLocally();
    }

    try {
      final res = await apiClient.get('/automation/$devId/rules');
      if (res.statusCode == 200) {
        final List list = res.data['data'] ?? [];
        if (list.isNotEmpty) {
          _rules = list.map((e) => AutomationRuleModel.fromJson(e)).toList();
          _persistRulesLocally();
        }
      }
    } catch (e) {
      debugPrint('Backend offline or unreachable, using local rules: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _persistRulesLocally() async {
    final devId = hardwareStateService.activeDevice?.id ?? 'esp32_pump_000000';
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _rules.map((r) => r.toJson()).toList();
    await prefs.setString('automation_rules_$devId', jsonEncode(jsonList));

    final activeRefill = _rules.firstWhere(
      (r) => r.isEnabled && r.actionType == 'START_PUMP',
      orElse: () => _rules.first,
    );

    hardwareStateService.saveAutomationRules(
      autoStartLevel: activeRefill.conditionValue,
      autoStopLevel: activeRefill.autoStopLevelPct,
      dryRunProtection: true,
      maxRuntimeMins: activeRefill.maxRunMinutes,
    );
  }

  Future<void> _toggleRule(AutomationRuleModel rule, bool value) async {
    setState(() {
      final idx = _rules.indexWhere((r) => r.id == rule.id);
      if (idx >= 0) {
        _rules[idx] = AutomationRuleModel(
          id: rule.id,
          deviceId: rule.deviceId,
          name: rule.name,
          conditionType: rule.conditionType,
          conditionValue: rule.conditionValue,
          actionType: rule.actionType,
          autoStopLevelPct: rule.autoStopLevelPct,
          maxRunMinutes: rule.maxRunMinutes,
          isEnabled: value,
        );
      }
    });

    await _persistRulesLocally();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${rule.name} ${value ? "Enabled" : "Disabled"}.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final devId = hardwareStateService.activeDevice?.id;
    if (devId != null) {
      try {
        await apiClient.put('/automation/$devId/rules/${rule.id}', data: {'isEnabled': value});
      } catch (_) {}
    }
  }

  Future<void> _confirmDeleteRule(AutomationRuleModel rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Rule?',
        content: 'Are you sure you want to delete "${rule.name}"? This will remove the rule from storage and update your hardware.',
        confirmText: 'Delete',
        confirmColor: AppTheme.danger,
        onConfirm: () {},
      ),
    );

    if (confirmed == true) {
      await _deleteRule(rule);
    }
  }

  Future<void> _deleteRule(AutomationRuleModel rule) async {
    setState(() {
      _rules.removeWhere((r) => r.id == rule.id);
    });

    await _persistRulesLocally();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rule "${rule.name}" deleted.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final devId = hardwareStateService.activeDevice?.id;
    if (devId != null) {
      try {
        await apiClient.delete('/automation/$devId/rules/${rule.id}');
      } catch (_) {}
    }
  }

  void _showAddRuleSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final nameCtrl = TextEditingController(text: 'Auto Refill Rule');
    double startLevel = 25.0;
    double stopLevel = 95.0;
    int maxMinutes = 30;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create Automation Rule',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Rule Name',
                  filled: true,
                  fillColor: isDark ? AppTheme.darkCard : AppTheme.lightBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Trigger: Auto-Start Below', style: textTheme.bodySmall),
                  Text('${startLevel.toInt()}%', style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary)),
                ],
              ),
              Slider(
                value: startLevel,
                min: 10,
                max: 50,
                divisions: 8,
                activeColor: colorScheme.primary,
                onChanged: (v) => setSheetState(() => startLevel = v),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Action: Auto-Stop Level', style: textTheme.bodySmall),
                  Text('${stopLevel.toInt()}%', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.accent)),
                ],
              ),
              Slider(
                value: stopLevel,
                min: 60,
                max: 100,
                divisions: 8,
                activeColor: AppTheme.accent,
                onChanged: (v) => setSheetState(() => stopLevel = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    final devId = hardwareStateService.activeDevice?.id ?? 'esp32_pump_000000';
                    final newRule = AutomationRuleModel(
                      id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
                      deviceId: devId,
                      name: nameCtrl.text.trim().isEmpty ? 'Auto Refill Rule' : nameCtrl.text.trim(),
                      conditionType: 'WATER_LEVEL_BELOW',
                      conditionValue: startLevel,
                      actionType: 'START_PUMP',
                      autoStopLevelPct: stopLevel,
                      maxRunMinutes: maxMinutes,
                      isEnabled: true,
                    );

                    setState(() {
                      _rules.add(newRule);
                    });

                    await _persistRulesLocally();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Rule saved and transmitted to hardware.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: const Text('Save & Sync to Hardware', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Autonomous Rules', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: colorScheme.primary),
            onPressed: _showAddRuleSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sync status badge
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(isDark ? 0.1 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.25), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All automation rules are saved locally and synced to ESP32 flash memory for offline autonomous operation.',
                      style: textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ACTIVE RULES (${_rules.length})',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: colorScheme.primary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showAddRuleSheet,
                  icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
                  label: Text('Add Rule', style: TextStyle(color: colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (_rules.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
                ),
                child: Center(
                  child: Text('No active automation rules. Tap + to add one.', style: textTheme.bodySmall),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rules.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final rule = _rules[index];
                  return Dismissible(
                    key: ValueKey(rule.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => ConfirmationDialog(
                          title: 'Delete Rule?',
                          content: 'Are you sure you want to delete "${rule.name}"?',
                          confirmText: 'Delete',
                          confirmColor: AppTheme.danger,
                          onConfirm: () {},
                        ),
                      );
                    },
                    onDismissed: (_) => _deleteRule(rule),
                    background: Container(
                      padding: const EdgeInsets.only(right: 20),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 24),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: rule.isEnabled
                                  ? AppTheme.accent.withOpacity(0.12)
                                  : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.auto_mode_rounded,
                              size: 18,
                              color: rule.isEnabled
                                  ? AppTheme.accent
                                  : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rule.name,
                                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Auto-Start below ${rule.conditionValue.toInt()}% · Cutoff at ${rule.autoStopLevelPct.toInt()}%',
                                  style: textTheme.bodySmall?.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: rule.isEnabled,
                            activeColor: AppTheme.accent,
                            onChanged: (val) => _toggleRule(rule, val),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                            tooltip: 'Delete Rule',
                            onPressed: () => _confirmDeleteRule(rule),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
