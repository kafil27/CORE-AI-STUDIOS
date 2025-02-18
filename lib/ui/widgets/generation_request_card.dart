import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../models/generation_request.dart';
import '../../models/generation_type.dart';
import '../../services/downloads_service.dart';
import '../../services/notification_service.dart';
import 'loading_overlay.dart';
import 'generation_progress_bar.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:gradient_progress_bar/gradient_progress_bar.dart';
import '../../services/predis_video_service.dart';
import '../../config/ai_service_config.dart';
import '../screens/ai_features/video_ai_screen.dart';

class GenerationRequestCard extends ConsumerStatefulWidget {
  final GenerationRequest request;
  final DocumentReference reference;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final Function(bool)? onCollectionToggle;
  final bool isAddedToCollection;
  final bool isTogglingCollection;

  const GenerationRequestCard({
    Key? key,
    required this.request,
    required this.reference,
    this.onRetry,
    this.onCancel,
    this.onCollectionToggle,
    this.isAddedToCollection = false,
    this.isTogglingCollection = false,
  }) : super(key: key);

  @override
  ConsumerState<GenerationRequestCard> createState() => _GenerationRequestCardState();
}

class _GenerationRequestCardState extends ConsumerState<GenerationRequestCard> with TickerProviderStateMixin {
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isAddingToCollection = false;
  late AnimationController _progressController;
  late AnimationController _fadeController;
  late Animation<double> _progressAnimation;
  late Animation<double> _fadeAnimation;
  String _currentStatus = '';
  bool _hasError = false;
  String? _errorMessage;
  String? _videoUrl;
  String? _fileName;
  bool _isVideoReady = false;
  late AnimationController _tickController;
  late Animation<double> _tickAnimation;
  bool _showCompletionTick = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupProgressAnimation(initial: true);
    _updateStatus();
    _processVideoOutput();
    _createRequiredDirectories();
  }

  void _initializeAnimations() {
    // Progress animation controller
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Fade animation controller
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _fadeController.forward();

    // Tick animation controller
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _tickAnimation = CurvedAnimation(
      parent: _tickController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _tickController.dispose();
    _progressController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _setupProgressAnimation({bool initial = false}) {
    final status = widget.request.status.toLowerCase();
    double targetProgress = 0.0;
    
    if (status == 'pending') {
      targetProgress = 0.2;
      _showCompletionTick = false;
    } else if (status == 'processing') {
      final apiProgress = widget.request.progress != null ? 
        (widget.request.progress! / 100).clamp(0.0, 0.8) : 0.4;
      targetProgress = apiProgress;
      _showCompletionTick = false;
    } else if (status == 'completed') {
      targetProgress = 1.0;
      _showCompletionTick = true;
      _tickController.forward();
    } else if (status == 'failed') {
      _hasError = true;
      _errorMessage = widget.request.errorMessage ?? 'Generation failed';
    }

      _progressAnimation = Tween<double>(
      begin: initial ? 0.0 : _progressAnimation.value,
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
      
      String? videoUrl;
      String? thumbnailUrl;
      List<dynamic>? postIds;
      
      // Try to get URL from different possible keys
      if (result.containsKey('outputUrl')) {
        videoUrl = result['outputUrl'] as String?;
      } else if (result.containsKey('video_url')) {
        videoUrl = result['video_url'] as String?;
      } else if (result.containsKey('url')) {
        videoUrl = result['url'] as String?;
      }
      
      // Try to get thumbnail from different possible keys
      if (result.containsKey('thumbnailUrl')) {
        thumbnailUrl = result['thumbnailUrl'] as String?;
      } else if (result.containsKey('thumbnail_url')) {
        thumbnailUrl = result['thumbnail_url'] as String?;
      } else if (result.containsKey('preview_url')) {
        thumbnailUrl = result['preview_url'] as String?;
      }
      
      if (result.containsKey('post_ids')) {
        postIds = result['post_ids'] as List<dynamic>?;
      }
      
      print("[DEBUG] Found video URL: $videoUrl");
      print("[DEBUG] Found thumbnail URL: $thumbnailUrl");
      print("[DEBUG] Found post IDs: $postIds");
      
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
    String? thumbnailUrl;
    if (widget.request.result is Map<String, dynamic>) {
      final result = widget.request.result as Map<String, dynamic>;
      thumbnailUrl = result['thumbnail_url'] as String? ?? 
                    result['thumbnailUrl'] as String? ?? 
                    result['preview_url'] as String?;
    }

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl?.isNotEmpty == true)
              CachedNetworkImage(
                imageUrl: thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildVideoPlaceholder(),
                errorWidget: (context, url, error) {
                  debugPrint('Thumbnail error: $error for URL: $url');
                  return _buildVideoPlaceholder();
                },
              )
            else
              _buildVideoPlaceholder(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openVideo(videoUrl),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white30,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40,
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

  Widget _buildVideoPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Pattern
          Opacity(
            opacity: 0.5,
            child: Icon(
              Icons.video_library_rounded,
              size: 80,
              color: Colors.grey[800],
            ),
          ),
          // Loading Animation
          if (!_isVideoReady)
            LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.white70,
              size: 40,
            ),
        ],
      ),
    );
  }

  Future<void> _createRequiredDirectories() async {
    try {
      final baseDir = await getExternalStorageDirectory();
      if (baseDir != null) {
        final videoDir = Directory(path.join(
          baseDir.path,
          'core_ai_studios',
          'generatedcontent',
          'video',
        ));
        if (!await videoDir.exists()) {
          await videoDir.create(recursive: true);
        }
      }
    } catch (e) {
      print("[DEBUG] Error creating directories: $e");
    }
  }

  Widget _buildGenerationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progressAnimation.value,
                    minHeight: 6,
                    backgroundColor: Colors.grey[900],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _progressAnimation.value == 1.0 ? Colors.green : _getStatusColor(),
                    ),
                  ),
                ),
                if (_currentStatus.isNotEmpty)
                  Positioned(
                    right: 24,
                    top: -10,
                    child: Text(
                      '${(_progressAnimation.value * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_showCompletionTick)
            ScaleTransition(
              scale: _tickAnimation,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.request.status.toLowerCase();
    final isGenerating = status == 'pending' || status == 'processing';
    final isCompleted = status == 'completed';
    
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) => Opacity(
        opacity: _fadeAnimation.value,
        child: Card(
          elevation: 8,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
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
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hasError) ...[
                  const SizedBox(height: 16),
                  _buildErrorSection(),
                ],
                if (isCompleted && _videoUrl != null)
                  _buildOutputSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red[400],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? 'An error occurred',
              style: TextStyle(
                color: Colors.red[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildOutputSection() {
    if (!_isVideoReady || _videoUrl == null) return const SizedBox.shrink();

    final isDownloaded = widget.request.metadata?['isDownloaded'] ?? false;
    final isAddedToCollection = widget.request.metadata?['isAddedToCollection'] ?? false;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      offset: Offset.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _buildThumbnailSection(_videoUrl!),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIconButton(
                  icon: isDownloaded ? Icons.check_circle : Icons.download_rounded,
                  color: isDownloaded ? Colors.green : Colors.blue,
                  onPressed: () => _downloadVideo(_videoUrl!),
                  loading: _isDownloading,
                  isActive: isDownloaded,
                ),
                const SizedBox(width: 16),
                _buildIconButton(
                  icon: Icons.play_circle_rounded,
                  color: Colors.purple,
                  onPressed: () => _openVideo(_videoUrl!),
                ),
                const SizedBox(width: 16),
                _buildIconButton(
                  icon: isAddedToCollection ? Icons.favorite : Icons.favorite_border_rounded,
                  color: isAddedToCollection ? Colors.red : Colors.grey,
                  onPressed: _addToCollection,
                  loading: _isAddingToCollection,
                  isActive: isAddedToCollection,
                ),
                const SizedBox(width: 16),
                _buildIconButton(
                  icon: Icons.refresh_rounded,
                  color: Colors.orange,
                  onPressed: _resetGeneration,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadVideo(String url) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      // Request storage permissions
      final storageStatus = await Permission.storage.request();
      final mediaStatus = await Permission.mediaLibrary.request();
      final externalStatus = await Permission.manageExternalStorage.request();
      
      if (!storageStatus.isGranted || !mediaStatus.isGranted || !externalStatus.isGranted) {
        throw Exception('Storage permissions are required to download videos');
      }

      // Create download directory
      Directory? baseDir;
      if (Platform.isAndroid) {
        baseDir = Directory('/storage/emulated/0/Download/CoreAIStudios');
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        baseDir = Directory('${appDir.path}/Downloads/CoreAIStudios');
      }

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'video_$timestamp.mp4';
      final file = File('${baseDir.path}/$filename');

      // Download with progress tracking
      final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
      final contentLength = response.contentLength ?? 0;
      final sink = file.openWrite();
      
      int received = 0;
      await response.stream.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (mounted && contentLength > 0) {
          setState(() => _downloadProgress = received / contentLength);
        }
      }).asFuture();
      
      await sink.close();

      // Save to gallery
      await Gal.putVideo(file.path);

      // Update Firestore document
      await widget.reference.update({
        'metadata': {
          ...widget.request.metadata ?? {},
          'isDownloaded': true,
          'downloadPath': file.path,
          'downloadedAt': FieldValue.serverTimestamp(),
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Video downloaded successfully'),
                ),
                TextButton(
                  onPressed: () => _openDownloadedFile(file.path),
                  child: const Text('OPEN', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.toString()),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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

  Future<void> _openDownloadedFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await launchUrl(Uri.file(path));
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool loading = false,
    bool isActive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: loading ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.2) : color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? color : color.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isActive ? color.withOpacity(0.2) : color.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
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

  void _resetGeneration() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Reset Generation',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will clear the current output. If not saved, the generated content will be lost. Continue?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _videoUrl = null;
                _isVideoReady = false;
                _fileName = null;
                _currentStatus = '';
                _hasError = false;
                _errorMessage = null;
                _showCompletionTick = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCollection() async {
    if (_isAddingToCollection) return;
    
    setState(() => _isAddingToCollection = true);
    
    try {
      final videoUrl = _videoUrl;
      if (videoUrl == null) throw Exception('Video URL not found');

      final userId = widget.request.userId;
      if (userId == null) throw Exception('User ID not found');

      // Create collection document
      final userCollectionsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('collections');

      final collectionDoc = await userCollectionsRef.add({
        'type': 'video',
        'sourceUrl': videoUrl,
        'prompt': widget.request.prompt,
        'createdAt': FieldValue.serverTimestamp(),
        'generationId': widget.request.id,
        'metadata': {
          'thumbnailUrl': widget.request.result?['thumbnail_url'] ?? 
                         widget.request.result?['preview_url'],
          'postId': widget.request.result?['post_ids']?[0],
          'videoId': widget.request.result?['video_id'],
          'originalRequest': widget.request.toMap(),
        },
        'status': 'active',
        'lastModified': FieldValue.serverTimestamp(),
      });

      // Update request metadata
      await widget.reference.update({
        'metadata': {
          ...widget.request.metadata ?? {},
          'isAddedToCollection': true,
          'collectionId': collectionDoc.id,
          'addedToCollectionAt': FieldValue.serverTimestamp(),
        }
      });

      if (mounted) {
        setState(() => _isAddingToCollection = false);
        widget.onCollectionToggle?.call(true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.favorite, color: Colors.red[400]),
                const SizedBox(width: 12),
                const Text('Added to your collection'),
              ],
            ),
            backgroundColor: Colors.grey[900],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error adding to collection: $e');
      if (mounted) {
        setState(() => _isAddingToCollection = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Failed to add to collection: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openVideo(String url) async {
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      debugPrint('Error opening video: $e');
    }
  }
} 