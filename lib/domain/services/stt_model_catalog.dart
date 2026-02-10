/// Catalog of supported offline STT models (Whisper).
///
/// Models are downloaded once, then used fully offline.
class SttModelOption {
  final String id;
  final String name;
  final String description;
  final int sizeBytes;
  final String downloadUrl;

  const SttModelOption({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  String get fileName => downloadUrl.split('/').last;
}

class SttModelCatalog {
  // HuggingFace repo with whisper.cpp-converted models.
  static const _hfBase =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  /// Multilingual Whisper models.
  ///
  /// Note: `small` is ~466 MiB (your choice: better accuracy, heavier).
  static const List<SttModelOption> models = [
    SttModelOption(
      id: 'base',
      name: 'Whisper Base (multilingual)',
      description: 'Faster, lower accuracy than Small.',
      sizeBytes: 142 * 1024 * 1024, // approximate; server is source of truth
      downloadUrl: '$_hfBase/ggml-base.bin',
    ),
    SttModelOption(
      id: 'small',
      name: 'Whisper Small (multilingual)',
      description: 'Better accuracy, heavier (~460MB).',
      sizeBytes: 466 * 1024 * 1024, // approximate
      downloadUrl: '$_hfBase/ggml-small.bin',
    ),
  ];

  static SttModelOption? findById(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }
}

