import 'package:flutter_test/flutter_test.dart';

import 'package:micro_llm_app/domain/services/model_catalog.dart';
import 'package:micro_llm_app/domain/entities/device_specs.dart';

void main() {
  group('ModelCatalog', () {
    test('contains valid models', () {
      expect(ModelCatalog.models.isNotEmpty, true);
      expect(ModelCatalog.models.length, greaterThanOrEqualTo(5));
    });

    test('all models have required fields', () {
      for (final model in ModelCatalog.models) {
        expect(model.id, isNotEmpty);
        expect(model.name, isNotEmpty);
        expect(model.description, isNotEmpty);
        expect(model.parameters, isNotEmpty);
        expect(model.quantization, isNotEmpty);
        expect(model.sizeBytes, greaterThan(0));
        expect(model.minRamBytes, greaterThan(0));
        expect(model.recommendedRamBytes, greaterThanOrEqualTo(model.minRamBytes));
        expect(model.contextSize, greaterThan(0));
        expect(model.downloadUrl, startsWith('https://'));
        expect(model.supportedLanguages, isNotEmpty);
      }
    });

    test('models are sorted by size (smallest first)', () {
      int prevSize = 0;
      for (final model in ModelCatalog.models) {
        expect(model.sizeBytes, greaterThanOrEqualTo(prevSize));
        prevSize = model.sizeBytes;
      }
    });

    test('findById returns correct model', () {
      final model = ModelCatalog.findById('tinyllama-1.1b-q4');
      expect(model, isNotNull);
      expect(model!.name, contains('TinyLlama'));
    });

    test('findById returns null for invalid id', () {
      final model = ModelCatalog.findById('invalid-model-id');
      expect(model, isNull);
    });

    test('getBestModelForDevice returns appropriate model for low-end device', () {
      final lowEndSpecs = DeviceSpecs(
        totalRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
        availableRamBytes: 2 * 1024 * 1024 * 1024,
        availableStorageBytes: 10 * 1024 * 1024 * 1024, // 10 GB storage
        cpuCores: 4,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Test Device',
        sdkVersion: 29,
        supportsNeon: true,
      );

      final model = ModelCatalog.getBestModelForDevice(lowEndSpecs);
      expect(model, isNotNull);
      // Should recommend a smaller model
      expect(model!.sizeBytes, lessThan(2 * 1024 * 1024 * 1024)); // Less than 2GB
    });

    test('getBestModelForDevice returns larger model for high-end device', () {
      final highEndSpecs = DeviceSpecs(
        totalRamBytes: 12 * 1024 * 1024 * 1024, // 12 GB
        availableRamBytes: 8 * 1024 * 1024 * 1024,
        availableStorageBytes: 100 * 1024 * 1024 * 1024, // 100 GB storage
        cpuCores: 8,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Flagship Device',
        sdkVersion: 33,
        supportsNeon: true,
        hasNpu: true,
      );

      final model = ModelCatalog.getBestModelForDevice(highEndSpecs);
      expect(model, isNotNull);
      // Should recommend a larger model (Mistral 7B or similar)
      expect(model!.parameters, contains('7B'));
    });

    test('getRunnableModels returns correct models for device', () {
      final specs = DeviceSpecs(
        totalRamBytes: 4 * 1024 * 1024 * 1024, // 4 GB
        availableRamBytes: 2 * 1024 * 1024 * 1024,
        availableStorageBytes: 20 * 1024 * 1024 * 1024,
        cpuCores: 8,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Test',
        sdkVersion: 30,
        supportsNeon: true,
      );

      final runnableModels = ModelCatalog.getRunnableModels(specs);
      expect(runnableModels, isNotEmpty);
      
      // All returned models should fit in device RAM
      for (final model in runnableModels) {
        expect(model.minRamBytes, lessThanOrEqualTo(specs.totalRamBytes));
      }
    });

    test('each model has unique id', () {
      final ids = ModelCatalog.models.map((m) => m.id).toSet();
      expect(ids.length, equals(ModelCatalog.models.length));
    });

    test('download URLs are valid GGUF links', () {
      for (final model in ModelCatalog.models) {
        expect(model.downloadUrl, contains('.gguf'));
        expect(model.downloadUrl, contains('huggingface.co'));
      }
    });
  });

  group('ModelOption', () {
    test('sizeFormatted returns human-readable size', () {
      final model = ModelCatalog.models.first;
      expect(model.sizeFormatted, matches(RegExp(r'\d+(\.\d+)?\s*(MB|GB)')));
    });

    test('minRamFormatted returns human-readable RAM', () {
      final model = ModelCatalog.models.first;
      expect(model.minRamFormatted, matches(RegExp(r'\d+(\.\d+)?\s*GB')));
    });
  });
}
