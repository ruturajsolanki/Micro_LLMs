import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:micro_llm_app/main.dart' as app;
import 'package:micro_llm_app/core/di/injection.dart';
import 'package:micro_llm_app/presentation/blocs/model/model_bloc.dart';

/// Integration tests for model download flow.
/// 
/// These tests require network access and sufficient storage.
/// Run on a real device or emulator with:
/// flutter test integration_test/model_download_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Model Download Flow', () {
    setUp(() async {
      await initializeDependencies();
    });

    tearDown(() async {
      await resetDependencies();
    });

    testWidgets('shows onboarding when model not downloaded', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Should show onboarding page
      expect(find.text('MicroLLM'), findsOneWidget);
      expect(find.text('Model Required'), findsOneWidget);
      expect(find.text('Download Model'), findsOneWidget);
    });

    testWidgets('starts download when button pressed', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap download button
      await tester.tap(find.text('Download Model'));
      await tester.pump();

      // Should show downloading state
      expect(find.text('Downloading model...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows progress during download', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Start download
      await tester.tap(find.text('Download Model'));
      
      // Wait a bit for progress
      await tester.pump(const Duration(seconds: 2));

      // Should show progress indicator
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('can cancel download', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Start download
      await tester.tap(find.text('Download Model'));
      await tester.pump(const Duration(milliseconds: 500));

      // Tap cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Should return to initial state
      expect(find.text('Download Model'), findsOneWidget);
    });

    // This test requires actual model download - skip in CI
    testWidgets(
      'completes download and transitions to chat',
      (tester) async {
        app.main();
        await tester.pumpAndSettle();

        // Start download
        await tester.tap(find.text('Download Model'));

        // Wait for download (this will take a while)
        // In real tests, you might want to use a smaller test model
        await tester.pumpAndSettle(const Duration(minutes: 10));

        // Should transition to chat page
        expect(find.text('Start a conversation'), findsOneWidget);
      },
      skip: true, // Skip in automated tests due to large download
    );
  });
}
