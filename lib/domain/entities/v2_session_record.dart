import 'package:equatable/equatable.dart';

/// A persisted record of a completed V2 evaluation session.
///
/// Stores all metadata needed for the history view:
/// date, recording duration, processing time, scores, transcript, etc.
class V2SessionRecord extends Equatable {
  /// Unique identifier (timestamp-based).
  final String id;

  /// When the session was completed.
  final DateTime completedAt;

  /// How long the user recorded (seconds).
  final int recordingDurationSeconds;

  /// Total processing time from stop-recording to results (milliseconds).
  final int processingTimeMs;

  /// Clarity of Thought score (1-10).
  final double clarityScore;

  /// Language Proficiency score (1-10).
  final double languageScore;

  /// Combined total score (out of 20).
  double get totalScore => clarityScore + languageScore;

  /// Clarity reasoning from the evaluator.
  final String clarityReasoning;

  /// Language reasoning from the evaluator.
  final String languageReasoning;

  /// Overall feedback from the evaluator.
  final String overallFeedback;

  /// Whether content was flagged as unsafe.
  final bool safetyFlag;

  /// Safety notes (if flagged).
  final String safetyNotes;

  /// The full transcript from STT.
  final String transcript;

  /// Word count of the transcript.
  int get wordCount =>
      transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// Which cloud LLM provider was used (groq / gemini).
  final String llmProvider;

  /// Which STT provider was used (groq_whisper / local_whisper).
  final String sttProvider;

  /// Source of the audio: 'mic' or 'upload'.
  final String audioSource;

  /// Original filename if audio was uploaded (null for mic recordings).
  final String? uploadedFileName;

  /// Path to the saved audio file on disk (null if file was cleaned up).
  final String? audioFilePath;

  const V2SessionRecord({
    required this.id,
    required this.completedAt,
    required this.recordingDurationSeconds,
    required this.processingTimeMs,
    required this.clarityScore,
    required this.languageScore,
    required this.clarityReasoning,
    required this.languageReasoning,
    required this.overallFeedback,
    required this.safetyFlag,
    required this.safetyNotes,
    required this.transcript,
    required this.llmProvider,
    required this.sttProvider,
    this.audioSource = 'mic',
    this.uploadedFileName,
    this.audioFilePath,
  });

  /// Qualitative label from total score.
  String get totalLabel {
    if (totalScore >= 18) return 'Excellent';
    if (totalScore >= 15) return 'Good';
    if (totalScore >= 12) return 'Above Average';
    if (totalScore >= 9) return 'Average';
    if (totalScore >= 6) return 'Below Average';
    return 'Needs Improvement';
  }

  /// Processing time formatted as seconds.
  String get processingTimeFormatted =>
      '${(processingTimeMs / 1000).toStringAsFixed(1)}s';

  /// Recording duration formatted as mm:ss.
  String get durationFormatted {
    final m = recordingDurationSeconds ~/ 60;
    final s = recordingDurationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Serialize to a Map for Hive storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'completedAt': completedAt.toIso8601String(),
      'recordingDurationSeconds': recordingDurationSeconds,
      'processingTimeMs': processingTimeMs,
      'clarityScore': clarityScore,
      'languageScore': languageScore,
      'clarityReasoning': clarityReasoning,
      'languageReasoning': languageReasoning,
      'overallFeedback': overallFeedback,
      'safetyFlag': safetyFlag,
      'safetyNotes': safetyNotes,
      'transcript': transcript,
      'llmProvider': llmProvider,
      'sttProvider': sttProvider,
      'audioSource': audioSource,
      'uploadedFileName': uploadedFileName,
      'audioFilePath': audioFilePath,
    };
  }

  /// Deserialize from a Hive Map.
  factory V2SessionRecord.fromMap(Map<dynamic, dynamic> map) {
    return V2SessionRecord(
      id: map['id'] as String? ?? '',
      completedAt: DateTime.tryParse(map['completedAt'] as String? ?? '') ??
          DateTime.now(),
      recordingDurationSeconds:
          (map['recordingDurationSeconds'] as num?)?.toInt() ?? 0,
      processingTimeMs: (map['processingTimeMs'] as num?)?.toInt() ?? 0,
      clarityScore: (map['clarityScore'] as num?)?.toDouble() ?? 0,
      languageScore: (map['languageScore'] as num?)?.toDouble() ?? 0,
      clarityReasoning:
          map['clarityReasoning'] as String? ?? '',
      languageReasoning:
          map['languageReasoning'] as String? ?? '',
      overallFeedback: map['overallFeedback'] as String? ?? '',
      safetyFlag: map['safetyFlag'] as bool? ?? false,
      safetyNotes: map['safetyNotes'] as String? ?? '',
      transcript: map['transcript'] as String? ?? '',
      llmProvider: map['llmProvider'] as String? ?? 'groq',
      sttProvider: map['sttProvider'] as String? ?? 'groq_whisper',
      audioSource: map['audioSource'] as String? ?? 'mic',
      uploadedFileName: map['uploadedFileName'] as String?,
      audioFilePath: map['audioFilePath'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        completedAt,
        recordingDurationSeconds,
        processingTimeMs,
        clarityScore,
        languageScore,
        safetyFlag,
        transcript,
        audioSource,
        audioFilePath,
      ];
}
