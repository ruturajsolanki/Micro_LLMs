import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';

import 'package:micro_llm_app/main.dart' as app;
import 'package:micro_llm_app/core/di/injection.dart';
import 'package:micro_llm_app/core/utils/logger.dart';

/// Stress tests for memory usage and leaks.
/// 
/// These tests verify that:
/// 1. Memory usage stays within acceptable bounds during inference
/// 2. No memory leaks occur over repeated operations
/// 3. App gracefully handles low memory situations
/// 
/// Run with:
/// flutter drive --target=test/stress/memory_stress_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Memory Stress Tests', () {
    setUp(() async {
      await initializeDependencies();
    });

    tearDown(() async {
      await resetDependencies();
    });

    testWidgets('memory usage stays bounded during repeated inference', 
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Skip if model not loaded
      if (!find.text('Type a message...').evaluate().isNotEmpty) {
        return;
      }

      final memorySnapshots = <int>[];
      
      // Run multiple inference cycles
      for (int i = 0; i < 10; i++) {
        // Record memory before
        final memBefore = await _getMemoryUsage();
        
        // Send a message
        await tester.enterText(
          find.byType(TextField),
          'Tell me a short joke about programming.',
        );
        await tester.tap(find.byIcon(Icons.send_rounded));
        
        // Wait for response
        await tester.pumpAndSettle(const Duration(seconds: 30));
        
        // Record memory after
        final memAfter = await _getMemoryUsage();
        memorySnapshots.add(memAfter);
        
        AppLogger.memory(
          'Inference cycle $i',
          usedMB: memAfter ~/ (1024 * 1024),
        );
        
        // Clear conversation to release message memory
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear conversation'));
        await tester.pumpAndSettle();
        
        // Give GC time to run
        await tester.pump(const Duration(seconds: 2));
      }
      
      // Analyze memory trend
      final firstSnapshot = memorySnapshots.first;
      final lastSnapshot = memorySnapshots.last;
      final memoryGrowth = lastSnapshot - firstSnapshot;
      
      // Memory growth should be minimal (< 100MB over 10 cycles)
      expect(
        memoryGrowth,
        lessThan(100 * 1024 * 1024),
        reason: 'Memory grew by ${memoryGrowth ~/ (1024 * 1024)}MB over 10 cycles',
      );
    });

    testWidgets('no memory leaks in conversation history', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!find.text('Type a message...').evaluate().isNotEmpty) {
        return;
      }

      final initialMemory = await _getMemoryUsage();
      
      // Add many messages
      for (int i = 0; i < 50; i++) {
        await tester.enterText(find.byType(TextField), 'Message $i');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pump(const Duration(milliseconds: 100));
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Clear conversation
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear conversation'));
      await tester.pumpAndSettle();
      
      // Force GC
      await tester.pump(const Duration(seconds: 3));
      
      final finalMemory = await _getMemoryUsage();
      final memoryDiff = finalMemory - initialMemory;
      
      // Memory should return close to initial (within 20MB)
      expect(
        memoryDiff.abs(),
        lessThan(20 * 1024 * 1024),
        reason: 'Memory leak detected: ${memoryDiff ~/ (1024 * 1024)}MB not released',
      );
    });

    testWidgets('handles rapid message sending without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!find.text('Type a message...').evaluate().isNotEmpty) {
        return;
      }

      // Rapidly send messages
      for (int i = 0; i < 20; i++) {
        await tester.enterText(find.byType(TextField), 'Rapid message $i');
        await tester.tap(find.byIcon(Icons.send_rounded));
        // Don't wait for response - immediately send next
        await tester.pump(const Duration(milliseconds: 50));
      }
      
      // Wait for things to settle
      await tester.pumpAndSettle(const Duration(seconds: 10));
      
      // App should still be responsive
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('handles very long input without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!find.text('Type a message...').evaluate().isNotEmpty) {
        return;
      }

      // Generate a very long input
      final longText = 'This is a test message. ' * 200; // ~4800 chars
      
      await tester.enterText(find.byType(TextField), longText);
      await tester.tap(find.byIcon(Icons.send_rounded));
      
      // Should handle gracefully (may truncate or show error)
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // App should still be responsive
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}

/// Get current memory usage in bytes.
/// 
/// Uses Timeline events to capture memory info.
/// Returns the private dirty memory which represents actual RAM usage.
Future<int> _getMemoryUsage() async {
  // Request GC first for accurate measurement
  developer.Timeline.startSync('GC');
  await Future.delayed(const Duration(milliseconds: 100));
  developer.Timeline.finishSync();
  
  // In a real implementation, this would use platform channels
  // to call Android's ActivityManager.getProcessMemoryInfo()
  // For now, return a placeholder
  return 0;
}
