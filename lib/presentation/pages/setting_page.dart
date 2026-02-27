import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/widgets/bottom_navigation_bar.dart';
import 'package:trffic_ilght_app/presentation/widgets/setting_card.dart';
import 'package:trffic_ilght_app/presentation/widgets/switch_item.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingState();
}

class _SettingState extends State<SettingPage> {
  // ตัวแปรสำหรับเก็บค่าสถานะของ Switch
  bool _isLightMode = true;
  bool _isNotificationOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("SettingPage"),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: MyBottomNavigationBar(),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 20.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // --- หัวข้อหน้า (Header) ---
                const Text(
                  'ตั้งค่า',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ปรับแต่งการแจ้งเตือนและฟีเจอร์',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 30),

                // --- การ์ดที่ 1: ธีมสี (Theme Card) ---
                SettingCard(
                  title: 'ธีมสี',
                  subtitle: 'เปลี่ยนโหมดสว่าง/มืด',
                  headerIcon: Icons.wb_sunny_outlined,
                  headerIconColor: Colors.blue,
                  headerIconBg: Colors.blue.withOpacity(0.1),
                  child: SwitchItem(
                    icon: Icons.wb_sunny_outlined,
                    iconColor: Colors.blue,
                    iconBg: Colors.blue.withOpacity(0.1),
                    title: 'โหมดสว่าง',
                    subtitle: 'แสงสว่างปกติ',
                    value: _isLightMode,
                    onChanged: (val) {
                      setState(() {
                        _isLightMode = val;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // --- การ์ดที่ 2: การแจ้งเตือน (Notification Card) ---
                SettingCard(
                  title: 'การแจ้งเตือน',
                  subtitle: 'จัดการการแจ้งเตือนของคุณ',
                  headerIcon: Icons.notifications_none_outlined,
                  headerIconColor: Colors.blue,
                  headerIconBg: Colors.blue.withOpacity(0.1),
                  child: SwitchItem(
                    icon: Icons.error_outline,
                    iconColor: Colors.red, // ไอคอนสีแดงตามรูป
                    iconBg: Colors.red.withOpacity(0.1),
                    title: 'เตือนสัญญาณไฟ',
                    subtitle: 'แจ้งเตือนสัญญาณไฟจราจร',
                    value: _isNotificationOn,
                    onChanged: (val) {
                      setState(() {
                        _isNotificationOn = val;
                      });
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
