import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/services/model_management/models/model_manifest.dart';

/// ฟังก์ชันที่คืนโฟลเดอร์รากสำหรับเก็บโมเดล
typedef RootDirectoryProvider = Future<Directory> Function();

/// อินเทอร์เฟซดาวน์โหลดโมเดล (แยกส่วนเพื่อเทสต์ได้ง่าย)
abstract interface class ModelDownloader {
  Future<File> downloadModel({
    required String modelId,
    required RemoteModelInfo model,
  });
}

/// ดาวน์โหลดโมเดลจาก manifest ลงเครื่อง
/// - ยืนยันขนาดไฟล์ + SHA-256 หลังดาวน์โหลด
/// - เขียนผ่านไฟล์ .part ก่อน แล้ว rename เป็นไฟล์จริงเมื่อผ่านตรวจสอบ
class ModelFileStore implements ModelDownloader {
  ModelFileStore(
    this._client, {
    RootDirectoryProvider? rootDirectoryProvider,
    this.requestTimeout = const Duration(seconds: 30),
  }) {
    if (rootDirectoryProvider == null) {
      _rootDirectoryProvider = getApplicationDocumentsDirectory;
    } else {
      _rootDirectoryProvider = rootDirectoryProvider;
    }
  }

  final http.Client _client;
  late final RootDirectoryProvider _rootDirectoryProvider;
  final Duration requestTimeout;

  @override
  Future<File> downloadModel({
    required String modelId,
    required RemoteModelInfo model,
  }) async {
    _validatePathParts(modelId, model);

    final root = await _rootDirectoryProvider();
    final modelDirectory = Directory(
      <String>[
        root.path,
        'models',
        modelId,
        model.version,
      ].join(Platform.pathSeparator),
    );
    await modelDirectory.create(recursive: true);

    final destination = File(
      '${modelDirectory.path}${Platform.pathSeparator}${model.fileName}',
    );
    final partial = File('${destination.path}.part');
    IOSink? sink;

    try {
      if (await partial.exists()) await partial.delete();

      final request = http.Request('GET', model.url);
      final response = await _client.send(request).timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw ModelDownloadException(
          'Model server returned HTTP ${response.statusCode}',
        );
      }

      if (response.contentLength != null &&
          response.contentLength != model.sizeBytes) {
        throw const ModelDownloadException(
          'Model Content-Length does not match the manifest',
        );
      }

      sink = partial.openWrite();
      var receivedBytes = 0;
      await for (final chunk in response.stream.timeout(requestTimeout)) {
        receivedBytes += chunk.length;
        if (receivedBytes > model.sizeBytes) {
          throw const ModelDownloadException(
            'Downloaded model exceeds its declared size',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (receivedBytes != model.sizeBytes) {
        throw const ModelDownloadException(
          'Downloaded model size does not match the manifest',
        );
      }

      final valid = await verifyFile(
        partial,
        expectedSha256: model.sha256,
        expectedSizeBytes: model.sizeBytes,
      );
      if (!valid) {
        throw const ModelDownloadException(
          'Downloaded model SHA-256 verification failed',
        );
      }

      if (await destination.exists()) await destination.delete();
      return partial.rename(destination.path);
    } on ModelDownloadException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ModelDownloadException('Model download timed out', cause: error);
    } on http.ClientException catch (error) {
      throw ModelDownloadException('Unable to download model', cause: error);
    } on FileSystemException catch (error) {
      throw ModelDownloadException('Unable to store model file', cause: error);
    } catch (error) {
      throw ModelDownloadException(
        'Unexpected model download error',
        cause: error,
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // Preserve the original download failure.
        }
      }
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {
          // A later cleanup pass can remove an orphaned .part file.
        }
      }
    }
  }

  Future<bool> verifyFile(
    File file, {
    required String expectedSha256,
    required int expectedSizeBytes,
  }) => verifyModelFile(
    file,
    expectedSha256: expectedSha256,
    expectedSizeBytes: expectedSizeBytes,
  );

  /// ตรวจว่าข้อมูล path/url ของโมเดลปลอดภัยก่อนเขียนไปยังระบบไฟล์
  void _validatePathParts(String modelId, RemoteModelInfo model) {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(modelId)) {
      throw const ModelDownloadException('Invalid model id');
    }
    if (!RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
    ).hasMatch(model.version)) {
      throw const ModelDownloadException('Invalid model version');
    }
    if (!model.fileName.endsWith('.tflite') ||
        model.fileName.contains('/') ||
        model.fileName.contains(r'\') ||
        model.fileName.contains('..')) {
      throw const ModelDownloadException('Invalid model file name');
    }
    final pathSegments = model.url.pathSegments;
    final isExpectedReleaseAsset =
        pathSegments.length == 6 &&
        pathSegments[0].toLowerCase() == 'kitsada-007' &&
        pathSegments[1].toLowerCase() == 'mobile-ml-app' &&
        pathSegments[2] == 'releases' &&
        pathSegments[3] == 'download' &&
        pathSegments[4].isNotEmpty &&
        pathSegments[5] == model.fileName;
    if (model.url.scheme != 'https' ||
        model.url.host.toLowerCase() != 'github.com' ||
        model.url.userInfo.isNotEmpty ||
        model.url.hasPort ||
        model.url.hasQuery ||
        model.url.hasFragment ||
        !isExpectedReleaseAsset) {
      throw const ModelDownloadException('Invalid model download URL');
    }
  }
}

/// ตรวจสอบไฟล์ว่ามีขนาดและ SHA-256 ตรงกับที่คาดหวังหรือไม่
Future<bool> verifyModelFile(
  File file, {
  required String expectedSha256,
  required int expectedSizeBytes,
}) async {
  try {
    if (!await file.exists() || await file.length() != expectedSizeBytes) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expectedSha256.toLowerCase();
  } on FileSystemException {
    return false;
  }
}

/// ข้อยกเว้นของการดาวน์โหลดโมเดลล้มเหลว
class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ModelDownloadException: $message';
}
