import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/device_specs.dart';

/// Data source for scanning device hardware specifications.
/// 
/// Uses platform channels to access Android system information.
abstract class DeviceScannerDataSource {
  /// Scan device and return specifications.
  Future<DeviceSpecs> scanDevice();
  
  /// Get real-time memory status.
  Future<MemoryStatus> getMemoryStatus();
  
  /// Get CPU temperature (if available).
  Future<double?> getCpuTemperature();
  
  /// Check if device is thermal throttling.
  Future<bool> isThermalThrottling();
}

class DeviceScannerDataSourceImpl with Loggable implements DeviceScannerDataSource {
  static const _channel = MethodChannel('com.microllm.app/device_scanner');
  
  DeviceSpecs? _cachedSpecs;
  DateTime? _lastScanTime;
  
  @override
  Future<DeviceSpecs> scanDevice() async {
    // Use cached specs if scanned recently (specs don't change)
    if (_cachedSpecs != null && 
        _lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!) < const Duration(minutes: 5)) {
      return _cachedSpecs!;
    }
    
    try {
      logger.i('Scanning device specifications...');
      
      final result = await _channel.invokeMethod<Map>('scanDevice');
      
      if (result == null) {
        throw const StorageException(message: 'Failed to scan device');
      }
      
      final specs = DeviceSpecs(
        totalRamBytes: result['totalRamBytes'] as int,
        availableRamBytes: result['availableRamBytes'] as int,
        cpuCores: result['cpuCores'] as int,
        cpuArchitecture: result['cpuArchitecture'] as String,
        cpuMaxFrequencyMHz: result['cpuMaxFrequencyMHz'] as int?,
        supportsNeon: result['supportsNeon'] as bool? ?? true,
        hasNpu: result['hasNpu'] as bool? ?? false,
        gpuName: result['gpuName'] as String?,
        availableStorageBytes: result['availableStorageBytes'] as int,
        deviceModel: result['deviceModel'] as String,
        sdkVersion: result['sdkVersion'] as int,
        socName: result['socName'] as String?,
      );
      
      _cachedSpecs = specs;
      _lastScanTime = DateTime.now();
      
      logger.i('Device scan complete: ${specs.deviceModel}, '
               '${specs.ramFormatted} RAM, ${specs.cpuCores} cores');
      
      return specs;
    } on PlatformException catch (e) {
      logger.e('Device scan failed: $e');
      
      // Return fallback specs based on platform defaults
      return _getFallbackSpecs();
    }
  }
  
  @override
  Future<MemoryStatus> getMemoryStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getMemoryStatus');
      
      if (result == null) {
        throw const StorageException(message: 'Failed to get memory status');
      }
      
      return MemoryStatus(
        totalBytes: result['totalBytes'] as int,
        availableBytes: result['availableBytes'] as int,
        usedBytes: result['usedBytes'] as int,
        lowMemoryThreshold: result['lowMemoryThreshold'] as int,
        isLowMemory: result['isLowMemory'] as bool,
      );
    } on PlatformException catch (e) {
      logger.e('Failed to get memory status: $e');
      rethrow;
    }
  }
  
  @override
  Future<double?> getCpuTemperature() async {
    try {
      final result = await _channel.invokeMethod<double>('getCpuTemperature');
      return result;
    } on PlatformException {
      // Temperature reading not available on all devices
      return null;
    }
  }
  
  @override
  Future<bool> isThermalThrottling() async {
    try {
      final result = await _channel.invokeMethod<bool>('isThermalThrottling');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
  
  /// Get fallback specs when platform channel fails.
  DeviceSpecs _getFallbackSpecs() {
    return DeviceSpecs(
      totalRamBytes: 4 * 1024 * 1024 * 1024, // Assume 4GB
      availableRamBytes: 2 * 1024 * 1024 * 1024, // Assume 2GB available
      cpuCores: Platform.numberOfProcessors,
      cpuArchitecture: 'arm64-v8a', // Assume modern ARM
      supportsNeon: true,
      availableStorageBytes: 10 * 1024 * 1024 * 1024, // Assume 10GB
      deviceModel: 'Unknown Device',
      sdkVersion: 29,
    );
  }
}

/// Real-time memory status.
class MemoryStatus {
  final int totalBytes;
  final int availableBytes;
  final int usedBytes;
  final int lowMemoryThreshold;
  final bool isLowMemory;
  
  const MemoryStatus({
    required this.totalBytes,
    required this.availableBytes,
    required this.usedBytes,
    required this.lowMemoryThreshold,
    required this.isLowMemory,
  });
  
  double get usagePercent => usedBytes / totalBytes * 100;
  
  String get availableFormatted => 
      '${(availableBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
