import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/presentation/controllers/settings_controller.dart'; // ตรวจสอบ path ให้ถูกต้อง
import 'package:trffic_ilght_app/presentation/widgets/bottom_navigation_bar.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent, // ให้สีกลืนไปกับพื้นหลัง
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
      bottomNavigationBar: const MyBottomNavigationBar(),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // 1. Notification (มีพื้นหลัง Highlight และ Switch)
          SettingMenuItem(
            icon: Icons.notifications_none_outlined,
            title: 'Notification',
            isHighlighted: true, // ทำให้มีกรอบสีพื้นหลังเหมือนในรูป
            trailing: Switch.adaptive(
              value: settings.isVoiceEnabled,
              activeThumbColor: Colors.blueGrey, // สีสวิตช์ตอนเปิด
              onChanged: (val) {
                context.read<SettingsProvider>().toggleVoice(val);
              },
            ),
          ),

          // 2. Dark Mode (มี Switch)
          SettingMenuItem(
            icon: Icons.light_mode_outlined,
            title: 'Dark Mode',
            trailing: Switch.adaptive(
              value: !settings.isLightMode,
              activeThumbColor: Colors.blueGrey,
              onChanged: (val) {
                context.read<SettingsProvider>().toggleTheme(!val);
              },
            ),
          ),

          const SizedBox(height: 8),

          // 3. IoU Threshold (มี Slider)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 22),
                        SizedBox(width: 16),
                        Text(
                          'IoU Threshold',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      settings.iouThreshold.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.blueGrey,
                    inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                    thumbColor: Colors.blueGrey,
                    overlayColor: Colors.blueGrey.withValues(alpha: 0.2),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: settings.iouThreshold,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    label: settings.iouThreshold.toStringAsFixed(2),
                    onChanged: (val) {
                      context.read<SettingsProvider>().setIouThreshold(val);
                    },
                  ),
                ),
              ],
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),

          color: isHighlighted
              ? (isDark ? const Color(0xFF2C2F42) : const Color(0xFFF0F2F5))
              : Colors.transparent,
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
