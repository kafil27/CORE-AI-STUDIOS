import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'dart:io';
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
    Key? key,
    required this.request,
    this.isExpanded = false,
    this.onRetry,
    this.showProgress = true,
    this.onCancel,
    this.isAddedToCollection = false,
    this.onCollectionToggle,
  }) : super(key: key);

  @override
  _GenerationRequestCardState createState() => _GenerationRequestCardState();
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
    if (status == 'processing') return 0.2;
    if (status == 'completed') return 1.0;
    return 0.0;
  }

  double _getTargetProgress() {
    final status = widget.request.status.toLowerCase();
    if (status == 'pending') return 0.2;
    if (status == 'processing') {
      final progress = widget.request.progress ?? 0.0;
      return 0.2 + (progress / 100.0 * 0.6); // Scale between 20% and 80%
    }
    if (status == 'completed') return 1.0;
    return 0.0;
  }

  String _getStatusText() {
    switch (widget.request.status.toLowerCase()) {
      case 'pending':
        return 'Initializing AI...';
      case 'processing':
        return 'Creating Your Video';
      case 'completed':
        return 'Video Ready!';
      case 'failed':
        return 'Generation Failed';
      default:
        return 'Processing...';
    }
  }

  IconData _getStatusIcon() {
    switch (widget.request.status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'processing':
        return Icons.movie_creation;
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.pending;
    }
  }

  Color _getStatusColor() {
    switch (widget.request.status.toLowerCase()) {
      case 'pending':
        return Colors.orange.withOpacity(0.8);
      case 'processing':
        return Colors.blue.withOpacity(0.8);
      case 'completed':
        return Colors.green.withOpacity(0.8);
      case 'failed':
        return Colors.red.withOpacity(0.8);
      default:
        return Colors.grey.withOpacity(0.8);
    }
  }

  Widget _buildProgressSection() {
    if (!widget.showProgress) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      color: _getStatusColor(),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${(_progressAnimation.value * 100).toInt()}%',
                    style: TextStyle(
                      color: _getStatusColor(),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progressAnimation.value,
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutputSection() {
    if (widget.request.status.toLowerCase() != 'completed') {
      return const SizedBox.shrink();
    }

    final videoUrl = widget.request.result is String 
        ? widget.request.result as String
        : (widget.request.result as Map<String, dynamic>?)?['video_url'] as String?;
    
    if (videoUrl == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[800]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video Thumbnail Section
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video Thumbnail
                  _buildThumbnailSection(videoUrl),
                  // Play Button Overlay
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _previewVideo(videoUrl),
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
                ],
              ),
            ),
          ),
          // Info Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Generated Video',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Generated ${_getTimeAgo(widget.request.timestamp)}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.token,
                            size: 16,
                            color: Colors.green[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.request.tokenCost} tokens',
                            style: TextStyle(
                              color: Colors.green[400],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildAnimatedActionButton(
                      icon: _isDownloading ? Icons.downloading_rounded : Icons.download_rounded,
                      label: _isDownloading ? 'Downloading...' : 'Download',
                      onPressed: _isDownloading ? null : () => _downloadVideo(videoUrl),
                      color: Colors.blue[400]!,
                      isLoading: _isDownloading,
                      progress: _downloadProgress,
                    ),
                    _buildAnimatedActionButton(
                      icon: Icons.open_in_browser_rounded,
                      label: 'Open in Browser',
                      onPressed: () => _openInBrowser(videoUrl),
                      color: Colors.green[400]!,
                    ),
                    _buildAnimatedActionButton(
                      icon: widget.isAddedToCollection 
                          ? Icons.bookmark_rounded 
                          : Icons.bookmark_outline_rounded,
                      label: widget.isAddedToCollection ? 'Saved' : 'Add to Collection',
                      onPressed: () => widget.onCollectionToggle?.call(!widget.isAddedToCollection),
                      color: widget.isAddedToCollection ? Colors.amber[400]! : Colors.grey[400]!,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailSection(String videoUrl) {
    return FutureBuilder<Widget>(
      future: _buildVideoThumbnail(videoUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: LoadingAnimationWidget.staggeredDotsWave(
              color: Theme.of(context).primaryColor,
              size: 40,
            ),
          );
        }
        
        if (snapshot.hasError || !snapshot.hasData) {
          return const Icon(Icons.video_file, size: 48);
        }
        
        return snapshot.data!;
      },
    );
  }

  Future<Widget> _buildVideoThumbnail(String videoUrl) async {
    try {
      final uint8List = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128,
        quality: 25,
      );
      
      if (uint8List == null) {
        return const Icon(Icons.video_file, size: 48);
      }
      
      return Image.memory(uint8List, fit: BoxFit.cover);
    } catch (e) {
      return const Icon(Icons.video_file, size: 48);
    }
  }

  Widget _buildAnimatedActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    bool isLoading = false,
    double progress = 0.0,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        backgroundColor: color.withOpacity(0.2),
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: isLoading ? 0.5 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      icon,
                      color: color,
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
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

      final request = await http.Client().send(
        http.Request('GET', Uri.parse(url))..headers['Accept'] = 'video/mp4',
      );

      if (request.statusCode != 200) {
        throw 'Failed to download video: ${request.statusCode}';
      }

      final contentLength = request.contentLength ?? 0;
      int received = 0;

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'AI_Video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File('${appDir.path}/$fileName');
      final sink = file.openWrite();

      await request.stream.listen(
        (List<int> chunk) {
          sink.add(chunk);
          received += chunk.length;
          setState(() {
            _downloadProgress = contentLength > 0 ? received / contentLength : 0;
          });
        },
        onDone: () async {
          await sink.close();
          if (!mounted) return;
          
          NotificationService.showSuccess(
            context: context,
            title: 'Download Complete',
            message: 'Video saved to downloads',
          );

          setState(() {
            _isDownloading = false;
            _downloadProgress = 1.0;
          });
        },
        onError: (error) {
          sink.close();
          throw error;
        },
        cancelOnError: true,
      ).asFuture(); // Convert StreamSubscription to Future

    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
      });

      if (!mounted) return;
      NotificationService.showError(
        context: context,
        title: 'Download Error',
        message: 'Failed to download video',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<void> _previewVideo(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw 'Could not launch video preview';
      }
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        context: context,
        title: 'Preview Error',
        message: 'Could not preview the video',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<void> _openInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch video in browser';
      }
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        context: context,
        title: 'Browser Error',
        message: 'Could not open the video in browser',
        technicalDetails: e.toString(),
      );
    }
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[800]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getStatusIcon(),
                color: _getStatusColor(),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.request.prompt,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onCancel != null &&
                  widget.request.status.toLowerCase() == 'pending')
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                  onPressed: widget.onCancel,
                ),
            ],
          ),
          _buildProgressSection(),
          _buildOutputSection(),
        ],
      ),
    );
  }
} 