import 'package:trffic_ilght_app/core/models/semantic_version.dart';

class ModelManifest {
  const ModelManifest({
    required this.schemaVersion,
    required this.releaseVersion,
    required this.minimumAppVersion,
    required this.models,
  });

  final int schemaVersion;
  final String releaseVersion;
  final String minimumAppVersion;
  final Map<String, RemoteModelInfo> models;

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');

    if (schemaVersion != 1) {
      throw const FormatException('Unsupported model manifest schemaVersion');
    }

    final releaseVersion = _requiredString(json, 'releaseVersion');
    final minimumAppVersion = _requiredString(json, 'minimumAppVersion');

    _validateVersion(releaseVersion, fieldName: 'releaseVersion');
    _validateVersion(minimumAppVersion, fieldName: 'minimumAppVersion');

    final modelsValue = json['models'];

    if (modelsValue is! Map) {
      throw const FormatException('models must be a JSON object');
    }

    final modelsJson = Map<String, dynamic>.from(modelsValue);

    // แอปนี้ต้องมีโมเดล traffic และ number
    for (final requiredModel in ['traffic', 'number']) {
      if (!modelsJson.containsKey(requiredModel)) {
        throw FormatException('Missing required model: $requiredModel');
      }
    }

    final models = <String, RemoteModelInfo>{};

    for (final entry in modelsJson.entries) {
      final modelId = entry.key;
      final modelValue = entry.value;

      if (!_modelIdPattern.hasMatch(modelId)) {
        throw FormatException('Invalid model id: $modelId');
      }

      if (modelValue is! Map) {
        throw FormatException('Model "$modelId" must be a JSON object');
      }

      models[modelId] = RemoteModelInfo.fromJson(
        modelId,
        Map<String, dynamic>.from(modelValue),
      );
    }

    return ModelManifest(
      schemaVersion: schemaVersion,
      releaseVersion: releaseVersion,
      minimumAppVersion: minimumAppVersion,
      models: Map.unmodifiable(models),
    );
  }
}

class RemoteModelInfo {
  const RemoteModelInfo({
    required this.version,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  final String version;
  final String fileName;
  final Uri url;
  final String sha256;
  final int sizeBytes;

  static const int maximumModelSizeBytes = 500 * 1024 * 1024; // 500 MB

  factory RemoteModelInfo.fromJson(String modelId, Map<String, dynamic> json) {
    final version = _requiredString(json, 'version');
    final fileName = _requiredString(json, 'fileName');
    final urlText = _requiredString(json, 'url');
    final sha256 = _requiredString(json, 'sha256').toLowerCase();
    final sizeBytes = _requiredInt(json, 'sizeBytes');

    _validateVersion(version, fieldName: '$modelId.version');

    _validateFileName(fileName, fieldName: '$modelId.fileName');

    final url = _validateModelUrl(
      urlText,
      fileName: fileName,
      fieldName: '$modelId.url',
    );

    if (!_sha256Pattern.hasMatch(sha256)) {
      throw FormatException(
        '$modelId.sha256 must contain 64 hexadecimal characters',
      );
    }

    if (sizeBytes <= 0) {
      throw FormatException('$modelId.sizeBytes must be greater than zero');
    }

    if (sizeBytes > maximumModelSizeBytes) {
      throw FormatException(
        '$modelId.sizeBytes exceeds the maximum allowed size',
      );
    }

    return RemoteModelInfo(
      version: version,
      fileName: fileName,
      url: url,
      sha256: sha256,
      sizeBytes: sizeBytes,
    );
  }
}

final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

final RegExp _modelIdPattern = RegExp(r'^[a-z][a-z0-9_-]*$');

String _requiredString(Map<String, dynamic> json, String fieldName) {
  final value = json[fieldName];

  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string');
  }

  return value.trim();
}

int _requiredInt(Map<String, dynamic> json, String fieldName) {
  final value = json[fieldName];

  if (value is! int) {
    throw FormatException('$fieldName must be an integer');
  }

  return value;
}

void _validateVersion(String version, {required String fieldName}) {
  try {
    SemanticVersion.parse(version);
  } on FormatException {
    throw FormatException('$fieldName must use major.minor.patch format');
  }
}

void _validateFileName(String fileName, {required String fieldName}) {
  if (!fileName.endsWith('.tflite')) {
    throw FormatException('$fieldName must end with .tflite');
  }

  if (fileName.contains('/') ||
      fileName.contains(r'\') ||
      fileName.contains('..')) {
    throw FormatException('$fieldName must not contain a path');
  }

  if (fileName != fileName.trim()) {
    throw FormatException('$fieldName contains invalid whitespace');
  }
}

Uri _validateModelUrl(
  String urlText, {
  required String fileName,
  required String fieldName,
}) {
  final url = Uri.tryParse(urlText);

  if (url == null || !url.hasScheme || !url.hasAuthority) {
    throw FormatException('$fieldName is not a valid URL');
  }

  if (url.scheme != 'https') {
    throw FormatException('$fieldName must use HTTPS');
  }

  if (url.host.toLowerCase() != 'github.com') {
    throw FormatException('$fieldName must use github.com');
  }

  // จำกัดให้ดาวน์โหลดจาก repository ของโปรเจกต์เท่านั้น
  const requiredPathPrefix = '/Kitsada-007/Mobile-ML-App/releases/download/';

  if (!url.path.startsWith(requiredPathPrefix)) {
    throw FormatException(
      '$fieldName must point to the Mobile-ML-App repository',
    );
  }

  if (url.pathSegments.isEmpty || url.pathSegments.last != fileName) {
    throw FormatException('$fieldName file name does not match $fileName');
  }

  if (url.hasQuery || url.hasFragment) {
    throw FormatException('$fieldName must not contain query or fragment');
  }

  return url;
}
