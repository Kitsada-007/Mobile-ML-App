import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';
import 'package:trffic_ilght_app/shared/widgets/countdown_badge.dart';

/// แผงแสดงผลการตรวจจับวิดีโอ (สำหรับหน้า Video Inference Screen โดยเฉพาะ)
/// ทำหน้าที่แสดงผลลัพธ์จากการประมวลผลไฟล์วิดีโอ แยกต่างหากจากกล้อง Realtime
class VideoDetectionPanel extends StatelessWidget {
  const VideoDetectionPanel({
    super.key,
    required this.formalNames,
    required this.alertMessages,
    required this.detectedNumber,
    required this.isLandscape,
    this.driverSignalResult,
    this.isPipelineStale = true,
    this.statusText = 'พร้อมตรวจจับวิดีโอ',
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
    final rawDetectedNumber = detectedNumber;
    String numberText;
    if (rawDetectedNumber == null) {
      numberText = '';
    } else {
      numberText = rawDetectedNumber;
    }
    final countdown = int.tryParse(numberText);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDriverMessage =
        driverSignalResult != null && driverSignalResult!.message.isNotEmpty;

    Color panelBackgroundColor;
    Color panelBorderColor;
    double panelShadowAlpha;
    if (isDark) {
      panelBackgroundColor = const Color(0xFF17191C);
      panelBorderColor = Colors.white12;
      panelShadowAlpha = 0.24;
    } else {
      panelBackgroundColor = Colors.white;
      panelBorderColor = const Color(0xFFE7E9ED);
      panelShadowAlpha = 0.07;
    }

    double panelVerticalPadding;
    if (isLandscape) {
      panelVerticalPadding = 12;
    } else {
      panelVerticalPadding = 16;
    }

    final displayItems = _buildDisplayItems(
      formalNames: formalNames,
      alertMessages: alertMessages,
      countdown: countdown,
    );

    Widget messageContent;
    if (hasDriverMessage) {
      messageContent = _VideoDriverSignalMessage(result: driverSignalResult!);
    } else if (displayItems.isEmpty) {
      messageContent = const _VideoScanningMessage();
    } else {
      messageContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in displayItems)
            _VideoDetectionMessage(className: item.$1, alertMessage: item.$2),
        ],
      );
    }

    return DecoratedBox(
      key: const Key('videoDetectionPanel'),
      decoration: BoxDecoration(
        color: panelBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: panelBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: panelShadowAlpha),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          panelVerticalPadding,
          16,
          panelVerticalPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _VideoPanelHeader(),
            const SizedBox(height: 12),
            _VideoPipelineStatus(
              isStale: isPipelineStale,
              statusText: statusText,
              lastDetectionConfidence: lastDetectionConfidence,
            ),
            Divider(color: panelBorderColor, height: 20),
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

class _VideoPanelHeader extends StatelessWidget {
  const _VideoPanelHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        const Icon(
          Icons.video_library_rounded,
          color: Color(0xFF0B9A5A),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'ผลการตรวจจับวิดีโอ',
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
          'การเล่นวิดีโอ',
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

class _VideoPipelineStatus extends StatelessWidget {
  const _VideoPipelineStatus({
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

    Color statusColor;
    String statusSemanticsLabel;
    if (isStale) {
      statusColor = const Color(0xFFE07A1F);
      statusSemanticsLabel = 'ข้อมูลวิดีโอหยุดชั่วคราว';
    } else {
      statusColor = const Color(0xFF0B9A5A);
      statusSemanticsLabel = 'ข้อมูลวิดีโอประมวลผลสด';
    }

    final chips = <Widget>[
      _VideoMetricChip(
        label: statusText,
        foregroundColor: statusColor,
        backgroundColor: statusColor.withValues(alpha: 0.12),
      ),
    ];

    // ความมั่นใจต่ำกว่า 50% ย้อมสีส้มเพื่อเตือนว่าผลอาจไม่น่าเชื่อถือ
    final confidence = lastDetectionConfidence;
    if (confidence != null) {
      Color confidenceColor;
      if (confidence < 0.5) {
        confidenceColor = Colors.orange.shade800;
      } else {
        confidenceColor = colorScheme.onSurfaceVariant;
      }
      chips.add(
        _VideoMetricChip(
          label: 'CONF ${(confidence * 100).round()}%',
          foregroundColor: confidenceColor,
        ),
      );
    }

    return Semantics(
      container: true,
      label: statusSemanticsLabel,
      child: Wrap(
        key: const Key('videoPipelineStatus'),
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: chips,
      ),
    );
  }
}

class _VideoMetricChip extends StatelessWidget {
  const _VideoMetricChip({
    required this.label,
    required this.foregroundColor,
    this.backgroundColor,
  });

  final String label;
  final Color foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final providedBackgroundColor = backgroundColor;
    Color chipBackgroundColor;
    if (providedBackgroundColor == null) {
      chipBackgroundColor = Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest;
    } else {
      chipBackgroundColor = providedBackgroundColor;
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

class _VideoDriverSignalMessage extends StatelessWidget {
  const _VideoDriverSignalMessage({required this.result});

  final DriverSignalResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (barColor, actionIcon, actionLabel) = switch (result.action) {
      SignalAction.go => (
        const Color(0xFF34C759),
        Icons.check_circle_rounded,
        'ไปได้',
      ),
      SignalAction.stop => (
        const Color(0xFFFF3B30),
        Icons.back_hand_rounded,
        'หยุดรอ',
      ),
      SignalAction.caution => (
        const Color(0xFFFF9500),
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

class _VideoScanningMessage extends StatelessWidget {
  const _VideoScanningMessage();

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
            'กำลังตรวจจับป้ายจราจรและสัญญาณไฟในวิดีโอ...',
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

class _VideoDetectionMessage extends StatelessWidget {
  const _VideoDetectionMessage({
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
