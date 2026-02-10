/// Domain-level contract to resolve local STT model paths.
///
/// Keeps the domain layer agnostic of storage and platform details.
abstract class SttModelPathResolver {
  /// Returns the local file path for a Whisper model ID, or null if not present.
  Future<String?> resolveWhisperModelPath(String modelId);

  /// True if the model file is present and looks complete.
  Future<bool> isWhisperModelDownloaded(String modelId);
}

