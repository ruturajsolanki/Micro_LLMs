import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// Records microphone audio to a WAV file on disk for cloud STT upload.
///
/// Uses a platform channel to the native Android AudioRecord API.
/// Also streams raw PCM audio chunks for real-time STT (Deepgram).
class AudioRecorderService {
  static const _channel = MethodChannel('com.microllm.app/audio_recorder');
  static const _eventChannel =
      EventChannel('com.microllm.app/audio_recorder_events');

  StreamSubscription<dynamic>? _eventSub;
  final _rmsController = StreamController<double>.broadcast();
  final _audioChunkController = StreamController<List<int>>.broadcast();

  bool _recording = false;

  bool get isRecording => _recording;

  /// Stream of RMS dB levels during recording (for waveform UI).
  Stream<double> get rmsStream => _rmsController.stream;

  /// Stream of raw PCM audio chunks for live STT streaming.
  Stream<List<int>> get audioChunkStream => _audioChunkController.stream;

  /// Start recording microphone audio to a WAV file.
  ///
  /// Returns immediately. Call [stopRecording] to finalize the file.
  /// The [outputPath] should be a writable absolute path ending in `.wav`.
  Future<void> startRecording({required String outputPath}) async {
    if (_recording) {
      AppLogger.w('AudioRecorderService: already recording, stopping first');
      await stopRecording();
    }

    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final type = event['type'] as String?;
          if (type == 'rms') {
            final rmsDb = (event['rmsDb'] as num?)?.toDouble() ?? -120.0;
            _rmsController.add(rmsDb);
          } else if (type == 'audio') {
            final data = event['data'];
            if (data is Uint8List) {
              _audioChunkController.add(data);
            } else if (data is List) {
              _audioChunkController.add(List<int>.from(data));
            }
          }
        }
      },
      onError: (e) {
        AppLogger.e('AudioRecorderService event error: $e');
      },
    );

    await _channel.invokeMethod<void>('startRecording', {
      'outputPath': outputPath,
    });
    _recording = true;
    AppLogger.i('AudioRecorderService: recording started → $outputPath');
  }

  /// Stop recording and finalize the WAV file.
  ///
  /// Returns the path to the written WAV file (same as [outputPath]).
  Future<String?> stopRecording() async {
    if (!_recording) return null;

    final path = await _channel.invokeMethod<String>('stopRecording');
    _recording = false;
    await _eventSub?.cancel();
    _eventSub = null;
    AppLogger.i('AudioRecorderService: recording stopped → $path');
    return path;
  }

  /// Cancel recording without saving.
  Future<void> cancelRecording() async {
    if (!_recording) return;
    await _channel.invokeMethod<void>('cancelRecording');
    _recording = false;
    await _eventSub?.cancel();
    _eventSub = null;
  }

  void dispose() {
    _eventSub?.cancel();
    _rmsController.close();
    _audioChunkController.close();
  }
}
