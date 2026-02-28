import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/presentation/pages/camera_inference_screen.dart';
import 'package:trffic_ilght_app/presentation/pages/single_image_screen.dart';
import 'package:trffic_ilght_app/presentation/pages/video_inference_screen.dart';

import 'package:trffic_ilght_app/presentation/widgets/bottom_navigation_bar.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Detection',
          style: TextStyle(
            color: Color(0xFF1A1D2E),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFEEEFF3)),
        ),
      ),
      bottomNavigationBar: const MyBottomNavigationBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero banner ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3D5AFE), Color(0xFF536DFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3D5AFE).withOpacity(0.25),
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
                          const Text(
                            'Traffic Light AI',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'ระบบตรวจจับ\nสัญญาณไฟจราจร',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
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

              const Text(
                'เลือกโหมดการตรวจจับ',
                style: TextStyle(
                  color: Color(0xFF1A1D2E),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),

              // ── Card: เปิดกล้อง ───────────────────────────────────
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
                    builder: (_) => const CameraInferenceScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Card: Single image ────────────────────────────────
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

              // ── Card: วิดีโอ ──────────────────────────────────────
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

  // ── Helper: สร้าง Action Card ─────────────────────────────────────────────
  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Color iconBg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEEFF3)),
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
                      style: const TextStyle(
                        color: Color(0xFF1A1D2E),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
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
