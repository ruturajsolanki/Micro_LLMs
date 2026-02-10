import 'package:flutter_test/flutter_test.dart';

import 'package:micro_llm_app/data/services/model_download_service.dart';

void main() {
  group('DownloadProgress', () {
    test('calculates progress percentage correctly', () {
      final progress = DownloadProgress(
        downloadedBytes: 500 * 1024 * 1024, // 500 MB
        totalBytes: 1000 * 1024 * 1024, // 1 GB
        bytesPerSecond: 10 * 1024 * 1024, // 10 MB/s
      );

      expect(progress.progress, closeTo(0.5, 0.01));
      expect(progress.formattedProgress, '50.0%');
    });

    test('formats speed correctly for MB/s', () {
      final progress = DownloadProgress(
        downloadedBytes: 100,
        totalBytes: 1000,
        bytesPerSecond: 5 * 1024 * 1024, // 5 MB/s
      );

      expect(progress.formattedSpeed, contains('MB/s'));
      expect(progress.formattedSpeed, contains('5'));
    });

    test('formats speed correctly for KB/s', () {
      final progress = DownloadProgress(
        downloadedBytes: 100,
        totalBytes: 1000,
        bytesPerSecond: 500 * 1024, // 500 KB/s
      );

      expect(progress.formattedSpeed, contains('KB/s'));
    });

    test('calculates ETA correctly', () {
      final progress = DownloadProgress(
        downloadedBytes: 500 * 1024 * 1024, // 500 MB downloaded
        totalBytes: 1000 * 1024 * 1024, // 1 GB total
        bytesPerSecond: 10 * 1024 * 1024, // 10 MB/s
      );

      // 500 MB remaining at 10 MB/s = 50 seconds
      expect(progress.eta, contains('50'));
      expect(progress.eta, contains('s'));
    });

    test('handles zero bytes per second gracefully', () {
      final progress = DownloadProgress(
        downloadedBytes: 100,
        totalBytes: 1000,
        bytesPerSecond: 0,
      );

      expect(progress.eta, '--:--');
      expect(progress.formattedSpeed, '0 B/s');
    });

    test('handles edge case of download complete', () {
      final progress = DownloadProgress(
        downloadedBytes: 1000,
        totalBytes: 1000,
        bytesPerSecond: 100,
      );

      expect(progress.progress, 1.0);
      expect(progress.formattedProgress, '100.0%');
    });
  });

  group('DownloadedModel', () {
    test('formats size correctly for GB', () {
      final model = DownloadedModel(
        filePath: '/path/to/model.gguf',
        fileName: 'model.gguf',
        sizeBytes: 2 * 1024 * 1024 * 1024, // 2 GB
        downloadedAt: DateTime.now(),
      );

      expect(model.formattedSize, contains('2'));
      expect(model.formattedSize, contains('GB'));
    });

    test('formats size correctly for MB', () {
      final model = DownloadedModel(
        filePath: '/path/to/model.gguf',
        fileName: 'model.gguf',
        sizeBytes: 500 * 1024 * 1024, // 500 MB
        downloadedAt: DateTime.now(),
      );

      expect(model.formattedSize, contains('500'));
      expect(model.formattedSize, contains('MB'));
    });

    test('uses catalog model name when available', () {
      final model = DownloadedModel(
        filePath: '/path/to/model.gguf',
        fileName: 'some-file.gguf',
        sizeBytes: 100,
        downloadedAt: DateTime.now(),
        catalogModel: null,
      );

      expect(model.displayName, 'some-file.gguf');
    });
  });

  group('DownloadEvent types', () {
    test('DownloadStarted contains correct info', () {
      const event = DownloadStarted(
        modelId: 'test-model',
        totalBytes: 1000000,
        resumingFrom: 500000,
      );

      expect(event.modelId, 'test-model');
      expect(event.totalBytes, 1000000);
      expect(event.resumingFrom, 500000);
    });

    test('DownloadComplete contains correct info', () {
      const event = DownloadComplete(
        modelId: 'test-model',
        filePath: '/path/to/file.gguf',
        sizeBytes: 1000000,
      );

      expect(event.modelId, 'test-model');
      expect(event.filePath, '/path/to/file.gguf');
      expect(event.sizeBytes, 1000000);
    });

    test('DownloadError contains message', () {
      const event = DownloadError(message: 'Network error');

      expect(event.message, 'Network error');
    });

    test('DownloadCancelled contains bytes downloaded', () {
      const event = DownloadCancelled(downloadedBytes: 500000);

      expect(event.downloadedBytes, 500000);
    });
  });
}
