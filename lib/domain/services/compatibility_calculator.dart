import '../entities/device_specs.dart';
import 'model_catalog.dart';

/// Calculates model compatibility and performance estimates for a device.
/// 
/// Uses benchmarks and heuristics to estimate:
/// - Whether a model will run
/// - Expected tokens per second
/// - Time to first token
/// - Potential issues
class CompatibilityCalculator {
  CompatibilityCalculator._();
  
  /// Assess compatibility of a model with device specs.
  static ModelCompatibility assess(ModelOption model, DeviceSpecs specs) {
    final warnings = <String>[];
    final recommendations = <String>[];
    
    // Check storage
    final hasEnoughStorage = specs.availableStorageBytes >= model.sizeBytes * 1.1;
    if (!hasEnoughStorage) {
      warnings.add('Insufficient storage space');
      recommendations.add('Free up ${((model.sizeBytes * 1.1 - specs.availableStorageBytes) / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB of storage');
    }
    
    // Check RAM
    final hasEnoughRam = specs.totalRamBytes >= model.minRamBytes;
    final hasRecommendedRam = specs.totalRamBytes >= model.recommendedRamBytes;
    
    if (!hasEnoughRam) {
      warnings.add('RAM below minimum requirement');
      recommendations.add('Consider a smaller model like TinyLlama');
    } else if (!hasRecommendedRam) {
      warnings.add('RAM below recommended amount');
      recommendations.add('Close other apps for better performance');
    }
    
    // Check available RAM (not just total)
    final availableRamRatio = specs.availableRamBytes / model.minRamBytes;
    if (availableRamRatio < 1.2 && hasEnoughRam) {
      warnings.add('Low available RAM - close other apps');
    }
    
    // Check architecture
    if (!specs.cpuArchitecture.contains('arm64')) {
      warnings.add('32-bit architecture may have reduced performance');
    }
    
    // Calculate compatibility level
    final level = _calculateCompatibilityLevel(model, specs);
    
    // Estimate performance
    final tokensPerSecond = _estimateTokensPerSecond(model, specs);
    final timeToFirstToken = _estimateTimeToFirstToken(model, specs);
    
    // Add performance recommendations
    if (tokensPerSecond < 4) {
      recommendations.add('Consider using a smaller model for faster responses');
    }
    
    if (specs.cpuCores < 4) {
      recommendations.add('Limited CPU cores may slow inference');
    }
    
    return ModelCompatibility(
      model: model,
      level: level,
      estimatedTokensPerSecond: tokensPerSecond,
      estimatedTimeToFirstTokenMs: timeToFirstToken,
      hasEnoughStorage: hasEnoughStorage,
      hasEnoughRam: hasEnoughRam,
      warnings: warnings,
      recommendations: recommendations,
    );
  }
  
  /// Assess all models in catalog.
  static List<ModelCompatibility> assessAll(DeviceSpecs specs) {
    return ModelCatalog.models
        .map((model) => assess(model, specs))
        .toList()
      ..sort((a, b) {
        // Sort by compatibility level (best first), then by model size
        final levelCompare = a.level.index.compareTo(b.level.index);
        if (levelCompare != 0) return levelCompare;
        return a.model.sizeBytes.compareTo(b.model.sizeBytes);
      });
  }
  
  /// Get recommended model for device.
  static ModelCompatibility? getRecommended(DeviceSpecs specs) {
    final assessments = assessAll(specs);
    
    // Find the best model with at least "good" compatibility
    for (final assessment in assessments) {
      if (assessment.level == CompatibilityLevel.excellent ||
          assessment.level == CompatibilityLevel.good) {
        return assessment;
      }
    }
    
    // Fallback to first fair model
    for (final assessment in assessments) {
      if (assessment.level == CompatibilityLevel.fair) {
        return assessment;
      }
    }
    
    return assessments.isNotEmpty ? assessments.first : null;
  }
  
  /// Calculate compatibility level based on device specs and model requirements.
  static CompatibilityLevel _calculateCompatibilityLevel(
    ModelOption model,
    DeviceSpecs specs,
  ) {
    // Check if incompatible
    if (!specs.cpuArchitecture.contains('arm64') &&
        !specs.cpuArchitecture.contains('x86_64')) {
      return CompatibilityLevel.incompatible;
    }
    
    if (specs.totalRamBytes < model.minRamBytes * 0.8) {
      return CompatibilityLevel.incompatible;
    }
    
    if (specs.availableStorageBytes < model.sizeBytes) {
      return CompatibilityLevel.incompatible;
    }
    
    // Calculate score
    double score = 0;
    
    // RAM score (0-40 points)
    final ramRatio = specs.totalRamBytes / model.recommendedRamBytes;
    if (ramRatio >= 1.5) {
      score += 40;
    } else if (ramRatio >= 1.2) {
      score += 35;
    } else if (ramRatio >= 1.0) {
      score += 28;
    } else if (ramRatio >= 0.8) {
      score += 18;
    } else {
      score += 8;
    }
    
    // CPU score (0-30 points)
    if (specs.cpuCores >= 8) {
      score += 15;
    } else if (specs.cpuCores >= 6) {
      score += 12;
    } else if (specs.cpuCores >= 4) {
      score += 8;
    } else {
      score += 4;
    }
    
    // CPU frequency bonus
    if (specs.cpuMaxFrequencyMHz != null) {
      if (specs.cpuMaxFrequencyMHz! >= 2800) {
        score += 15;
      } else if (specs.cpuMaxFrequencyMHz! >= 2400) {
        score += 12;
      } else if (specs.cpuMaxFrequencyMHz! >= 2000) {
        score += 8;
      } else {
        score += 4;
      }
    } else {
      score += 8; // Assume moderate if unknown
    }
    
    // NEON bonus (0-15 points)
    if (specs.supportsNeon) {
      score += 15;
    }
    
    // NPU bonus (0-15 points)
    if (specs.hasNpu) {
      score += 10; // Future: could be more with NPU support
    }
    
    // Map score to level
    if (score >= 85) return CompatibilityLevel.excellent;
    if (score >= 65) return CompatibilityLevel.good;
    if (score >= 45) return CompatibilityLevel.fair;
    if (score >= 25) return CompatibilityLevel.poor;
    return CompatibilityLevel.incompatible;
  }
  
  /// Estimate tokens per second based on device specs and model size.
  /// 
  /// Based on benchmarks from various devices running llama.cpp:
  /// - Snapdragon 8 Gen 2 with 12GB RAM: ~15-20 t/s for 7B Q4
  /// - Snapdragon 870 with 8GB RAM: ~8-12 t/s for 7B Q4
  /// - Snapdragon 695 with 6GB RAM: ~4-6 t/s for 7B Q4
  static double _estimateTokensPerSecond(ModelOption model, DeviceSpecs specs) {
    // Base estimate from model size (smaller = faster)
    double baseTokensPerSecond;
    
    final paramCount = _parseParameterCount(model.parameters);
    if (paramCount <= 1.5) {
      baseTokensPerSecond = 25.0;
    } else if (paramCount <= 2.5) {
      baseTokensPerSecond = 18.0;
    } else if (paramCount <= 3.5) {
      baseTokensPerSecond = 12.0;
    } else if (paramCount <= 7.5) {
      baseTokensPerSecond = 6.0;
    } else {
      baseTokensPerSecond = 3.0;
    }
    
    // Adjust for device specs
    double multiplier = 1.0;
    
    // RAM adjustment
    final ramRatio = specs.totalRamBytes / model.recommendedRamBytes;
    if (ramRatio >= 1.5) {
      multiplier *= 1.2;
    } else if (ramRatio >= 1.0) {
      multiplier *= 1.0;
    } else if (ramRatio >= 0.8) {
      multiplier *= 0.7;
    } else {
      multiplier *= 0.4;
    }
    
    // CPU adjustment
    if (specs.cpuCores >= 8) {
      multiplier *= 1.3;
    } else if (specs.cpuCores >= 6) {
      multiplier *= 1.15;
    } else if (specs.cpuCores >= 4) {
      multiplier *= 1.0;
    } else {
      multiplier *= 0.7;
    }
    
    // Frequency adjustment
    if (specs.cpuMaxFrequencyMHz != null) {
      if (specs.cpuMaxFrequencyMHz! >= 2800) {
        multiplier *= 1.3;
      } else if (specs.cpuMaxFrequencyMHz! >= 2400) {
        multiplier *= 1.15;
      } else if (specs.cpuMaxFrequencyMHz! >= 2000) {
        multiplier *= 1.0;
      } else {
        multiplier *= 0.8;
      }
    }
    
    // NEON boost
    if (specs.supportsNeon) {
      multiplier *= 1.4;
    }
    
    return (baseTokensPerSecond * multiplier).clamp(0.5, 50.0);
  }
  
  /// Estimate time to first token (prompt processing time).
  static int _estimateTimeToFirstToken(ModelOption model, DeviceSpecs specs) {
    // Base estimate in milliseconds
    final paramCount = _parseParameterCount(model.parameters);
    int baseTime;
    
    if (paramCount <= 1.5) {
      baseTime = 200;
    } else if (paramCount <= 2.5) {
      baseTime = 400;
    } else if (paramCount <= 3.5) {
      baseTime = 600;
    } else if (paramCount <= 7.5) {
      baseTime = 1200;
    } else {
      baseTime = 2000;
    }
    
    // Adjust for device performance
    double multiplier = 1.0;
    
    if (specs.cpuCores >= 8 && (specs.cpuMaxFrequencyMHz ?? 0) >= 2400) {
      multiplier = 0.6;
    } else if (specs.cpuCores >= 6) {
      multiplier = 0.8;
    } else if (specs.cpuCores < 4) {
      multiplier = 1.5;
    }
    
    if (!specs.supportsNeon) {
      multiplier *= 2.0;
    }
    
    return (baseTime * multiplier).round();
  }
  
  /// Parse parameter count from string like "2.7B" or "7B".
  static double _parseParameterCount(String params) {
    final cleaned = params.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 3.0;
  }
}
