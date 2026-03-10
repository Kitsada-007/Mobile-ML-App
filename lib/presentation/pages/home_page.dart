import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/presentation/pages/camera_inference_page.dart';
import 'package:trffic_ilght_app/presentation/pages/single_image_screen.dart';
import 'package:trffic_ilght_app/presentation/pages/video_inference_screen.dart';

import 'package:trffic_ilght_app/presentation/widgets/bottom_navigation_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker picker = ImagePicker();

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Detection',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: theme.dividerColor),
        ),
      ),
      bottomNavigationBar: const MyBottomNavigationBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      isDark
                          ? colorScheme.primaryContainer
                          : colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Traffic Light AI',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimary.withOpacity(0.85),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ระบบตรวจจับ\nสัญญาณไฟจราจร',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'เลือกโหมดการตรวจจับ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _buildActionCard(
                context,
                icon: Icons.camera_alt_rounded,
                title: 'เปิดกล้องตรวจจับ',
                subtitle: 'ตรวจจับแบบ Real-time ผ่านกล้อง',
                iconColor: const Color(0xFF3D5AFE),
                iconBg: const Color(0xFFEEF1FF),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CameraInferencePage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _buildActionCard(
                context,
                icon: Icons.image_search_rounded,
                title: 'ทดสอบรูปภาพเดี่ยว',
                subtitle: 'อัปโหลดและวิเคราะห์ภาพจากคลัง',
                iconColor: const Color(0xFF00C853),
                iconBg: const Color(0xFFE8FFF0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SingleImageScreen()),
                ),
              ),
              const SizedBox(height: 12),

              _buildActionCard(
                context,
                icon: Icons.play_circle_rounded,
                title: 'ทดสอบวิดีโอ',
                subtitle: 'วิเคราะห์ไฟล์วิดีโอ .mp4',
                iconColor: const Color(0xFFFF6D00),
                iconBg: const Color(0xFFFFF3E8),
                onTap: () => Get.to(() => VideoInferenceScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Color iconBg,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              // Arrow
              Icon(Icons.arrow_forward_ios_rounded, color: iconColor, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}
