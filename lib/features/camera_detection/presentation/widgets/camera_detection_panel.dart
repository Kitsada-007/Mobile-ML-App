import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';
import 'package:trffic_ilght_app/shared/widgets/countdown_badge.dart';

/// แผงแสดงผลสัญญาณจราจรสด (อยู่ใต้ preview กล้อง/วิดีโอ)
/// - แสดงสถานะ pipeline + confidence
/// - แสดงตัวเลขนับถอยหลัง + ข้อความผลการตรวจจับภาษาไทย
/// - (ถ้ามี) แสดงคำสั่งคนขับผลจาก SignalInterpreter เช่น ไปได้/หยุดรอ/ระวัง
class CameraDetectionPanel extends StatelessWidget {
  const CameraDetectionPanel({
    super.key,
    required this.formalNames,
    required this.alertMessages,
    required this.detectedNumber,
    required this.isLandscape, // ปรับ padding ตามแนว/ขวาง
    this.driverSignalResult,
    this.isPipelineStale = true,
    this.statusText = 'กำลังตรวจจับ',
    this.lastDetectionConfidence,
    this.trafficLightClassName,
  });

  final List<String> formalNames;
  final List<String> alertMessages;
  final String? detectedNumber;
  final bool isLandscape;

  /// คลาสไฟจราจรเสถียร (จาก controller) ใช้เลือกสีป้ายนับถอยหลัง
  final String? trafficLightClassName;
  final DriverSignalResult? driverSignalResult;
  final bool isPipelineStale;
  final String statusText;
  final double? lastDetectionConfidence;

  @override
  Widget build(BuildContext context) {
    String numberText;
    final detected = detectedNumber;
    if (detected == null) {
      numberText = '';
    } else {
      numberText = detected;
    }
    final countdown = int.tryParse(numberText);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDriverMessage =
        driverSignalResult != null && driverSignalResult!.message.isNotEmpty;

    final displayItems = _buildDisplayItems(
      formalNames: formalNames,
      alertMessages: alertMessages,
      countdown: countdown,
    );

    // สีพื้น/เส้นขอบ/เงา ของแผง เปลี่ยนตามธีมสว่าง-มืด
    Color panelColor;
    Color outlineColor;
    double shadowAlpha;
    if (isDark) {
      panelColor = const Color(0xFF17191C);
      outlineColor = Colors.white12;
      shadowAlpha = 0.24;
    } else {
      panelColor = Colors.white;
      outlineColor = const Color(0xFFE7E9ED);
      shadowAlpha = 0.07;
    }

    // แนวนอนมีเนื้อที่แนวตั้งน้อยกว่า จึงลด padding บน-ล่าง
    double verticalPadding;
    if (isLandscape) {
      verticalPadding = 12;
    } else {
      verticalPadding = 16;
    }

    Widget messageContent;
    if (hasDriverMessage) {
      messageContent = _DriverSignalMessage(result: driverSignalResult!);
    } else if (displayItems.isEmpty) {
      messageContent = const _ScanningMessage();
    } else {
      messageContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in displayItems)
            _DetectionMessage(className: item.$1, alertMessage: item.$2),
        ],
      );
    }

    return DecoratedBox(
      key: const Key('cameraDetectionPanel'),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowAlpha),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, verticalPadding, 16, verticalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelHeader(),
            const SizedBox(height: 12),
            _RealtimePipelineStatus(
              isStale: isPipelineStale,
              statusText: statusText,
              lastDetectionConfidence: lastDetectionConfidence,
            ),
            Divider(color: outlineColor, height: 20),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CountdownBadge(
                    countdown: countdown,
                    trafficLightClassName: trafficLightClassName,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: messageContent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// แสดงข้อความคำสั่งคนขับ (จาก SignalInterpreter) พร้อมสี/ไอคอนตาม action
class _DriverSignalMessage extends StatelessWidget {
  const _DriverSignalMessage({required this.result});

  final DriverSignalResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (barColor, actionIcon, actionLabel) = switch (result.action) {
      SignalAction.go => (
        const Color(0xFF34C759), // เขียว
        Icons.check_circle_rounded,
        'ไปได้',
      ),
      SignalAction.stop => (
        const Color(0xFFFF3B30), // แดง
        Icons.back_hand_rounded,
        'หยุดรอ',
      ),
      SignalAction.caution => (
        const Color(0xFFFF9500), // ส้ม
        Icons.warning_amber_rounded,
        'ระวัง',
      ),
      SignalAction.none => (Colors.grey, Icons.info_outline_rounded, ''),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                result.message,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ),
          if (actionLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: barColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(actionIcon, size: 16, color: barColor),
                    const SizedBox(width: 4),
                    Text(
                      actionLabel,
                      style: TextStyle(
                        color: barColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// แถวสถานะของ pipeline (ข้อความสถานะ + เปอร์เซ็นต์ confidence)
class _RealtimePipelineStatus extends StatelessWidget {
  const _RealtimePipelineStatus({
    required this.isStale,
    required this.statusText,
    required this.lastDetectionConfidence,
  });

  final bool isStale;
  final String statusText;
  final double? lastDetectionConfidence;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // สีตามสถานะ: ล้าสมัย = ส้ม, ปกติ = เขียว
    Color statusColor;
    // ป้ายกำกับสำหรับ screen reader ต้องบอกสถานะเดียวกับสีที่เห็น
    String semanticsLabel;
    if (isStale) {
      statusColor = const Color(0xFFE07A1F);
      semanticsLabel = 'ข้อมูลจากกล้องล่าช้า';
    } else {
      statusColor = const Color(0xFF0B9A5A);
      semanticsLabel = 'ข้อมูลจากกล้องเป็นปัจจุบัน';
    }

    // ชิป confidence จะแสดงเฉพาะเมื่อมีค่า จึงสร้างไว้ล่วงหน้าเป็น Widget?
    Widget? confidenceChip;
    final confidence = lastDetectionConfidence;
    if (confidence != null) {
      Color confidenceColor;
      if (confidence < 0.5) {
        confidenceColor = Colors.orange.shade800;
      } else {
        confidenceColor = colorScheme.onSurfaceVariant;
      }
      confidenceChip = _PipelineMetricChip(
        label: 'CONF ${(confidence * 100).round()}%',
        foregroundColor: confidenceColor,
      );
    }

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Wrap(
        key: const Key('realtimePipelineStatus'),
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _PipelineMetricChip(
            label: statusText,
            foregroundColor: statusColor,
            backgroundColor: statusColor.withValues(alpha: 0.12),
          ),
          ?confidenceChip,
        ],
      ),
    );
  }
}

/// ชิปเล็ก ๆ สำหรับแสดงป้ายสั้น ๆ (สถานะ/ค่า metric)
class _PipelineMetricChip extends StatelessWidget {
  const _PipelineMetricChip({
    required this.label,
    required this.foregroundColor,
    this.backgroundColor,
  });

  final String label;
  final Color foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    Color chipBackgroundColor;
    final providedBackground = backgroundColor;
    if (providedBackground == null) {
      chipBackgroundColor = Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest;
    } else {
      chipBackgroundColor = providedBackground;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chipBackgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// ส่วนหัวของแผง: หัวข้อ "ผลการตรวจจับ" + ไฟสถานะ "กำลังทำงาน"
class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        const Icon(
          Icons.center_focus_strong_rounded,
          color: Color(0xFF0B9A5A),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'ผลการตรวจจับ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF34C759),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'กำลังทำงาน',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// ข้อความชั่วคราวเมื่อยังไม่มีผลตรวจจับ (กำลังสแกน)
class _ScanningMessage extends StatelessWidget {
  const _ScanningMessage();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFF63E681),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x8063E681), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'กำลังสแกนหาป้ายจราจรและสัญญาณไฟ...',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// แถวข้อความการตรวจจับ 1 คลาส (มีแถบสีซ้าย + ข้อความ)
class _DetectionMessage extends StatelessWidget {
  const _DetectionMessage({
    required this.className,
    required this.alertMessage,
  });

  final String className;
  final String alertMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    String message;
    if (alertMessage.isNotEmpty) {
      message = alertMessage;
    } else {
      message = className;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: _alertColor(className),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// เลือกสีของแถบตามคำในชื่อคลาส (แดง/เหลือง/เขียว/น้ำเงิน)
  Color _alertColor(String name) {
    if (name.contains('แดง') || name.contains('ห้าม')) {
      return Colors.redAccent;
    }
    if (name.contains('เหลือง')) {
      return Colors.orangeAccent;
    }
    if (name.contains('เขียว') ||
        name.contains('เลี้ยว') ||
        name.contains('ตรง')) {
      return Colors.greenAccent;
    }
    return Colors.blueAccent;
  }
}

List<(String className, String alertMessage)> _buildDisplayItems({
  required List<String> formalNames,
  required List<String> alertMessages,
  required int? countdown,
}) {
  final displayItems = <(String className, String alertMessage)>[];
  for (var index = 0; index < formalNames.length; index++) {
    final name = formalNames[index];
    String alert;
    if (index < alertMessages.length) {
      alert = alertMessages[index];
    } else {
      alert = '';
    }
    final isCountdownSignal =
        name == 'สัญญาณไฟนับถอยหลัง' || name == 'sign_number';

    if (isCountdownSignal) {
      if (countdown != null && shouldPrepareToGo(countdown)) {
        displayItems.add((name, 'เตรียมตัวไป'));
      }
    } else {
      displayItems.add((name, alert));
    }
  }
  return displayItems;
}
