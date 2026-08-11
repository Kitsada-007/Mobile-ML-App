import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart'; // โครงสร้าง DriverSignalResult / SignalAction
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart'; // helper เลขไทย (shouldPrepareToGo)

/// แผงแสดงผลสัญญาณจราจรสด (อยู่ใต้ preview กล้อง/วิดีโอ)
/// - แสดงสถานะ pipeline + confidence
/// - แสดงตัวเลขนับถอยหลัง + ข้อความผลการตรวจจับภาษาไทย
/// - (ถ้ามี) แสดงคำสั่งคนขับผลจาก SignalInterpreter เช่น ไปได้/หยุดรอ/ระวัง
class CameraDetectionPanel extends StatelessWidget {
  const CameraDetectionPanel({
    super.key,
    required this.formalNames, // ชื่อไทยทางการของป้าย/สัญญาณที่พบ
    required this.alertMessages, // ข้อความแจ้งเตือนภาษาไทย
    required this.detectedNumber, // ตัวเลขนับถอยหลัง (ถ้ามี)
    required this.isLandscape, // ปรับ padding ตามแนว/ขวาง
    this.driverSignalResult, // คำสั่งคนขับจาก signal interpreter (optional)
    this.isPipelineStale = true, // pipeline ล้าสมัยไหม (default ล้าสมัย)
    this.statusText = 'กำลังตรวจจับ', // ข้อความสถานะ
    this.lastDetectionConfidence, // confidence สูงสุดล่าสุด
  });

  final List<String> formalNames;
  final List<String> alertMessages;
  final String? detectedNumber;
  final bool isLandscape;
  final DriverSignalResult? driverSignalResult;
  final bool isPipelineStale;
  final String statusText;
  final double? lastDetectionConfidence;

  @override
  Widget build(BuildContext context) {
    final countdown = int.tryParse(detectedNumber ?? ''); // แปลงตัวเลขเป็น int
    final isDark =
        Theme.of(context).brightness == Brightness.dark; // ธีมมืด/สว่าง
    final hasDriverMessage =
        driverSignalResult != null &&
        driverSignalResult!.message.isNotEmpty; // มีข้อความคำสั่งคนขับไหม

    final displayItems = _buildDisplayItems(
      formalNames: formalNames,
      alertMessages: alertMessages,
      countdown: countdown,
    );

    return DecoratedBox(
      key: const Key('cameraDetectionPanel'),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF17191C)
            : Colors.white, // พื้นหลังตามธีม
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE7E9ED),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          isLandscape ? 12 : 16,
          16,
          isLandscape ? 12 : 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelHeader(), // หัว "ผลการตรวจจับ"
            const SizedBox(height: 12),
            _RealtimePipelineStatus(
              // แถวสถานะ pipeline + confidence
              isStale: isPipelineStale,
              statusText: statusText,
              lastDetectionConfidence: lastDetectionConfidence,
            ),
            Divider(
              color: isDark ? Colors.white12 : const Color(0xFFE7E9ED),
              height: 20,
            ),
            // เนื้อหาหลัก: ตัวเลขนับถอยหลัง + ข้อความตรวจจับ
            Semantics(
              liveRegion: true, // screen reader อ่านการเปลี่ยนแบบสด
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CountdownBadge(countdown: countdown), // ป้ายตัวเลขนับถอยหลัง
                  const SizedBox(width: 12),
                  Expanded(
                    child: hasDriverMessage
                        // มีคำสั่งคนขับ -> แสดงข้อความจาก SignalInterpreter
                        ? _DriverSignalMessage(result: driverSignalResult!)
                        : displayItems.isEmpty
                        ? const _ScanningMessage() // ยังไม่มีอะไร -> กำลังสแกน
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // แสดงข้อความตรวจจับทุกคลาสที่พบ
                              for (final item in displayItems)
                                _DetectionMessage(
                                  className: item.$1,
                                  alertMessage: item.$2,
                                ),
                            ],
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

/// แสดงข้อความคำสั่งคนขับ (จาก SignalInterpreter) พร้อมสี/ไอคอนตาม action
class _DriverSignalMessage extends StatelessWidget {
  const _DriverSignalMessage({required this.result});

  final DriverSignalResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // กำหนด (สี, ไอคอน, ป้ายข้อความ) ตามประเภท action ของสัญญาณ
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
          // แถบสีแนวตั้งทางซ้าย (บอกประเภท action)
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          // ข้อความหลักของคำสั่งคนขับ
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
          // ป้าย action (เช่น "ไปได้") ทางขวา ถ้ามี
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

  final bool isStale; // pipeline ล้าสมัยไหม
  final String statusText; // ข้อความสถานะ
  final double? lastDetectionConfidence; // confidence สูงสุดล่าสุด

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // สีตามสถานะ: ล้าสมัย = ส้ม, ปกติ = เขียว
    final statusColor = isStale
        ? const Color(0xFFE07A1F)
        : const Color(0xFF0B9A5A);

    return Semantics(
      container: true,
      label: isStale ? 'ข้อมูลจากกล้องล่าช้า' : 'ข้อมูลจากกล้องเป็นปัจจุบัน',
      child: Wrap(
        key: const Key('realtimePipelineStatus'),
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // ชิปสถานะ pipeline
          _PipelineMetricChip(
            label: statusText,
            foregroundColor: statusColor,
            backgroundColor: statusColor.withValues(alpha: 0.12),
          ),
          // ชิปค่า confidence (ถ้ามี) — สีเปลี่ยนเป็นส้มถ้าต่ำกว่า 0.5
          if (lastDetectionConfidence != null)
            _PipelineMetricChip(
              label: 'CONF ${(lastDetectionConfidence! * 100).round()}%',
              foregroundColor: lastDetectionConfidence! < 0.5
                  ? Colors.orange.shade800
                  : colorScheme.onSurfaceVariant,
            ),
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

  final String label; // ข้อความ
  final Color foregroundColor; // สีข้อความ
  final Color? backgroundColor; // สีพื้น (default จากธีม)

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999), // มุมโค้งเต็ม
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
        // จุดเขียว + ข้อความ "กำลังทำงาน"
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

/// ป้ายตัวเลขนับถอยหลัง (กล่องแดงด้านซ้าย)
class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.countdown});

  final int? countdown; // ตัวเลข (null = ไม่พบ)

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: countdown == null
          ? 'ไม่พบตัวเลขนับถอยหลัง'
          : 'ตัวเลขนับถอยหลัง $countdown วินาที',
      child: Container(
        width: 86,
        height: 86,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEEEE), // พื้นแดงอ่อน
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFD6D6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ตัวเลขขนาดใหญ่ (หรือ "X" เมื่อไม่พบ)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                countdown?.toString() ?? 'X',
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFFE63D3D),
                  fontSize: 36,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // คำว่า "วินาที" หรือ "ไม่พบตัวเลข"
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                countdown == null ? 'ไม่พบตัวเลข' : 'วินาที',
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFF9F3A3A),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
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
        // จุดสีเขียวมีแสง
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
    required this.className, // ชื่อภาษาไทยของคลาส
    required this.alertMessage, // ข้อความแจ้งเตือน
  });

  final String className;
  final String alertMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = alertMessage.isNotEmpty ? alertMessage : className;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // แถบสีแนวตั้ง (สีตามชื่อคลาส/ความหมาย)
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
    if (name.contains('เหลือง') || name.contains('กะพริบ')) {
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
    final alert = index < alertMessages.length ? alertMessages[index] : '';
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
