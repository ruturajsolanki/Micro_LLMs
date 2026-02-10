import 'package:flutter/material.dart';

import '../../domain/entities/model_info.dart';
import '../blocs/model/model_bloc.dart';

/// Banner showing model status when not ready.
/// 
/// Displays download progress, loading status, or errors.
class ModelStatusBanner extends StatelessWidget {
  final ModelState state;
  
  const ModelStatusBanner({
    super.key,
    required this.state,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _backgroundColor(context),
      child: Row(
        children: [
          _buildIcon(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: _foregroundColor(context),
                  ),
                ),
                if (state.isDownloading && state.downloadProgress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: state.downloadProgress!.progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation(_foregroundColor(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.downloadProgress!.progressPercent} • ${state.downloadProgress!.speedFormatted}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _foregroundColor(context).withOpacity(0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildIcon(BuildContext context) {
    if (state.isDownloading || state.isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(_foregroundColor(context)),
        ),
      );
    }
    
    return Icon(
      _icon,
      size: 20,
      color: _foregroundColor(context),
    );
  }
  
  String get _title {
    switch (state.status) {
      case ModelStatus.notDownloaded:
        return 'Model not downloaded';
      case ModelStatus.downloading:
        return 'Downloading model...';
      case ModelStatus.downloaded:
        return 'Model ready to load';
      case ModelStatus.loading:
        return 'Loading model...';
      case ModelStatus.unloading:
        return 'Unloading model...';
      case ModelStatus.error:
        return state.errorMessage ?? 'Error';
      case ModelStatus.ready:
        return 'Model ready';
    }
  }
  
  IconData get _icon {
    switch (state.status) {
      case ModelStatus.notDownloaded:
        return Icons.download_rounded;
      case ModelStatus.downloaded:
        return Icons.check_circle_outline;
      case ModelStatus.error:
        return Icons.error_outline;
      default:
        return Icons.info_outline;
    }
  }
  
  Color _backgroundColor(BuildContext context) {
    switch (state.status) {
      case ModelStatus.error:
        return Colors.red.shade100;
      case ModelStatus.downloading:
      case ModelStatus.loading:
        return Colors.blue.shade100;
      case ModelStatus.downloaded:
        return Colors.green.shade100;
      default:
        return Colors.orange.shade100;
    }
  }
  
  Color _foregroundColor(BuildContext context) {
    switch (state.status) {
      case ModelStatus.error:
        return Colors.red.shade900;
      case ModelStatus.downloading:
      case ModelStatus.loading:
        return Colors.blue.shade900;
      case ModelStatus.downloaded:
        return Colors.green.shade900;
      default:
        return Colors.orange.shade900;
    }
  }
}
