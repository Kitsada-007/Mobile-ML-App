import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // 👈 อย่าลืม import provider
import 'package:trffic_ilght_app/presentation/controllers/settings_controller.dart';
import 'package:trffic_ilght_app/presentation/widgets/bottom_navigation_bar.dart';
import 'package:trffic_ilght_app/presentation/widgets/setting_card.dart';
import 'package:trffic_ilght_app/presentation/widgets/switch_item.dart';
// import SettingsProvider ของคุณ

class SettingPage extends StatelessWidget {
  // เปลี่ยนเป็น StatelessWidget ได้เลย
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 🟢 ดึงข้อมูลจาก Provider
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: const MyBottomNavigationBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ปรับแต่งการแจ้งเตือนและฟีเจอร์',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 30),

                // --- ธีมสี ---
                // SettingCard(
                //   title: 'ธีมสี',
                //   subtitle: 'เปลี่ยนโหมดสว่าง/มืด',
                //   headerIcon: Icons.wb_sunny_outlined,
                //   headerIconColor: Colors.blue,
                //   headerIconBg: Colors.blue.withOpacity(0.1),
                //   child: SwitchItem(
                //     icon: Icons.wb_sunny_outlined,
                //     iconColor: Colors.blue,
                //     iconBg: Colors.blue.withOpacity(0.1),
                //     title: 'โหมดสว่าง',
                //     subtitle: 'แสงสว่างปกติ',
                //     // 🟢 ผูกค่า Value กับ Provider
                //     value: settings.isLightMode,
                //     onChanged: (val) {
                //       // 🟢 สั่งเปลี่ยนธีม
                //       context.read<SettingsProvider>().toggleTheme(val);
                //     },
                //   ),
                // ),
                // const SizedBox(height: 20),

                // --- การแจ้งเตือน ---
                SettingCard(
                  title: 'การแจ้งเตือน',
                  subtitle: 'จัดการการแจ้งเตือนของคุณ',
                  headerIcon: Icons.notifications_none_outlined,
                  headerIconColor: Colors.blue,
                  headerIconBg: Colors.blue.withOpacity(0.1),
                  child: SwitchItem(
                    icon: Icons
                        .volume_up_outlined, // แนะนำเปลี่ยนไอคอนเป็นรูปลำโพง
                    iconColor: Colors.red,
                    iconBg: Colors.red.withOpacity(0.1),
                    title: 'เตือนสัญญาณไฟ',
                    subtitle: 'แจ้งเตือนด้วยเสียง',
                    // 🟢 ผูกค่า Value กับ Provider
                    value: settings.isVoiceEnabled,
                    onChanged: (val) {
                      // 🟢 สั่งเปิด/ปิดเสียง
                      context.read<SettingsProvider>().toggleVoice(val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
