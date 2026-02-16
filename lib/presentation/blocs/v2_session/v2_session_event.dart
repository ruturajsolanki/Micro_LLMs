part of 'v2_session_bloc.dart';

sealed class V2SessionEvent extends Equatable {
  const V2SessionEvent();

  @override
  List<Object?> get props => [];
}

/// Check if cloud is ready (API key + connectivity).
final class V2CloudCheckRequested extends V2SessionEvent {
  const V2CloudCheckRequested();
}

/// Start recording audio.
final class V2RecordingStarted extends V2SessionEvent {
  const V2RecordingStarted();
}

/// Stop recording and begin processing.
final class V2RecordingStopped extends V2SessionEvent {
  const V2RecordingStopped();
}

/// User picked an audio file to upload and process.
final class V2AudioFileSelected extends V2SessionEvent {
  final String filePath;
  final String fileName;

  const V2AudioFileSelected({
    required this.filePath,
    required this.fileName,
  });

  @override
  List<Object?> get props => [filePath, fileName];
}

/// Reset to initial state for a new session.
final class V2SessionReset extends V2SessionEvent {
  const V2SessionReset();
}

/// Update the recording timer tick.
final class V2TimerTicked extends V2SessionEvent {
  final int elapsedSeconds;
  const V2TimerTicked(this.elapsedSeconds);

  @override
  List<Object?> get props => [elapsedSeconds];
}
