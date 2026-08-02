import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:trffic_ilght_app/core/services/model_management/models/model_manifest.dart';

abstract interface class ModelManifestSource {
  Future<ModelManifest> fetchLatestManifest();
}

class ModelUpdateClient implements ModelManifestSource {
  ModelUpdateClient(
    this._client, {
    required this.manifestUri,
    this.requestTimeout = const Duration(seconds: 15),
    this.maximumManifestSizeBytes = 256 * 1024,
  });

  final http.Client _client;
  final Uri manifestUri;
  final Duration requestTimeout;
  final int maximumManifestSizeBytes;

  @override
  Future<ModelManifest> fetchLatestManifest() async {
    _validateManifestUri();

    try {
      final request = http.Request('GET', manifestUri)
        ..headers.addAll(const <String, String>{
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        });

      final response = await _client.send(request).timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw ModelManifestFetchException(
          'GitHub returned HTTP ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maximumManifestSizeBytes) {
        throw const ModelManifestFetchException(
          'Manifest exceeds the maximum allowed size',
        );
      }

      final bytes = BytesBuilder(copy: false);
      var receivedBytes = 0;
      await for (final chunk in response.stream.timeout(requestTimeout)) {
        receivedBytes += chunk.length;
        if (receivedBytes > maximumManifestSizeBytes) {
          throw const ModelManifestFetchException(
            'Manifest exceeds the maximum allowed size',
          );
        }
        bytes.add(chunk);
      }

      if (receivedBytes == 0) {
        throw const ModelManifestFetchException('Manifest response is empty');
      }

      final decoded = jsonDecode(
        utf8.decode(bytes.takeBytes(), allowMalformed: false),
      );
      if (decoded is! Map) {
        throw const ModelManifestFetchException(
          'Manifest root must be a JSON object',
        );
      }

      return ModelManifest.fromJson(Map<String, dynamic>.from(decoded));
    } on ModelManifestFetchException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ModelManifestFetchException(
        'Manifest request timed out',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ModelManifestFetchException(
        'Unable to download manifest',
        cause: error,
      );
    } on FormatException catch (error) {
      throw ModelManifestFetchException(
        'Manifest JSON or validation is invalid: ${error.message}',
        cause: error,
      );
    } catch (error) {
      throw ModelManifestFetchException(
        'Unexpected manifest download error',
        cause: error,
      );
    }
  }

  void _validateManifestUri() {
    if (manifestUri.scheme != 'https' ||
        manifestUri.host.toLowerCase() != 'github.com') {
      throw const ModelManifestFetchException(
        'Manifest URL must use HTTPS on github.com',
      );
    }

    const expectedPath =
        '/Kitsada-007/Mobile-ML-App/'
        'releases/latest/download/model_manifest.json';
    if (manifestUri.path != expectedPath ||
        manifestUri.hasQuery ||
        manifestUri.hasFragment) {
      throw const ModelManifestFetchException(
        'Manifest URL does not point to the expected repository asset',
      );
    }
  }
}

class ModelManifestFetchException implements Exception {
  const ModelManifestFetchException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ModelManifestFetchException: $message';
}
