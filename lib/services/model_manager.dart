import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:ultralytics_yolo/config/channel_config.dart';

/// Manages YOLO model loading from local assets for Android only (Offline Mode).
class ModelManager {
  static final MethodChannel _channel =
      ChannelConfig.createSingleImageChannel();

  /// Callback for status message updates
  final void Function(String message)? onStatusUpdate;

  ModelManager({this.onStatusUpdate});

  /// ดึง Path ของไฟล์โมเดล (รองรับเฉพาะ Android)
  Future<String?> getModelPath(ModelType modelType) async {
    // ดักไว้ก่อนเลยว่าถ้าไม่ใช่ Android ไม่ต้องทำต่อ
    if (!Platform.isAndroid) {
      _updateStatus('แอปพลิเคชันนี้รองรับเฉพาะระบบ Android');
      return null;
    }

    _updateStatus('กำลังตรวจสอบโมเดล ${modelType.modelName}...');

    // จัดการนามสกุลไฟล์ (Default เป็น .tflite)
    String bundledName = modelType.modelName;
    if (!bundledName.endsWith('.tflite') &&
        !bundledName.endsWith('.pt') &&
        !bundledName.endsWith('.onnx')) {
      bundledName = '$bundledName.tflite';
    }

    // 1. ลองเช็คผ่าน Native Channel ก่อน (ปลั๊กอินบางตัวจัดการ path ให้)
    try {
      final result = await _channel.invokeMethod('checkModelExists', {
        'modelPath': bundledName,
      });
      if (result != null && result['exists'] == true) {
        return result['location'] == 'assets'
            ? bundledName
            : result['path'] as String;
      }
    } catch (_) {}

    // 2. เช็คใน Local Storage ของแอป (กรณีเคยเปิดแอปแล้วก๊อปปี้ไฟล์ไว้แล้ว)
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File('${dir.path}/$bundledName');
    if (await modelFile.exists()) return modelFile.path;

    try {
      _updateStatus('กำลังเตรียมไฟล์โมเดลจากเครื่อง...');

      // ✅ ลบคำว่า 'assets/models/' ออกไปเลย ให้ใช้ค่าที่ส่งมาตรงๆ
      final assetPath = bundledName;
      final assetData = await rootBundle.load(assetPath);

      await modelFile.parent.create(recursive: true);
      await modelFile.writeAsBytes(assetData.buffer.asUint8List());
      return modelFile.path;
    } catch (e) {
      print('เกิดข้อผิดพลาดในการโหลดโมเดล Android จาก assets: $e');
      return null;
    }
  }

  /// Updates the status message
  void _updateStatus(String message) => onStatusUpdate?.call(message);
}
