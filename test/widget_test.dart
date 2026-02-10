import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:micro_llm_app/presentation/widgets/device_specs_card.dart';
import 'package:micro_llm_app/presentation/widgets/benchmark_dialog.dart';
import 'package:micro_llm_app/domain/entities/device_specs.dart';

void main() {
  group('DeviceSpecsCard', () {
    late DeviceSpecs mockSpecs;

    setUp(() {
      mockSpecs = DeviceSpecs(
        totalRamBytes: 8 * 1024 * 1024 * 1024,
        availableRamBytes: 4 * 1024 * 1024 * 1024,
        availableStorageBytes: 50 * 1024 * 1024 * 1024,
        cpuCores: 8,
        cpuArchitecture: 'arm64-v8a',
        deviceModel: 'Test Device',
        sdkVersion: 33,
        supportsNeon: true,
        socName: 'Test SoC',
      );
    });

    testWidgets('displays device model', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSpecsCard(specs: mockSpecs),
          ),
        ),
      );

      expect(find.text('Test Device'), findsOneWidget);
    });

    testWidgets('displays RAM information', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSpecsCard(specs: mockSpecs),
          ),
        ),
      );

      expect(find.text('RAM'), findsOneWidget);
      expect(find.textContaining('8'), findsWidgets); // 8 GB
    });

    testWidgets('displays CPU information', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSpecsCard(specs: mockSpecs),
          ),
        ),
      );

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('8 cores'), findsOneWidget);
    });

    testWidgets('displays SoC name when available', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSpecsCard(specs: mockSpecs),
          ),
        ),
      );

      expect(find.textContaining('SoC'), findsOneWidget);
      expect(find.textContaining('Test SoC'), findsOneWidget);
    });

    testWidgets('shows cleanup button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSpecsCard(specs: mockSpecs),
          ),
        ),
      );

      expect(find.byIcon(Icons.cleaning_services_rounded), findsOneWidget);
    });
  });

  group('BenchmarkDialog', () {
    testWidgets('shows title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BenchmarkDialog(),
          ),
        ),
      );

      expect(find.textContaining('Performance Benchmark'), findsOneWidget);
    });

    testWidgets('shows start button initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BenchmarkDialog(),
          ),
        ),
      );

      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('shows cancel button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BenchmarkDialog(),
          ),
        ),
      );

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('displays description text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BenchmarkDialog(),
          ),
        ),
      );

      expect(find.textContaining('benchmark'), findsWidgets);
    });
  });
}
