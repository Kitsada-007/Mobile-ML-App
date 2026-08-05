import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';

/// Live traffic-sign results displayed below the camera preview.
class CameraDetectionPanel extends StatelessWidget {
  const CameraDetectionPanel({
    super.key,
    required this.formalNames,
    required this.alertMessages,
    required this.detectedNumber,
    required this.isLandscape,
    this.isPipelineStale = true,
    this.statusText = 'กำลังตรวจจับ',
    this.lastDetectionConfidence,
  });

  final List<String> formalNames;
  final List<String> alertMessages;
  final String? detectedNumber;
  final bool isLandscape;
  final bool isPipelineStale;
  final String statusText;
  final double? lastDetectionConfidence;

  @override
  Widget build(BuildContext context) {
    final countdown = int.tryParse(detectedNumber ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      key: const Key('cameraDetectionPanel'),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17191C) : Colors.white,
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
            const _PanelHeader(),
            const SizedBox(height: 12),
            _RealtimePipelineStatus(
              isStale: isPipelineStale,
              statusText: statusText,
              lastDetectionConfidence: lastDetectionConfidence,
            ),
            Divider(
              color: isDark ? Colors.white12 : const Color(0xFFE7E9ED),
              height: 20,
            ),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CountdownBadge(countdown: countdown),
                  const SizedBox(width: 12),
                  Expanded(
                    child: formalNames.isEmpty
                        ? const _ScanningMessage()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var index = 0;
                                index < formalNames.length;
                                index++
                              )
                                _DetectionMessage(
                                  className: formalNames[index],
                                  alertMessage: index < alertMessages.length
                                      ? alertMessages[index]
                                      : '',
                                  detectedNumber: detectedNumber,
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
          _PipelineMetricChip(
            label: statusText,
            foregroundColor: statusColor,
            backgroundColor: statusColor.withValues(alpha: 0.12),
          ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
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

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.countdown});

  final int? countdown;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: countdown == null
          ? 'ไม่พบตัวเลขนับถอยหลัง'
          : 'ตัวเลขนับถอยหลัง $countdown วินาที',
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: const Color(0xFFFFEEEE),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFD6D6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              countdown?.toString() ?? 'X',
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFFE63D3D),
                fontSize: 38,
                height: 0.95,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              countdown == null ? 'ไม่พบตัวเลข' : 'วินาที',
              style: const TextStyle(
                color: Color(0xFF9F3A3A),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _DetectionMessage extends StatelessWidget {
  const _DetectionMessage({
    required this.className,
    required this.alertMessage,
    required this.detectedNumber,
  });

  final String className;
  final String alertMessage;
  final String? detectedNumber;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final countdown = int.tryParse(detectedNumber ?? '');
    final isCountdownSignal =
        className == 'สัญญาณไฟนับถอยหลัง' && countdown != null;
    final message = isCountdownSignal
        ? shouldPrepareToGo(countdown)
              ? 'เตรียมตัวไป'
              : 'สัญญาณไฟนับถอยหลัง $countdown วินาที'
        : alertMessage.isNotEmpty
        ? alertMessage
        : className;

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
