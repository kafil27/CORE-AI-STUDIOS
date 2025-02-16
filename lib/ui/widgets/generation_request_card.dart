import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:video_thumbnail_imageview/video_thumbnail_imageview.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  bool _isAddingToCollection = false;
  late AnimationController _progressController;
  Animation<double>? _progressAnimation;
  String _currentStatus = '';
  bool _hasError = false;
  String? _errorMessage;
  String? _videoUrl;
  String? _fileName;
  bool _isVideoReady = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _setupProgressAnimation(initial: true);
    _updateStatus();
    _processVideoOutput();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _setupProgressAnimation({bool initial = false}) {
    final status = widget.request.status.toLowerCase();
    double targetProgress = 0.0;
    
    if (status == 'pending') {
      targetProgress = 0.2;
    } else if (status == 'processing') {
      final currentProgress = _progressAnimation?.value ?? 0.0;
      final apiProgress = widget.request.progress != null ? 
        (widget.request.progress! / 100).clamp(0.0, 0.8) : 0.4;
      targetProgress = apiProgress > currentProgress ? apiProgress : currentProgress;
    } else if (status == 'completed') {
      targetProgress = 1.0;
    } else if (status == 'failed') {
      _hasError = true;
      _errorMessage = widget.request.errorMessage ?? 'Generation failed';
    }

    double startProgress = initial ? 0.0 : _progressAnimation?.value ?? 0.0;
    
    _progressAnimation = Tween<double>(
      begin: startProgress,
      end: targetProgress,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));

    if (!initial && mounted) {
      _progressController.forward(from: 0);
    }
  }

  void _updateStatus() {
    final status = widget.request.status.toLowerCase();
    setState(() {
      if (status == 'pending') {
        _currentStatus = 'Added to Queue';
      } else if (status == 'processing') {
        if ((widget.request.progress ?? 0) < 30) {
          _currentStatus = 'Initializing Generation';
        } else if ((widget.request.progress ?? 0) < 60) {
          _currentStatus = 'Processing Content';
        } else {
          _currentStatus = 'Finalizing Generation';
        }
      } else if (status == 'completed') {
        _currentStatus = 'Generation Complete';
        _processVideoOutput(); // Ensure video output is processed on completion
      } else if (status == 'failed') {
        _currentStatus = 'Generation Failed';
        _hasError = true;
        _errorMessage = widget.request.errorMessage ?? 'Generation failed';
      }
    });
  }

  void _processVideoOutput() {
    if (widget.request.result != null && mounted) {
      final result = widget.request.result!;
      
      print("[DEBUG] Processing video output: ${result.toString()}");
      
      // Extract video URL and post_ids first
      String? videoUrl;
      List<dynamic>? postIds;
      
      if (result.containsKey('outputUrl')) {
        videoUrl = result['outputUrl'] as String?;
        print("[DEBUG] Found video URL: $videoUrl");
      }
      if (result.containsKey('post_ids')) {
        postIds = result['post_ids'] as List<dynamic>?;
        print("[DEBUG] Found post IDs: $postIds");
      }
      
      // Only update state if we have valid output
      if (videoUrl != null || (postIds != null && postIds.isNotEmpty)) {
        setState(() {
          _videoUrl = videoUrl;
          if (_videoUrl != null) {
            _fileName = _videoUrl!.split('/').last;
          }
          _isVideoReady = true;
          print("[DEBUG] Updated state - URL: $_videoUrl, Filename: $_fileName, Ready: $_isVideoReady");
        });
      }
    }
  }

  @override
  void didUpdateWidget(GenerationRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    print("[DEBUG] Widget updated - Old status: ${oldWidget.request.status}, New status: ${widget.request.status}");
    print("[DEBUG] Old result: ${oldWidget.request.result}, New result: ${widget.request.result}");
    
    // Check for result changes
    if (oldWidget.request.result != widget.request.result) {
      print("[DEBUG] Result changed, processing video output");
      _processVideoOutput();
    }
    
    // Check for status changes
    if (oldWidget.request.status != widget.request.status) {
      _setupProgressAnimation();
      _updateStatus();
      
      // Process output again on completion
      if (widget.request.status.toLowerCase() == 'completed') {
        print("[DEBUG] Status changed to completed, processing video output");
        _processVideoOutput();
      }
    }
    
    // Check for progress changes
    if (oldWidget.request.progress != widget.request.progress) {
      _setupProgressAnimation();
      _updateStatus();
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
          children: _isVideoReady 
            ? [
                VTImageView(
                  videoUrl: videoUrl,
                  assetPlaceHolder: 'assets/bot_image.png',
                  errorBuilder: (context, error, stack) => _buildVideoPlaceholder(),
                ),
                // Play button overlay
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openVideo(videoUrl),
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
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
                          if (_fileName != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _fileName!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ]
            : [_buildVideoPlaceholder()],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
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
            widget.request.status.toLowerCase() == 'completed' 
              ? 'Processing Video Output...'
              : 'Generating Video...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 4),
            Text(
              _fileName!,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
              ),
            ),
          ],
        ],
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
    } catch (e) {
      print("[DEBUG] Download error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
        });
      }
    }
  }

  Widget _buildActionButtons() {
    final status = widget.request.status.toLowerCase();
    final isCompleted = status == 'completed';
    final videoUrl = widget.request.result?['outputUrl'] as String?;
    final bool showNewGeneration = isCompleted || status == 'failed';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showNewGeneration)
          _buildAnimatedIconButton(
            icon: Icons.add_circle_outline,
            color: Colors.teal,
            onPressed: () {
              // Handle new generation
              Navigator.of(context).pop(); // Close current generation view
            },
          ),
        if (isCompleted && videoUrl != null) ...[
          const SizedBox(width: 8),
          _buildAnimatedIconButton(
            icon: _isDownloading ? Icons.download_done : Icons.download,
            color: _isDownloading ? Colors.green : Colors.blue,
            onPressed: () => _downloadVideo(videoUrl),
            loading: _isDownloading,
          ),
          const SizedBox(width: 8),
          _buildAnimatedIconButton(
            icon: Icons.play_circle_outline,
            color: Colors.purple,
            onPressed: () => _openVideo(videoUrl),
          ),
          const SizedBox(width: 8),
          _buildAnimatedIconButton(
            icon: widget.isAddedToCollection ? Icons.favorite : Icons.favorite_border,
            color: widget.isAddedToCollection ? Colors.red : Colors.grey,
            onPressed: () => _addToCollection(),
            loading: _isAddingToCollection,
          ),
        ] else if (status == 'pending' && widget.onCancel != null) ...[
          _buildAnimatedIconButton(
            icon: Icons.cancel_outlined,
            color: Colors.red,
            onPressed: () => widget.onCancel!(),
          ),
        ],
      ],
    );
  }

  Widget _buildAnimatedIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool loading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: loading ? null : onPressed,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: loading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: LoadingAnimationWidget.staggeredDotsWave(
                    color: color,
                    size: 20,
                  ),
                )
              : Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
        ),
      ),
    );
  }

  Future<void> _addToCollection() async {
    if (_isAddingToCollection) return;
    
    setState(() => _isAddingToCollection = true);
    
    try {
      final videoUrl = widget.request.result?['outputUrl'] as String?;
      if (videoUrl == null) throw Exception('Video URL not found');

      // Add to Firestore
      await FirebaseFirestore.instance.collection('user_collection').add({
        'userId': widget.request.userId,
        'videoUrl': videoUrl,
        'prompt': widget.request.prompt,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'video',
        'metadata': widget.request.metadata,
      });

      // Update collection status
      widget.onCollectionToggle?.call(true);
      
      NotificationService.showSuccess(
        context: context,
        title: 'Added to Collection',
        message: 'Video has been added to your collection',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to add to collection: ${e.toString()}',
      );
    } finally {
      setState(() => _isAddingToCollection = false);
    }
  }

  Future<void> _openVideo(String url) async {
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to open video: ${e.toString()}',
      );
    }
  }

  Widget _buildGenerationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: GenerationProgressBar(
              progress: _progressAnimation?.value ?? 0.0,
              status: _currentStatus,
              showLabel: true,
              height: 4,
              startColor: _getStatusColor(),
              endColor: _getStatusColor().withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few minutes',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputSection() {
    if (!_isVideoReady || _videoUrl == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),
        _buildThumbnailSection(_videoUrl!),
        const SizedBox(height: 16),
        _buildActionButtons(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.request.status.toLowerCase();
    final isGenerating = status == 'pending' || status == 'processing';
    
    print("[DEBUG] Building card - Status: $status, IsGenerating: $isGenerating, VideoReady: $_isVideoReady, VideoUrl: $_videoUrl");
    
    return Card(
      elevation: 4,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.black.withOpacity(0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isGenerating) 
              _buildGenerationSection(),
            if (_hasError) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red[400],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage ?? 'An error occurred',
                        style: TextStyle(
                          color: Colors.red[400],
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (widget.onRetry != null)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        color: Colors.red[400],
                        onPressed: widget.onRetry,
                      ),
                  ],
                ),
              ),
            ],
            if (status == 'completed' && _videoUrl != null)
              _buildOutputSection(),
          ],
        ),
      ),
    );
  }
} 