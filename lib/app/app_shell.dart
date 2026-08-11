import 'package:flutter/material.dart'; // ไลบรารี UI หลักของ Flutter (Widget ต่าง ๆ)
import 'package:trffic_ilght_app/app/routes.dart'; // ตัวจัดการ Route/หน้าเพจทั้งหมดของแอป
import 'package:trffic_ilght_app/features/camera_detection/presentation/screens/camera_inference_page.dart'; // หน้าเซนต์หลัง (BLoC) ที่ใช้เป็นตัว main หน้า บอดี้ของแอปหลัก

/// หน้าจอหลักของแอป (Main Screen)
/// - ใช้ Scaffold พร้อม Drawer (เมนูข้าง) สำหรับนำทาง
/// - Body หลักคือ CameraInferencePage (หน้าตรวจจับเรียลไทม์)
/// - initializeCamera: ควบคุมการเริ่มต้นกล้อง (ปิดได้สำหรับ testing)
class MainScreen extends StatefulWidget {
  // StatefulWidget เพราะต้องการ State ที่สามารถเข้าถึง Scaffold ผ่าน GlobalKey ได้
  const MainScreen({super.key, this.initializeCamera = true});

  // กำหนดว่าควรเปิดกล้องเมื่อเข้าเว็บหรือไม่ (default = true; ตั้งเป็น false ในตอนทดสอบเพื่อไม่ให้ขอสิทธิ์กล้อง)
  final bool initializeCamera;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // GlobalKey ไว้เก็บ reference ของ Scaffold เพื่อให้เปิด/ปิด Drawer ได้จากที่อื่น
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    // Scaffold คือโครงร่างหลักของหน้าจอ (AppBar / Drawer / Body)
    return Scaffold(
      key: _scaffoldKey, // ผูก GlobalKey เพื่อใช้ควบคุม Drawer ภายหลัง
      backgroundColor: Colors.black, // พื้นหลังสีดำ (ธีมมืด)
      drawer: const _AppDrawer(), // Drawer (เมนูนำทางด้านข้าง) ที่สร้างเอง
      drawerScrimColor: Colors.black.withValues(
        alpha: 0.72,
      ), // สีฉากหลังเมื่อ Drawer เปิด (โปร่งแสง 72%)
      body: CameraInferencePage(
        initializeOnStart:
            widget.initializeCamera, // ส่งค่าควบคุมการตั้งค่ากล้องลงไป
        onMenuPressed: () => _scaffoldKey.currentState
            ?.openDrawer(), // เมื่อกดปุ่มเมนูให้เปิด Drawer
      ),
    );
  }
}

/// Drawer เมนูนำทางด้านข้าง (Side Navigation)
/// เมนูหลัก:
/// - Realtime Detection: หน้าตรวจจับกล้องเรียลไทม์ (หน้าหลัก)
/// - Single Image Test: ทดสอบตรวจจับภาพเดียว (Developer tool)
/// - Video Test: ทดสอบตรวจจับวิดีโอ (Developer tool)
/// - Settings: หน้าตั้งค่า
class _AppDrawer extends StatelessWidget {
  // StatelessWidget เพราะ Drawer ไม่มีการเปลี่ยนแปลงสถานะภายใน
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    // Drawer: แผงเมนูที่เลื่อนออกมาจากขอบซ้ายของหน้าจอ
    return Drawer(
      backgroundColor: const Color(
        0xFF111111,
      ), // พื้นหลังสีดำเข้ม (เข้ากับธีมมืด)
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ), // ทำมุมโค้งเฉพาะด้านขวา (ด้านที่ติดกับเนื้อหา)
      child: SafeArea(
        // SafeArea: กันเนื้อหาไม่ให้ชนกับพื้นที่สถานะ / แถบนำทางของระบบ
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // ให้ลูกทุกตัวกว้างเต็ม Drawer
          children: [
            // ---------- ส่วนหัวของ Drawer (Header) ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const _DrawerLogo(), // โลโก้แอป
                  const SizedBox(width: 12),
                  // ชื่อแอป + คำอธิบายสั้น ๆ (ใช้ Expanded เพื่อไม่ให้ข้อความล้น)
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Berng Fai',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Realtime traffic assistant',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              color: Colors.white12,
            ), // เส้นแบ่งใต้ส่วนหัว
            const SizedBox(height: 8),
            // ---------- เมนูหลัก ----------
            // เมนู: Realtime Detection (หน้าหลัก - ตรวจจับกล้องเรียลไทม์)
            ListTile(
              leading: const Icon(Icons.center_focus_strong_rounded),
              title: const Text('Realtime Detection'),
              selected: true, // ไฮไลต์เป็นหน้าปัจจุบันที่เลือกอยู่
              selectedColor: Colors.white,
              iconColor: Colors.white70,
              textColor: Colors.white,
              selectedTileColor: Colors.white.withValues(
                alpha: 0.08,
              ), // พื้นหลังจาง ๆ สำหรับเมนูที่เลือก
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ), // มุมโค้งให้กับพื้นที่เลือก
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              // เป็นหน้าหลักอยู่แล้ว จึงแค่ปิด Drawer กลับไป (ไม่ต้อง push หน้าใหม่)
              onTap: () => Navigator.of(context).pop(),
            ),
            // ---------- เมนู: Single Image Test (ทดสอบตรวจจับภาพเดียว - Developer tool) ----------

            // ---------- เมนู: Video Test (ทดสอบตรวจจับวิดีโอ - Developer tool) ----------
            ListTile(
              leading: const Icon(Icons.video_file_rounded),
              title: const Text('Video Detection'),

              iconColor: Colors.white70,
              textColor: Colors.white,
              subtitleTextStyle: const TextStyle(color: Colors.white38),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop(); // ปิด Drawer ก่อน
                navigator.push(
                  AppRoutes.videoDetection(),
                ); // ไปยังหน้า Video Test
              },
            ),
            // ---------- เมนู: Settings (หน้าตั้งค่า) ----------
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('Settings'),
              iconColor: Colors.white70,
              textColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop(); // ปิด Drawer ก่อน
                navigator.push(AppRoutes.settings()); // ไปยังหน้าตั้งค่า
              },
            ),
            const Spacer(), // ดัน footer ให้อยู่ด้านล่างสุดของ Drawer
            // ---------- Footer: แสดงสถานะระบบพร้อมทำงาน ----------
            Padding(
              padding: const EdgeInsets.all(20),
              child: const Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: Color(0xFF63E681),
                    size: 8,
                  ), // จุดไฟเขียว = ระบบพร้อม
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detection system',
                      maxLines: 1,
                      overflow: TextOverflow
                          .ellipsis, // ถ้าเกินความกว้างให้ตัดด้วย ...
                      style: TextStyle(color: Colors.white54, fontSize: 12),
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
    // Container: กล่องสี่เหลี่ยมพื้นขาว ทำมุมโค้ง ใช้เป็นพื้นหลังให้โลโก้
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(7), // กันขอบโดยรอบเพื่อให้โลโก้ไม่ชิดกรอบ
      decoration: BoxDecoration(
        color: Colors
            .white, // พื้นหลังสีขาว เพื่อให้โลโก้เข้มเห็นชัดเจนบน Drawer สีดำ
        borderRadius: BorderRadius.circular(14), // มุมโค้ง
      ),
      child: Image.asset(
        'assets/images/app.png', // โหลดโลโก้จากไฟล์ asset
        fit: BoxFit.contain, // ปรับขนาดภาพให้พอดีและคงสัดส่วนเดิม
        // errorBuilder: ถ้าโหลดรูปไม่สำเร็จ (ไฟล์หาย) ให้แสดงไอคอนจราจรสีดำแทน
        errorBuilder: (_, _, _) =>
            const Icon(Icons.traffic_rounded, color: Colors.black),
      ),
    );
  }
}
