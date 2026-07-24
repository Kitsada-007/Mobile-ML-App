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
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          isLandscape ? 72 : 12,
          isLandscape ? 60 : 72,
          isLandscape ? 72 : 12,
          0,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('cameraDetectionPanel'),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
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
            'AI TRAFFIC SCANNER',
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

class _ScanningMessage extends StatelessWidget {
  const _ScanningMessage();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
