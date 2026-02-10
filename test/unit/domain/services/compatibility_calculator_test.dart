import 'package:flutter_test/flutter_test.dart';

import 'package:micro_llm_app/domain/services/compatibility_calculator.dart';
import 'package:micro_llm_app/domain/services/model_catalog.dart';
import 'package:micro_llm_app/domain/entities/device_specs.dart';

void main() {
  group('CompatibilityCalculator', () {
    late DeviceSpecs lowEndDevice;
    late DeviceSpecs midRangeDevice;
    late DeviceSpecs highEndDevice;

    setUp(() {
      lowEndDevice = DeviceSpecs(
        totalRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
        availableRamBytes: 1 * 1024 * 1024 * 1024,
        availableStorageBytes: 5 * 1024 * 1024 * 1024,
        cpuCores: 4,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Low End',
        sdkVersion: 29,
        supportsNeon: true,
      );

      midRangeDevice = DeviceSpecs(
        totalRamBytes: 6 * 1024 * 1024 * 1024, // 6 GB
        availableRamBytes: 3 * 1024 * 1024 * 1024,
        availableStorageBytes: 20 * 1024 * 1024 * 1024,
        cpuCores: 8,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Mid Range',
        sdkVersion: 31,
        supportsNeon: true,
        cpuMaxFrequencyMHz: 2800,
      );

      highEndDevice = DeviceSpecs(
        totalRamBytes: 12 * 1024 * 1024 * 1024, // 12 GB
        availableRamBytes: 8 * 1024 * 1024 * 1024,
        availableStorageBytes: 100 * 1024 * 1024 * 1024,
        cpuCores: 8,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Flagship',
        sdkVersion: 34,
        supportsNeon: true,
        hasNpu: true,
        cpuMaxFrequencyMHz: 3200,
      );
    });

    test('assessAll returns assessments for all models', () {
      final assessments = CompatibilityCalculator.assessAll(midRangeDevice);
      expect(assessments.length, equals(ModelCatalog.models.length));
    });

    test('assessments are sorted by compatibility level', () {
      final assessments = CompatibilityCalculator.assessAll(midRangeDevice);
      
      // Best compatibility should come first
      for (int i = 0; i < assessments.length - 1; i++) {
        expect(
          assessments[i].level.index,
          lessThanOrEqualTo(assessments[i + 1].level.index),
        );
      }
    });

    test('low-end device gets correct compatibility levels', () {
      final assessments = CompatibilityCalculator.assessAll(lowEndDevice);
      
      // Small models should be compatible
      final smallModelAssessment = assessments.firstWhere(
        (a) => a.model.id == 'tinyllama-1.1b-q4',
      );
      expect(
        smallModelAssessment.level,
        anyOf(CompatibilityLevel.excellent, CompatibilityLevel.good, CompatibilityLevel.fair),
      );
      
      // Large models should be incompatible or poor
      final largeModelAssessment = assessments.firstWhere(
        (a) => a.model.id == 'mistral-7b-q4',
      );
      expect(
        largeModelAssessment.level,
        anyOf(CompatibilityLevel.poor, CompatibilityLevel.incompatible),
      );
    });

    test('high-end device can run all models', () {
      final assessments = CompatibilityCalculator.assessAll(highEndDevice);
      
      for (final assessment in assessments) {
        expect(
          assessment.level,
          isNot(CompatibilityLevel.incompatible),
          reason: '${assessment.model.name} should be compatible on high-end device',
        );
      }
    });

    test('getRecommended returns a runnable model', () {
      final recommended = CompatibilityCalculator.getRecommended(midRangeDevice);
      
      expect(recommended, isNotNull);
      expect(recommended!.level, isNot(CompatibilityLevel.incompatible));
      expect(recommended.level, isNot(CompatibilityLevel.poor));
    });

    test('assessments include performance estimates', () {
      final assessments = CompatibilityCalculator.assessAll(midRangeDevice);
      
      for (final assessment in assessments) {
        if (assessment.level != CompatibilityLevel.incompatible) {
          expect(assessment.estimatedTokensPerSecond, greaterThan(0));
          expect(assessment.estimatedTimeToFirstTokenMs, greaterThan(0));
          expect(assessment.performanceEstimate, isNotEmpty);
        }
      }
    });

    test('assessments include RAM warnings when appropriate', () {
      final assessments = CompatibilityCalculator.assessAll(lowEndDevice);
      
      // Find a model that needs more RAM than available
      final tightModel = assessments.firstWhere(
        (a) => a.model.recommendedRamBytes > lowEndDevice.availableRamBytes &&
               a.model.minRamBytes <= lowEndDevice.totalRamBytes,
        orElse: () => assessments.first,
      );
      
      if (tightModel.model.recommendedRamBytes > lowEndDevice.availableRamBytes) {
        expect(tightModel.warnings, isNotEmpty);
      }
    });
  });

  group('CompatibilityLevel', () {
    test('has correct display names', () {
      expect(CompatibilityLevel.excellent.displayName, isNotEmpty);
      expect(CompatibilityLevel.good.displayName, isNotEmpty);
      expect(CompatibilityLevel.fair.displayName, isNotEmpty);
      expect(CompatibilityLevel.poor.displayName, isNotEmpty);
      expect(CompatibilityLevel.incompatible.displayName, isNotEmpty);
    });

    test('has emojis for visual feedback', () {
      expect(CompatibilityLevel.excellent.emoji, isNotEmpty);
      expect(CompatibilityLevel.incompatible.emoji, isNotEmpty);
    });
  });
}
