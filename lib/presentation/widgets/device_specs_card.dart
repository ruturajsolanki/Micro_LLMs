import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/device_specs.dart';

/// Card displaying device hardware specifications.
class DeviceSpecsCard extends StatefulWidget {
  final DeviceSpecs specs;
  final VoidCallback? onSpecsUpdated;
  
  const DeviceSpecsCard({
    super.key,
    required this.specs,
    this.onSpecsUpdated,
  });

  @override
  State<DeviceSpecsCard> createState() => _DeviceSpecsCardState();
}

class _DeviceSpecsCardState extends State<DeviceSpecsCard> {
  static const _memoryChannel = MethodChannel('com.microllm.app/memory');
  bool _isCleaningRam = false;

  Future<void> _cleanupRam() async {
    if (_isCleaningRam) return;
    
    setState(() => _isCleaningRam = true);
    
    try {
      final result = await _memoryChannel.invokeMethod<Map<Object?, Object?>>('cleanupRam');
      
      if (!mounted) return;
      
      if (result != null) {
        final totalFreed = (result['totalFreedBytes'] as num?)?.toInt() ?? 0;
        final freedMB = (totalFreed / (1024 * 1024)).toStringAsFixed(1);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(totalFreed > 0 
                    ? 'Freed $freedMB MB of RAM' 
                    : 'RAM is already optimized'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Notify parent to refresh specs
        widget.onSpecsUpdated?.call();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cleanup RAM: ${e.message}'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCleaningRam = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final specs = widget.specs;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.smartphone,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        specs.deviceModel,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Android ${specs.sdkVersion}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Specs Grid
            Row(
              children: [
                Expanded(
                  child: _SpecItem(
                    icon: Icons.memory,
                    label: 'RAM',
                    value: specs.ramFormatted,
                    detail: '${specs.availableRamFormatted} available',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SpecItem(
                    icon: Icons.developer_board,
                    label: 'CPU',
                    value: '${specs.cpuCores} cores',
                    detail: specs.cpuArchitecture,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _SpecItem(
                    icon: Icons.storage,
                    label: 'Storage',
                    value: specs.storageFormatted,
                    detail: 'Available',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SpecItem(
                    icon: Icons.speed,
                    label: 'CPU Speed',
                    value: specs.cpuMaxFrequencyMHz != null
                        ? '${specs.cpuMaxFrequencyMHz} MHz'
                        : 'Unknown',
                    detail: specs.supportsNeon ? 'NEON enabled' : 'No NEON',
                  ),
                ),
              ],
            ),
            
            // SOC info if available
            if (specs.socName != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.memory_outlined,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SoC: ${specs.socName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (specs.hasNpu) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'NPU',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            
            // RAM usage bar with cleanup button
            const SizedBox(height: 16),
            _RamUsageBarWithCleanup(
              usagePercent: specs.ramUsagePercent,
              totalGB: specs.totalRamGB,
              availableGB: specs.availableRamGB,
              isCleaningRam: _isCleaningRam,
              onCleanup: _cleanupRam,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  
  const _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RamUsageBarWithCleanup extends StatelessWidget {
  final double usagePercent;
  final double totalGB;
  final double availableGB;
  final bool isCleaningRam;
  final VoidCallback onCleanup;
  
  const _RamUsageBarWithCleanup({
    required this.usagePercent,
    required this.totalGB,
    required this.availableGB,
    required this.isCleaningRam,
    required this.onCleanup,
  });
  
  @override
  Widget build(BuildContext context) {
    final usedGB = totalGB - availableGB;
    final color = usagePercent > 80
        ? Colors.red
        : usagePercent > 60
            ? Colors.orange
            : Colors.green;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RAM Usage',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${usedGB.toStringAsFixed(1)} / ${totalGB.toStringAsFixed(1)} GB',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usagePercent / 100,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Cleanup button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isCleaningRam ? null : onCleanup,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: usagePercent > 60 
                        ? Colors.orange.shade50 
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: usagePercent > 60 
                          ? Colors.orange.shade200 
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: isCleaningRam
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              usagePercent > 60 
                                  ? Colors.orange.shade700 
                                  : Colors.grey.shade600,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.cleaning_services_rounded,
                          size: 20,
                          color: usagePercent > 60 
                              ? Colors.orange.shade700 
                              : Colors.grey.shade600,
                        ),
                ),
              ),
            ),
          ],
        ),
        if (usagePercent > 70) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'High RAM usage may affect LLM performance. Tap the cleanup button to free memory.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
