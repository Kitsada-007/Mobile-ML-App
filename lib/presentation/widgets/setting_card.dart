import 'package:flutter/material.dart';

class SettingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData headerIcon;
  final Color headerIconColor;
  final Color headerIconBg;
  final Widget child;

  const SettingCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.headerIcon,
    required this.headerIconColor,
    required this.headerIconBg,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: headerIconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(headerIcon, color: headerIconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Content (Switch, Slider, Button, etc.)
          child,
        ],
      ),
    );
  }
}
