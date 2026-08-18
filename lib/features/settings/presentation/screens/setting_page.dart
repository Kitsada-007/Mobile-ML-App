import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/features/settings/presentation/controllers/settings_controller.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          _buildSectionHeader(context, 'General Settings'),
          const SizedBox(height: 8),
          _buildCardContainer(
            context,
            children: [
              SettingMenuItem(
                icon: Icons.notifications_none_outlined,
                title: 'Notification Voice Alerts',
                trailing: Switch.adaptive(
                  value: settings.isVoiceEnabled,
                  onChanged: (val) {
                    context.read<SettingsProvider>().toggleVoice(val);
                  },
                ),
              ),
              if (settings.isVoiceEnabled) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(height: 1),
                ),
                const SizedBox(height: 8),
                _buildSliderRow(
                  context,
                  icon: Icons.volume_up_outlined,
                  title: 'Voice Volume',
                  value: settings.ttsVolume,
                  valueDisplay: '${(settings.ttsVolume * 100).toInt()}%',
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  onChanged: (val) =>
                      context.read<SettingsProvider>().setTtsVolume(val),
                ),
                _buildSliderRow(
                  context,
                  icon: Icons.speed_outlined,
                  title: 'Voice Speed',
                  value: settings.ttsSpeed,
                  valueDisplay: '${settings.ttsSpeed.toStringAsFixed(1)}x',
                  min: 0.4,
                  max: 1.0,
                  divisions: 6,
                  onChanged: (val) =>
                      context.read<SettingsProvider>().setTtsSpeed(val),
                ),
                _buildSliderRow(
                  context,
                  icon: Icons.hearing_outlined,
                  title: 'Voice Pitch',
                  value: settings.ttsPitch,
                  valueDisplay: settings.ttsPitch.toStringAsFixed(1),
                  min: 0.5,
                  max: 1.5,
                  divisions: 10,
                  onChanged: (val) =>
                      context.read<SettingsProvider>().setTtsPitch(val),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    bottom: 12.0,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        side: BorderSide(
                          color: colorScheme.primary,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.volume_up_rounded, size: 20),
                      label: const Text(
                        'ทดลองฟังเสียงพูดแจ้งเตือน',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () async {
                        final voiceService = TrafficVoiceService();
                        await voiceService.speak(
                          "ทดสอบการแจ้งเตือนสัญญาณไฟจราจร",
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Divider(height: 1),
              ),
              SettingMenuItem(
                icon: Icons.light_mode_outlined,
                title: 'Dark Mode',
                trailing: Switch.adaptive(
                  value: !settings.isLightMode,
                  onChanged: (val) {
                    context.read<SettingsProvider>().toggleTheme(!val);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _buildSectionHeader(context, 'Advanced Options'),
          const SizedBox(height: 8),
          Container(
            decoration: _cardBoxDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Theme(
                data: theme.copyWith(
                  dividerColor: Colors.transparent,
                  expansionTileTheme: ExpansionTileThemeData(
                    iconColor: colorScheme.primary,
                    collapsedIconColor: colorScheme.onSurfaceVariant,
                  ),
                ),
                child: ExpansionTile(
                  leading: Icon(Icons.tune_rounded, color: colorScheme.primary),
                  title: const Text(
                    'Model Threshold Settings',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Divider(height: 1),
                    ),
                    const SizedBox(height: 8),
                    _buildSliderRow(
                      context,
                      icon: Icons.adjust_rounded,
                      title: 'IoU Threshold',
                      value: settings.iouThreshold,
                      valueDisplay: settings.iouThreshold.toStringAsFixed(2),
                      min: 0.1,
                      max: 0.9,
                      divisions: 80,
                      onChanged: (val) =>
                          context.read<SettingsProvider>().setIouThreshold(val),
                    ),
                    _buildSliderRow(
                      context,
                      icon: Icons.filter_center_focus_rounded,
                      title: 'Confidence Threshold',
                      value: settings.confidenceThreshold,
                      valueDisplay: settings.confidenceThreshold
                          .toStringAsFixed(2),
                      min: 0.1,
                      max: 0.9,
                      divisions: 80,
                      onChanged: (val) => context
                          .read<SettingsProvider>()
                          .setConfidenceThreshold(val),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.restore_rounded, size: 20),
              label: const Text(
                'Reset Settings to Default',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Reset Thresholds'),
                    content: const Text(
                      'Are you sure you want to reset all model thresholds to their default values?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          context.read<SettingsProvider>().resetThresholds();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Thresholds reset to defaults'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, top: 4.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  BoxDecoration _cardBoxDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color cardColor;
    Color cardBorderColor;
    if (isDark) {
      cardColor = const Color(0xFF1E202C);
      cardBorderColor = Colors.white10;
    } else {
      cardColor = const Color(0xFFF7F8FA);
      cardBorderColor = Colors.black.withValues(alpha: 0.05);
    }

    return BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cardBorderColor, width: 1),
    );
  }

  Widget _buildCardContainer(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return Container(
      decoration: _cardBoxDecoration(context),
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required double value,
    required String valueDisplay,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueDisplay,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const SettingMenuItem({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // แถวที่ถูกไฮไลต์ใช้พื้นหลังอ่อน ๆ ตามธีม ส่วนแถวปกติโปร่งใส
    Color rowColor;
    if (isHighlighted) {
      if (isDark) {
        rowColor = const Color(0xFF2C2F42);
      } else {
        rowColor = const Color(0xFFF0F2F5);
      }
    } else {
      rowColor = Colors.transparent;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: rowColor,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
