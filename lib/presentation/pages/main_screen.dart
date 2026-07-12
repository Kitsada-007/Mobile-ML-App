import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/pages/home_page.dart';
import 'package:trffic_ilght_app/presentation/pages/setting_page.dart';
import 'package:trffic_ilght_app/presentation/widgets/bottom_navigation_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: const [
          HomePage(),
          SettingPage(),
        ],
      ),
      bottomNavigationBar: MyBottomNavigationBar(
        selectedIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
