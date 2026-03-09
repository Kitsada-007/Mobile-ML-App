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
              activeColor: Colors.blueGrey, // สีสวิตช์ตอนเปิด
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
              activeColor: Colors.blueGrey,
              onChanged: (val) {
                context.read<SettingsProvider>().toggleTheme(!val);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 🟢 วิดเจ็ตสำหรับสร้างแต่ละแถวให้เหมือนในรูป
// ==========================================
class SettingMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing; // สำหรับใส่ Switch หรืออื่นๆ ด้านขวาสุด
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
    // เช็คว่าปัจจุบันเป็นโหมดมืดหรือสว่าง เพื่อเลือกสีพื้นหลัง Highlight ได้ถูกต้อง
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(
          bottom: 4.0,
        ), // เว้นระยะห่างระหว่างแต่ละแถวเล็กน้อย
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // ถ้า isHighlighted เป็น true จะใส่สีพื้นหลังตามโหมด (แบบแถบ Notification)
          color: isHighlighted
              ? (isDark ? const Color(0xFF2C2F42) : const Color(0xFFF0F2F5))
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              // ไม่บังคับสี ปล่อยให้เปลี่ยนตาม Theme ของแอป
            ),
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
