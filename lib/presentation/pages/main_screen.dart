import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/pages/camera_inference_page.dart';
import 'package:trffic_ilght_app/presentation/pages/setting_page.dart';
import 'package:trffic_ilght_app/presentation/pages/single_image_screen.dart';
import 'package:trffic_ilght_app/presentation/pages/video_inference_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.initializeCamera = true});

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
      backgroundColor: Colors.black,
      drawer: const _AppDrawer(),
      drawerScrimColor: Colors.black.withValues(alpha: 0.72),
      body: CameraInferencePage(
        initializeOnStart: widget.initializeCamera,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF111111),
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
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.center_focus_strong_rounded),
              title: const Text('Realtime Detection'),
              selected: true,
              selectedColor: Colors.white,
              iconColor: Colors.white70,
              textColor: Colors.white,
              selectedTileColor: Colors.white.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.image_search_rounded),
              title: const Text('Single Image Test'),
              subtitle: const Text('Developer test tool'),
              iconColor: Colors.white70,
              textColor: Colors.white,
              subtitleTextStyle: const TextStyle(color: Colors.white38),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SingleImageScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_file_rounded),
              title: const Text('Video Test'),
              subtitle: const Text('Developer test tool'),
              iconColor: Colors.white70,
              textColor: Colors.white,
              subtitleTextStyle: const TextStyle(color: Colors.white38),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => VideoInferenceScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('Settings'),
              iconColor: Colors.white70,
              textColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(builder: (_) => const SettingPage()),
                );
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Color(0xFF63E681), size: 8),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detection system ready',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
