import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/app/routes.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/screens/camera_inference_page.dart';

/// หน้าจอหลักของแอป (Main Screen)
/// - ใช้ Scaffold พร้อม Drawer (เมนูข้าง) สำหรับนำทาง
/// - Body หลักคือ CameraInferencePage (หน้าตรวจจับเรียลไทม์)
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.initializeCamera = true});

  /// ตั้งเป็น false ในเทสต์เพื่อไม่ให้แอปขอสิทธิ์กล้อง
  final bool initializeCamera;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const _AppDrawer(),
      body: CameraInferencePage(
        initializeOnStart: widget.initializeCamera,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}

/// Drawer เมนูนำทางด้านข้าง (Side Navigation)
/// เมนูหลัก:
/// - Realtime Detection: หน้าตรวจจับกล้องเรียลไทม์ (หน้าหลัก)
/// - Video Detection: ทดสอบตรวจจับวิดีโอ (Developer tool)
/// - Settings: หน้าตั้งค่า
class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final colorScheme = theme;

    return Drawer(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const _DrawerLogo(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Berng Fai',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Realtime traffic assistant',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.center_focus_strong_rounded),
              title: const Text('Realtime Detection'),
              selected: true,
              selectedColor: colorScheme.primary,
              iconColor: colorScheme.onSurfaceVariant,
              textColor: colorScheme.onSurface,
              selectedTileColor: colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              // เป็นหน้าหลักอยู่แล้ว จึงแค่ปิด Drawer ไม่ต้อง push หน้าใหม่
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.video_file_rounded),
              title: const Text('Video Detection'),
              iconColor: colorScheme.onSurfaceVariant,
              textColor: colorScheme.onSurface,
              subtitleTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(AppRoutes.videoDetection());
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('Settings'),
              iconColor: colorScheme.onSurfaceVariant,
              textColor: colorScheme.onSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(AppRoutes.settings());
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: Color(0xFF63E681), size: 8),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detection system',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo ใน Drawer Header
/// - แสดงรูปภาพจาก assets/images/app.png
/// - fallback เป็นไอคอน traffic หากโหลดรูปไม่ได้
class _DrawerLogo extends StatelessWidget {
  const _DrawerLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Image.asset(
        'assets/images/app.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.traffic_rounded, color: Colors.black),
      ),
    );
  }
}
