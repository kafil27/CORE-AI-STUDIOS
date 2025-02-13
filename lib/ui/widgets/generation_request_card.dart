import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:video_thumbnail_imageview/video_thumbnail_imageview.dart';
import '../../models/generation_request.dart';
import '../../models/generation_type.dart';
import '../../services/downloads_service.dart';
import '../../services/notification_service.dart';
import 'loading_overlay.dart';
import 'generation_progress_bar.dart';

class GenerationRequestCard extends ConsumerStatefulWidget {
  final GenerationRequest request;
  final bool isExpanded;
  final VoidCallback? onRetry;
  final bool showProgress;
  final VoidCallback? onCancel;
  final bool isAddedToCollection;
  final Function(bool)? onCollectionToggle;

  const GenerationRequestCard({
    super.key,
    required this.request,
    this.isExpanded = false,
    this.onRetry,
    this.showProgress = true,
    this.onCancel,
    this.isAddedToCollection = false,
    this.onCollectionToggle,
  });

  @override
  ConsumerState<GenerationRequestCard> createState() => _GenerationRequestCardState();
}

class _GenerationRequestCardState extends ConsumerState<GenerationRequestCard> with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  double _downloadProgress = 0;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _progressAnimation = Tween<double>(
      begin: _getInitialProgress(),
      end: _getTargetProgress(),
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GenerationRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.progress != widget.request.progress ||
        oldWidget.request.status != widget.request.status) {
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: _getTargetProgress(),
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut,
      ));
      _progressController.forward(from: 0);
    }
  }

  double _getInitialProgress() {
    final status = widget.request.status.toLowerCase();
    if (status == 'pending') return 0.0;
    if (status == 'processing') {
      return (widget.request.progress ?? 0) / 100;
    }
    if (status == 'completed') return 1.0;
    return 0.0;
  }

  double _getTargetProgress() {
    final status = widget.request.status.toLowerCase();
    if (status == 'pending') return 0.0;
    if (status == 'processing') {
      return (widget.request.progress ?? 0) / 100;
    }
    if (status == 'completed') return 1.0;
    return 0.0;
  }

  String _getStatusMessage() {
    final status = widget.request.status.toLowerCase();
    if (status == 'pending') return 'Initializing...';
    if (status == 'processing') return 'Generating your masterpiece...';
    if (status == 'completed') return 'Generation completed!';
    if (status == 'failed') return 'Generation failed';
    return 'Processing...';
  }

  Color _getStatusColor() {
    final status = widget.request.status.toLowerCase();
    if (status == 'pending') return Colors.amber;
    if (status == 'processing') return Colors.blue;
    if (status == 'completed') return Colors.green;
    if (status == 'failed') return Colors.red;
    return Colors.grey;
  }

  Widget _buildStatusIcon() {
    final status = widget.request.status.toLowerCase();
    if (status == 'pending') {
      return LoadingAnimationWidget.staggeredDotsWave(
        color: Colors.amber,
        size: 24,
      );
    }
    if (status == 'processing') {
      return LoadingAnimationWidget.inkDrop(
        color: Colors.blue,
        size: 24,
      );
    }
    if (status == 'completed') {
      return const Icon(Icons.check_circle, color: Colors.green, size: 24);
    }
    if (status == 'failed') {
      return const Icon(Icons.error, color: Colors.red, size: 24);
    }
    return const Icon(Icons.hourglass_empty, color: Colors.grey, size: 24);
  }

  Widget _buildThumbnailSection(String videoUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VTImageView(
              videoUrl: videoUrl,
              assetPlaceHolder: 'assets/bot_image.png',
              errorBuilder: (context, error, stack) => Container(
                color: Colors.grey[900],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.video_file,
                      size: 48,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Video thumbnail not available',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Play button overlay
            if (widget.request.status.toLowerCase() == 'completed')
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => launchUrl(Uri.parse(videoUrl)),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white24,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadVideo(String url) async {
    if (_isDownloading) return;

    try {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0;
      });

      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied');
      }

      final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        setState(() {
          _downloadProgress = contentLength > 0 ? downloaded / contentLength : 0;
        });
      }

      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = await DownloadsService.getLocalFile(fileName, ContentType.video);
      await file.writeAsBytes(bytes);

      // Save to gallery
      await Gal.putVideo(file.path);

      if (mounted) {
        NotificationService.showSuccess(
          context: context,
          title: 'Success',
          message: 'Video saved to gallery',
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError(
          context: context,
          title: 'Download Error',
          message: 'Failed to download video',
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoUrl = widget.request.outputUrl ?? widget.request.storageUrl;
    final isCompleted = widget.request.status.toLowerCase() == 'completed';
    final status = widget.request.status.toLowerCase();
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status == 'completed' ? 'Generation completed!' : 'Processing...',
                    style: TextStyle(
                      color: _getStatusColor(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.onCancel != null && !isCompleted)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onCancel,
                    color: Colors.grey[400],
                  ),
              ],
            ),
          ),

          // Prompt Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.request.prompt,
              style: const TextStyle(fontSize: 16),
            ),
          ),

          // Progress Bar Section (if not completed)
          if (widget.showProgress && !isCompleted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GenerationProgressBar(
                progress: _progressAnimation.value,
                status: widget.request.status,
                showLabel: true,
                startColor: _getStatusColor(),
              ),
            ),

          // Generation Complete Actions
          if (isCompleted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.onCollectionToggle != null)
                          IconButton(
                            icon: Icon(
                              widget.isAddedToCollection
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: widget.isAddedToCollection ? Colors.amber : Colors.grey[400],
                            ),
                            onPressed: () => widget.onCollectionToggle?.call(!widget.isAddedToCollection),
                          ),
                        IconButton(
                          icon: Icon(Icons.download, color: Colors.grey[400]),
                          onPressed: videoUrl != null ? () => _downloadVideo(videoUrl) : null,
                        ),
                        IconButton(
                          icon: Icon(Icons.open_in_browser, color: Colors.grey[400]),
                          onPressed: videoUrl != null ? () => launchUrl(Uri.parse(videoUrl)) : null,
                        ),
                      ],
                    ),
                  ),
                  // Start New Generation Button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).primaryColor.withOpacity(0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed: () {
                        // Handle new generation
                      },
                      tooltip: 'Start New Generation',
                    ),
                  ),
                ],
              ),
            ),

          // Error/Retry Section
          if (widget.request.errorMessage != null && widget.onRetry != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error: ${widget.request.errorMessage}',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Generation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400]?.withOpacity(0.2),
                      foregroundColor: Colors.red[400],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
} 