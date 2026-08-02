import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';

/// Live traffic-sign messages displayed over the fullscreen camera preview.
class CameraDetectionPanel extends StatelessWidget {
  const CameraDetectionPanel({
    super.key,
    required this.formalNames,
    required this.alertMessages,
    required this.detectedNumber,
    required this.isLandscape,
  });

  final List<String> formalNames;
  final List<String> alertMessages;
  final String? detectedNumber;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final countdown = int.tryParse(detectedNumber ?? '');

    return Positioned(
      key: const Key('cameraDetectionPanelPosition'),
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          isLandscape ? 72 : 16,
          0,
          isLandscape ? 72 : 16,
          isLandscape ? 8 : 12,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('cameraDetectionPanel'),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    isLandscape ? 8 : 12,
                    12,
                    isLandscape ? 8 : 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _PanelHeader(),
                      const Divider(color: Colors.white24, height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (countdown != null) ...[
                              _CountdownBadge(countdown: countdown),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: formalNames.isEmpty
                                  ? const _ScanningMessage()
                                  : ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: isLandscape ? 72 : 160,
                                      ),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (
                                              var index = 0;
                                              index < formalNames.length;
                                              index++
                                            )
                                              _DetectionMessage(
                                                className: formalNames[index],
                                                alertMessage:
                                                    index < alertMessages.length
                                                    ? alertMessages[index]
                                                    : '',
                                                detectedNumber: detectedNumber,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    return Row(
      children: [
        const Icon(Icons.sensors_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'LIVE DETECTION',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
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
          'ACTIVE',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.countdown});

  final int countdown;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ตัวเลขนับถอยหลัง $countdown วินาที',
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$countdown',
              maxLines: 1,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 34,
                height: 0.95,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'SECONDS',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
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
              color: Colors.white.withValues(alpha: 0.72),
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
              style: const TextStyle(
                color: Colors.white,
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
