import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// อ่าน provider แบบไม่บังคับว่าต้องมีอยู่จริง
///
/// หน้าจอในแอปถูก pump เดี่ยว ๆ ในเทสต์ (ไม่มี MultiProvider ครอบ) การเรียก
/// Provider.of ตรง ๆ จะโยน ProviderNotFoundException ทิ้งทั้งหน้าจอ
/// ฟังก์ชันนี้จึงคืน null ให้ผู้เรียกตัดสินใจใช้ค่าสำรองเองแทน
///
/// ใช้นอก build() เท่านั้น (listen: false) เช่นใน initState
T? readOptionalProvider<T extends Object>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
