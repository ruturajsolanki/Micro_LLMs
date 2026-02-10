import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../entities/device_specs.dart';

/// Runs synthetic benchmarks to estimate device performance.
/// 
/// These benchmarks simulate the types of operations performed during
/// LLM inference without requiring an actual model.
class DeviceBenchmark {
  DeviceBenchmark._();
  
  /// Run all benchmarks and return results.
  static Future<BenchmarkResults> runAll({
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Starting benchmarks...', 0.0);
    
    // Allow UI to update
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Run CPU benchmark
    onProgress?.call('Testing CPU performance...', 0.1);
    final cpuScore = await _runCpuBenchmark();
    
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Run memory bandwidth benchmark
    onProgress?.call('Testing memory bandwidth...', 0.4);
    final memoryScore = await _runMemoryBenchmark();
    
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Run SIMD simulation
    onProgress?.call('Testing SIMD operations...', 0.7);
    final simdScore = await _runSimdBenchmark();
    
    onProgress?.call('Calculating results...', 0.95);
    
    // Calculate overall score
    final overallScore = (cpuScore * 0.4 + memoryScore * 0.3 + simdScore * 0.3).round();
    
    // Estimate tokens per second based on benchmark
    final estimatedTps = _estimateTokensPerSecond(overallScore);
    
    onProgress?.call('Complete', 1.0);
    
    return BenchmarkResults(
      cpuScore: cpuScore,
      memoryScore: memoryScore,
      simdScore: simdScore,
      overallScore: overallScore,
      estimatedTokensPerSecond: estimatedTps,
      performanceTier: _getPerformanceTier(overallScore),
    );
  }
  
  /// CPU benchmark: matrix multiplication simulation.
  /// This simulates the attention computation in transformers.
  static Future<int> _runCpuBenchmark() async {
    final stopwatch = Stopwatch()..start();
    
    const size = 256;
    final random = Random(42);
    
    // Create matrices
    final a = List.generate(size, (_) => 
        List.generate(size, (_) => random.nextDouble()));
    final b = List.generate(size, (_) => 
        List.generate(size, (_) => random.nextDouble()));
    final c = List.generate(size, (_) => 
        List.filled(size, 0.0));
    
    // Perform matrix multiplication
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        double sum = 0;
        for (int k = 0; k < size; k++) {
          sum += a[i][k] * b[k][j];
        }
        c[i][j] = sum;
      }
    }
    
    stopwatch.stop();
    
    // Score based on time (faster = higher score)
    // Baseline: 1000ms = score 100, scale inversely
    final timeMs = stopwatch.elapsedMilliseconds;
    final score = (100000 / (timeMs + 1)).clamp(10, 1000).round();
    
    return score;
  }
  
  /// Memory bandwidth benchmark: large array operations.
  /// Simulates the memory access patterns during inference.
  static Future<int> _runMemoryBenchmark() async {
    final stopwatch = Stopwatch()..start();
    
    // Allocate large buffer (16MB)
    const bufferSize = 16 * 1024 * 1024;
    final buffer = Float32List(bufferSize ~/ 4);
    
    // Write pattern
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = i.toDouble();
    }
    
    // Read and accumulate (prevents optimization)
    double sum = 0;
    for (int i = 0; i < buffer.length; i++) {
      sum += buffer[i];
    }
    
    // Random access pattern (cache unfriendly)
    final random = Random(42);
    for (int i = 0; i < 100000; i++) {
      final idx = random.nextInt(buffer.length);
      sum += buffer[idx];
    }
    
    stopwatch.stop();
    
    // Prevent optimization
    if (sum == double.negativeInfinity) print(sum);
    
    // Score based on bandwidth
    final timeMs = stopwatch.elapsedMilliseconds;
    final bandwidthMBps = (bufferSize * 2) / (timeMs * 1000); // MB/s
    final score = (bandwidthMBps * 10).clamp(10, 1000).round();
    
    return score;
  }
  
  /// SIMD simulation benchmark.
  /// Simulates vectorized operations used in quantized inference.
  static Future<int> _runSimdBenchmark() async {
    final stopwatch = Stopwatch()..start();
    
    const iterations = 1000000;
    const vectorSize = 8;
    
    final a = Float32List(vectorSize);
    final b = Float32List(vectorSize);
    final c = Float32List(vectorSize);
    
    // Initialize
    for (int i = 0; i < vectorSize; i++) {
      a[i] = i.toDouble();
      b[i] = (vectorSize - i).toDouble();
    }
    
    // Simulate SIMD operations
    for (int iter = 0; iter < iterations; iter++) {
      // Vector add
      for (int i = 0; i < vectorSize; i++) {
        c[i] = a[i] + b[i];
      }
      
      // Vector multiply
      for (int i = 0; i < vectorSize; i++) {
        c[i] = a[i] * b[i];
      }
      
      // Fused multiply-add (common in neural nets)
      for (int i = 0; i < vectorSize; i++) {
        c[i] = a[i] * b[i] + c[i];
      }
    }
    
    stopwatch.stop();
    
    // Prevent optimization
    double sum = 0;
    for (int i = 0; i < vectorSize; i++) {
      sum += c[i];
    }
    if (sum == double.negativeInfinity) print(sum);
    
    // Score based on operations per second
    final timeMs = stopwatch.elapsedMilliseconds;
    final opsPerSecond = (iterations * vectorSize * 3) / (timeMs / 1000);
    final score = (opsPerSecond / 100000).clamp(10, 1000).round();
    
    return score;
  }
  
  /// Estimate tokens per second from benchmark score.
  static double _estimateTokensPerSecond(int overallScore) {
    // Empirical correlation from device testing:
    // Score 100 ≈ 2 t/s (low-end)
    // Score 300 ≈ 8 t/s (mid-range)
    // Score 500 ≈ 15 t/s (high-end)
    // Score 800+ ≈ 25+ t/s (flagship)
    
    if (overallScore >= 800) {
      return 25 + (overallScore - 800) * 0.02;
    } else if (overallScore >= 500) {
      return 15 + (overallScore - 500) * 0.033;
    } else if (overallScore >= 300) {
      return 8 + (overallScore - 300) * 0.035;
    } else if (overallScore >= 100) {
      return 2 + (overallScore - 100) * 0.03;
    } else {
      return 1 + overallScore * 0.01;
    }
  }
  
  /// Get performance tier from score.
  static PerformanceTier _getPerformanceTier(int score) {
    if (score >= 700) return PerformanceTier.flagship;
    if (score >= 450) return PerformanceTier.highEnd;
    if (score >= 250) return PerformanceTier.midRange;
    if (score >= 120) return PerformanceTier.entryLevel;
    return PerformanceTier.basic;
  }
}

/// Results from device benchmarks.
class BenchmarkResults {
  /// CPU computation score.
  final int cpuScore;
  
  /// Memory bandwidth score.
  final int memoryScore;
  
  /// SIMD operations score.
  final int simdScore;
  
  /// Overall combined score.
  final int overallScore;
  
  /// Estimated tokens per second for 2.7B Q4 model.
  final double estimatedTokensPerSecond;
  
  /// Performance tier classification.
  final PerformanceTier performanceTier;
  
  const BenchmarkResults({
    required this.cpuScore,
    required this.memoryScore,
    required this.simdScore,
    required this.overallScore,
    required this.estimatedTokensPerSecond,
    required this.performanceTier,
  });
  
  /// Get score breakdown as percentage of max.
  Map<String, double> get scoreBreakdown => {
    'CPU': (cpuScore / 1000 * 100).clamp(0, 100),
    'Memory': (memoryScore / 1000 * 100).clamp(0, 100),
    'SIMD': (simdScore / 1000 * 100).clamp(0, 100),
  };
}

/// Performance tier classification.
enum PerformanceTier {
  flagship,
  highEnd,
  midRange,
  entryLevel,
  basic,
}

extension PerformanceTierExtension on PerformanceTier {
  String get displayName {
    switch (this) {
      case PerformanceTier.flagship: return 'Flagship';
      case PerformanceTier.highEnd: return 'High-End';
      case PerformanceTier.midRange: return 'Mid-Range';
      case PerformanceTier.entryLevel: return 'Entry-Level';
      case PerformanceTier.basic: return 'Basic';
    }
  }
  
  String get description {
    switch (this) {
      case PerformanceTier.flagship:
        return 'Excellent performance with all models';
      case PerformanceTier.highEnd:
        return 'Great performance with most models';
      case PerformanceTier.midRange:
        return 'Good performance with medium models';
      case PerformanceTier.entryLevel:
        return 'Suitable for smaller models';
      case PerformanceTier.basic:
        return 'Limited to smallest models';
    }
  }
  
  List<String> get recommendedModels {
    switch (this) {
      case PerformanceTier.flagship:
        return ['Mistral 7B', 'StableLM 3B', 'Phi-2 2.7B', 'Gemma 2B'];
      case PerformanceTier.highEnd:
        return ['StableLM 3B', 'Phi-2 2.7B', 'Gemma 2B', 'Qwen 1.8B'];
      case PerformanceTier.midRange:
        return ['Phi-2 2.7B', 'Gemma 2B', 'Qwen 1.8B', 'TinyLlama 1.1B'];
      case PerformanceTier.entryLevel:
        return ['Qwen 1.8B', 'TinyLlama 1.1B'];
      case PerformanceTier.basic:
        return ['TinyLlama 1.1B'];
    }
  }
}
