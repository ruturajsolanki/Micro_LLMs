import 'package:flutter_test/flutter_test.dart';

import 'package:micro_llm_app/domain/entities/device_specs.dart';

void main() {
  group('DeviceSpecs', () {
    late DeviceSpecs specs;

    setUp(() {
      specs = DeviceSpecs(
        totalRamBytes: 8 * 1024 * 1024 * 1024, // 8 GB
        availableRamBytes: 4 * 1024 * 1024 * 1024, // 4 GB
        availableStorageBytes: 50 * 1024 * 1024 * 1024, // 50 GB
        cpuCores: 8,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Test Device',
        sdkVersion: 33,
        supportsNeon: true,
        hasNpu: true,
        cpuMaxFrequencyMHz: 2800,
        socName: 'Snapdragon 8 Gen 2',
      );
    });

    test('calculates totalRamGB correctly', () {
      expect(specs.totalRamGB, closeTo(8.0, 0.1));
    });

    test('calculates availableRamGB correctly', () {
      expect(specs.availableRamGB, closeTo(4.0, 0.1));
    });

    test('calculates ramUsagePercent correctly', () {
      // 4GB used out of 8GB = 50%
      expect(specs.ramUsagePercent, closeTo(50.0, 0.1));
    });

    test('formats RAM correctly', () {
      expect(specs.ramFormatted, contains('8'));
      expect(specs.ramFormatted, contains('GB'));
    });

    test('formats available RAM correctly', () {
      expect(specs.availableRamFormatted, contains('4'));
      expect(specs.availableRamFormatted, contains('GB'));
    });

    test('formats storage correctly', () {
      expect(specs.storageFormatted, contains('50'));
      expect(specs.storageFormatted, contains('GB'));
    });

    test('meetsMinimumRequirements returns true for capable device', () {
      expect(specs.meetsMinimumRequirements, true);
    });

    test('meetsMinimumRequirements returns false for weak device', () {
      final weakDevice = DeviceSpecs(
        totalRamBytes: 1 * 1024 * 1024 * 1024, // 1 GB
        availableRamBytes: 512 * 1024 * 1024,
        availableStorageBytes: 1 * 1024 * 1024 * 1024,
        cpuCores: 2,
        cpuArchitecture: 'armeabi-v7a',
        deviceModel: 'Weak Device',
        sdkVersion: 28,
        supportsNeon: false,
      );

      expect(weakDevice.meetsMinimumRequirements, false);
    });

    test('calculates performance tier correctly for high-end device', () {
      expect(specs.performanceTier, greaterThanOrEqualTo(4));
    });

    test('calculates performance tier correctly for low-end device', () {
      final lowEndDevice = DeviceSpecs(
        totalRamBytes: 2 * 1024 * 1024 * 1024, // 2 GB
        availableRamBytes: 1 * 1024 * 1024 * 1024,
        availableStorageBytes: 5 * 1024 * 1024 * 1024,
        cpuCores: 4,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Budget Phone',
        sdkVersion: 29,
        supportsNeon: true,
      );

      expect(lowEndDevice.performanceTier, lessThanOrEqualTo(2));
    });

    test('performanceTierName returns non-empty string', () {
      expect(specs.performanceTierName, isNotEmpty);
    });

    test('copyWith preserves unchanged values', () {
      final copied = specs.copyWith(cpuCores: 12);
      
      expect(copied.cpuCores, 12);
      expect(copied.totalRamBytes, specs.totalRamBytes);
      expect(copied.deviceModel, specs.deviceModel);
      expect(copied.supportsNeon, specs.supportsNeon);
    });

    test('copyWith updates specified values', () {
      final copied = specs.copyWith(
        availableRamBytes: 6 * 1024 * 1024 * 1024,
        hasNpu: false,
      );

      expect(copied.availableRamBytes, 6 * 1024 * 1024 * 1024);
      expect(copied.hasNpu, false);
    });
  });

  group('ModelCompatibility', () {
    test('creates valid compatibility assessment', () {
      final model = ModelOption(
        id: 'test-model',
        name: 'Test Model',
        description: 'A test model',
        parameters: '1B',
        quantization: 'Q4_K_M',
        sizeBytes: 500 * 1024 * 1024,
        minRamBytes: 2 * 1024 * 1024 * 1024,
        recommendedRamBytes: 3 * 1024 * 1024 * 1024,
        contextSize: 2048,
        downloadUrl: 'https://example.com/model.gguf',
        sha256: '',
        supportedLanguages: ['en'],
        strengths: ['Fast'],
      );

      final compatibility = ModelCompatibility(
        model: model,
        level: CompatibilityLevel.good,
        estimatedTokensPerSecond: 15.0,
        estimatedTimeToFirstTokenMs: 500,
        hasEnoughRam: true,
        hasEnoughStorage: true,
        warnings: [],
      );

      expect(compatibility.model, model);
      expect(compatibility.level, CompatibilityLevel.good);
      expect(compatibility.estimatedTokensPerSecond, 15.0);
      expect(compatibility.hasEnoughRam, true);
    });
  });

  group('CompatibilityLevel', () {
    test('levels are ordered from best to worst', () {
      expect(CompatibilityLevel.excellent.index, lessThan(CompatibilityLevel.good.index));
      expect(CompatibilityLevel.good.index, lessThan(CompatibilityLevel.fair.index));
      expect(CompatibilityLevel.fair.index, lessThan(CompatibilityLevel.poor.index));
      expect(CompatibilityLevel.poor.index, lessThan(CompatibilityLevel.incompatible.index));
    });
  });
}
