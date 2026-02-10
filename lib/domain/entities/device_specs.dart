import 'package:equatable/equatable.dart';

/// Device hardware specifications.
/// 
/// Captures all relevant hardware info for model compatibility assessment.
class DeviceSpecs extends Equatable {
  /// Total RAM in bytes.
  final int totalRamBytes;
  
  /// Available RAM in bytes.
  final int availableRamBytes;
  
  /// Number of CPU cores.
  final int cpuCores;
  
  /// CPU architecture (e.g., "arm64-v8a").
  final String cpuArchitecture;
  
  /// CPU max frequency in MHz (if available).
  final int? cpuMaxFrequencyMHz;
  
  /// Whether device supports NEON SIMD.
  final bool supportsNeon;
  
  /// Whether device has dedicated NPU/TPU.
  final bool hasNpu;
  
  /// GPU name (if available).
  final String? gpuName;
  
  /// Available storage in bytes.
  final int availableStorageBytes;
  
  /// Device model name.
  final String deviceModel;
  
  /// Android SDK version.
  final int sdkVersion;
  
  /// SOC (System on Chip) name if available.
  final String? socName;
  
  const DeviceSpecs({
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.cpuCores,
    required this.cpuArchitecture,
    this.cpuMaxFrequencyMHz,
    required this.supportsNeon,
    this.hasNpu = false,
    this.gpuName,
    required this.availableStorageBytes,
    required this.deviceModel,
    required this.sdkVersion,
    this.socName,
  });

  DeviceSpecs copyWith({
    int? totalRamBytes,
    int? availableRamBytes,
    int? cpuCores,
    String? cpuArchitecture,
    int? cpuMaxFrequencyMHz,
    bool? supportsNeon,
    bool? hasNpu,
    String? gpuName,
    int? availableStorageBytes,
    String? deviceModel,
    int? sdkVersion,
    String? socName,
  }) {
    return DeviceSpecs(
      totalRamBytes: totalRamBytes ?? this.totalRamBytes,
      availableRamBytes: availableRamBytes ?? this.availableRamBytes,
      cpuCores: cpuCores ?? this.cpuCores,
      cpuArchitecture: cpuArchitecture ?? this.cpuArchitecture,
      cpuMaxFrequencyMHz: cpuMaxFrequencyMHz ?? this.cpuMaxFrequencyMHz,
      supportsNeon: supportsNeon ?? this.supportsNeon,
      hasNpu: hasNpu ?? this.hasNpu,
      gpuName: gpuName ?? this.gpuName,
      availableStorageBytes: availableStorageBytes ?? this.availableStorageBytes,
      deviceModel: deviceModel ?? this.deviceModel,
      sdkVersion: sdkVersion ?? this.sdkVersion,
      socName: socName ?? this.socName,
    );
  }
  
  /// Total RAM in GB.
  double get totalRamGB => totalRamBytes / (1024 * 1024 * 1024);
  
  /// Available RAM in GB.
  double get availableRamGB => availableRamBytes / (1024 * 1024 * 1024);
  
  /// Available storage in GB.
  double get availableStorageGB => availableStorageBytes / (1024 * 1024 * 1024);
  
  /// RAM usage percentage.
  double get ramUsagePercent => 
      (totalRamBytes - availableRamBytes) / totalRamBytes * 100;
  
  /// Human-readable RAM string.
  String get ramFormatted => '${totalRamGB.toStringAsFixed(1)} GB';
  
  /// Human-readable available RAM.
  String get availableRamFormatted => '${availableRamGB.toStringAsFixed(1)} GB';
  
  /// Human-readable storage.
  String get storageFormatted => '${availableStorageGB.toStringAsFixed(1)} GB';
  
  /// Check if device meets minimum requirements for any LLM.
  bool get meetsMinimumRequirements {
    return totalRamBytes >= 3 * 1024 * 1024 * 1024 && // 3GB RAM
           cpuArchitecture.contains('arm64') &&
           availableStorageBytes >= 2 * 1024 * 1024 * 1024; // 2GB storage
  }
  
  /// Estimated performance tier (1-5, 5 being best).
  int get performanceTier {
    int score = 0;
    
    // RAM scoring
    if (totalRamGB >= 12) score += 2;
    else if (totalRamGB >= 8) score += 1;
    
    // CPU cores scoring
    if (cpuCores >= 8) score += 1;
    
    // CPU frequency scoring
    if (cpuMaxFrequencyMHz != null && cpuMaxFrequencyMHz! >= 2800) score += 1;
    
    // Architecture bonus
    if (supportsNeon) score += 1;
    
    return (score + 1).clamp(1, 5);
  }
  
  /// Get tier name.
  String get performanceTierName {
    switch (performanceTier) {
      case 5: return 'Flagship';
      case 4: return 'High-End';
      case 3: return 'Mid-Range';
      case 2: return 'Entry-Level';
      default: return 'Basic';
    }
  }
  
  @override
  List<Object?> get props => [
    totalRamBytes,
    availableRamBytes,
    cpuCores,
    cpuArchitecture,
    cpuMaxFrequencyMHz,
    supportsNeon,
    hasNpu,
    gpuName,
    availableStorageBytes,
    deviceModel,
    sdkVersion,
    socName,
  ];
}

/// Information about an available LLM model.
class ModelOption extends Equatable {
  /// Unique identifier.
  final String id;
  
  /// Display name.
  final String name;
  
  /// Model description.
  final String description;
  
  /// Parameter count (e.g., "2.7B").
  final String parameters;
  
  /// Quantization type (e.g., "Q4_K_M").
  final String quantization;
  
  /// File size in bytes.
  final int sizeBytes;
  
  /// Minimum RAM required in bytes.
  final int minRamBytes;
  
  /// Recommended RAM in bytes.
  final int recommendedRamBytes;
  
  /// Context window size.
  final int contextSize;
  
  /// Download URL.
  final String downloadUrl;
  
  /// SHA256 hash for verification.
  final String sha256;
  
  /// Supported languages.
  final List<String> supportedLanguages;
  
  /// Model strengths.
  final List<String> strengths;
  
  /// Whether this model is recommended for the device.
  final bool isRecommended;
  
  const ModelOption({
    required this.id,
    required this.name,
    required this.description,
    required this.parameters,
    required this.quantization,
    required this.sizeBytes,
    required this.minRamBytes,
    required this.recommendedRamBytes,
    required this.contextSize,
    required this.downloadUrl,
    required this.sha256,
    this.supportedLanguages = const ['en'],
    this.strengths = const [],
    this.isRecommended = false,
  });
  
  /// File size in GB.
  double get sizeGB => sizeBytes / (1024 * 1024 * 1024);
  
  /// Min RAM in GB.
  double get minRamGB => minRamBytes / (1024 * 1024 * 1024);
  
  /// Recommended RAM in GB.
  double get recommendedRamGB => recommendedRamBytes / (1024 * 1024 * 1024);
  
  /// Human-readable size.
  String get sizeFormatted => '${sizeGB.toStringAsFixed(1)} GB';
  
  /// Human-readable min RAM.
  String get minRamFormatted => '${minRamGB.toStringAsFixed(1)} GB';
  
  /// Create copy with isRecommended flag.
  ModelOption copyWithRecommended(bool recommended) {
    return ModelOption(
      id: id,
      name: name,
      description: description,
      parameters: parameters,
      quantization: quantization,
      sizeBytes: sizeBytes,
      minRamBytes: minRamBytes,
      recommendedRamBytes: recommendedRamBytes,
      contextSize: contextSize,
      downloadUrl: downloadUrl,
      sha256: sha256,
      supportedLanguages: supportedLanguages,
      strengths: strengths,
      isRecommended: recommended,
    );
  }
  
  @override
  List<Object?> get props => [id, name, parameters, quantization, sizeBytes];
}

/// Model compatibility assessment result.
class ModelCompatibility extends Equatable {
  /// The model being assessed.
  final ModelOption model;
  
  /// Compatibility level.
  final CompatibilityLevel level;
  
  /// Estimated tokens per second.
  final double estimatedTokensPerSecond;
  
  /// Estimated time to first token in milliseconds.
  final int estimatedTimeToFirstTokenMs;
  
  /// Whether there's enough storage.
  final bool hasEnoughStorage;
  
  /// Whether there's enough RAM.
  final bool hasEnoughRam;
  
  /// Warnings for the user.
  final List<String> warnings;
  
  /// Recommendations.
  final List<String> recommendations;
  
  const ModelCompatibility({
    required this.model,
    required this.level,
    required this.estimatedTokensPerSecond,
    required this.estimatedTimeToFirstTokenMs,
    required this.hasEnoughStorage,
    required this.hasEnoughRam,
    this.warnings = const [],
    this.recommendations = const [],
  });
  
  /// Overall score (0-100).
  int get score {
    switch (level) {
      case CompatibilityLevel.excellent: return 90;
      case CompatibilityLevel.good: return 75;
      case CompatibilityLevel.fair: return 55;
      case CompatibilityLevel.poor: return 35;
      case CompatibilityLevel.incompatible: return 0;
    }
  }
  
  /// Human-readable performance estimate.
  String get performanceEstimate {
    if (estimatedTokensPerSecond >= 15) return 'Fast';
    if (estimatedTokensPerSecond >= 8) return 'Good';
    if (estimatedTokensPerSecond >= 4) return 'Moderate';
    if (estimatedTokensPerSecond >= 2) return 'Slow';
    return 'Very Slow';
  }
  
  @override
  List<Object?> get props => [model, level, estimatedTokensPerSecond];
}

/// Compatibility level enum.
enum CompatibilityLevel {
  /// Model runs excellently on this device.
  excellent,
  
  /// Model runs well on this device.
  good,
  
  /// Model runs but with some limitations.
  fair,
  
  /// Model runs poorly, not recommended.
  poor,
  
  /// Model cannot run on this device.
  incompatible,
}

extension CompatibilityLevelExtension on CompatibilityLevel {
  String get displayName {
    switch (this) {
      case CompatibilityLevel.excellent: return 'Excellent';
      case CompatibilityLevel.good: return 'Good';
      case CompatibilityLevel.fair: return 'Fair';
      case CompatibilityLevel.poor: return 'Poor';
      case CompatibilityLevel.incompatible: return 'Not Compatible';
    }
  }
  
  String get emoji {
    switch (this) {
      case CompatibilityLevel.excellent: return '🟢';
      case CompatibilityLevel.good: return '🟡';
      case CompatibilityLevel.fair: return '🟠';
      case CompatibilityLevel.poor: return '🔴';
      case CompatibilityLevel.incompatible: return '⛔';
    }
  }
}
