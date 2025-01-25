import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/video_generation_service.dart';
import '../../widgets/error_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/token_balance_service.dart';
import '../../widgets/loading_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/notification_service.dart';
import '../../widgets/custom_error_popup.dart';
import '../../../services/downloads_service.dart';
import '../../widgets/ai_prompt_input.dart';
import '../../widgets/tips_section.dart';
import '../../../providers/token_provider.dart';

final videoServiceProvider = Provider((ref) => VideoGenerationService());

enum VideoModel {
  predisShort,
  predisLong,
}

class VideoAIScreen extends ConsumerStatefulWidget {
  const VideoAIScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<VideoAIScreen> createState() => _VideoAIScreenState();
}

class _VideoAIScreenState extends ConsumerState<VideoAIScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _promptController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  bool _isGenerating = false;
  bool _isLoadingVideos = false;
  String? _currentVideoId;
  final List<Map<String, dynamic>> _videoList = [];
  int _currentPage = 1;
  bool _hasMoreVideos = true;
  Map<String, double> _downloadProgress = {};
  Map<String, String> _downloadedFiles = {};
  final VideoGenerationService _videoService = VideoGenerationService();
  final TokenBalanceService _tokenService = TokenBalanceService();
  Timer? _statusCheckTimer;
  final int _tokenCost = 50; // Cost per video generation
  final int _maxPromptLength = 500; // Default max prompt length
  bool _isPromptTooLong = false;
  static const int _videosPerPage = 5;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _promptController.addListener(_checkPromptLength);
    _loadVideos();
  }

  void _checkPromptLength() {
    final isPromptTooLong = _promptController.text.length > _maxPromptLength;
    if (isPromptTooLong != _isPromptTooLong) {
      setState(() => _isPromptTooLong = isPromptTooLong);
    }
  }

  @override
  void dispose() {
    _promptController.removeListener(_checkPromptLength);
    _promptController.dispose();
    _animationController.dispose();
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVideos() async {
    if (_isLoadingVideos || !_hasMoreVideos) return;

    setState(() => _isLoadingVideos = true);

    try {
      final response = await _videoService.listVideos(
        context: context,
        page: _currentPage,
        limit: _videosPerPage,
      );

      setState(() {
        if (response['data'].isEmpty) {
          _hasMoreVideos = false;
        } else {
          // Insert new videos at the beginning of the list
          _videoList.insertAll(0, List<Map<String, dynamic>>.from(response['data']));
          _currentPage++;
        }
      });
    } catch (e) {
      NotificationService.showError(
        title: 'Error',
        message: 'Failed to load videos. Please try again.',
        context: context,
      );
    } finally {
      setState(() => _isLoadingVideos = false);
    }
  }

  Future<void> _generateVideo(String prompt) async {
    setState(() {
      _isGenerating = true;
      _currentVideoId = null;
    });

    try {
      final result = await _videoService.generateVideo(
        prompt: prompt,
        context: context,
      );

      setState(() => _currentVideoId = result['post_id']);

      // Start checking status
      _checkVideoStatus();
    } catch (e) {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _checkVideoStatus() async {
    if (_currentVideoId == null || !_isGenerating) return;

    try {
      final status = await _videoService.getVideoStatus(_currentVideoId!, context);

      if (status['status'] == 'completed') {
        setState(() => _isGenerating = false);
        
        // Reset page counter and reload videos to show the new one
        setState(() {
          _currentPage = 1;
          _videoList.clear();
        });
        
        await _loadVideos();
        
        NotificationService.showSuccess(
          title: 'Success',
          message: 'Video generated successfully!',
          context: context,
        );
      } else if (status['status'] == 'failed') {
        setState(() => _isGenerating = false);
        NotificationService.showError(
          title: 'Generation Failed',
          message: status['error'] ?? 'Failed to generate video. Please try again.',
          context: context,
        );
      } else {
        // Continue checking status
        Future.delayed(const Duration(seconds: 5), _checkVideoStatus);
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      NotificationService.showError(
        title: 'Error',
        message: 'Failed to check video status. Please try again.',
        context: context,
      );
    }
  }

  Future<void> _cancelGeneration() async {
    if (_currentVideoId == null) return;

    try {
      await _videoService.cancelGeneration(_currentVideoId!, context);
      setState(() {
        _isGenerating = false;
        _currentVideoId = null;
      });
    } catch (e) {
      NotificationService.showError(
        title: 'Error',
        message: 'Failed to cancel generation. Please try again.',
        context: context,
      );
    }
  }

  Future<void> _downloadVideo(String url, String caption) async {
    try {
      await _videoService.downloadVideo(
        url,
        context,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[url] = progress;
          });
        },
      );

      setState(() {
        _downloadProgress.remove(url);
      });
    } catch (e) {
      setState(() {
        _downloadProgress.remove(url);
      });
      NotificationService.showError(
        title: 'Download Failed',
        message: 'Failed to download video. Please try again.',
        context: context,
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'processing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildVideoCard(Map<String, dynamic> video) {
    final status = video['status'] ?? 'unknown';
    final url = video['video_url'] ?? '';
    final caption = video['caption'] ?? '';
    final progress = _downloadProgress[url] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (video['thumbnail_url'] != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                video['thumbnail_url'],
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: double.infinity,
                    height: 200,
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.movie,
                      size: 64,
                      color: Colors.white54,
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getStatusColor(status).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status.toLowerCase() == 'completed'
                                ? Icons.check_circle
                                : status.toLowerCase() == 'failed'
                                    ? Icons.error
                                    : Icons.pending,
                            size: 16,
                            color: _getStatusColor(status),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: _getStatusColor(status),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (status.toLowerCase() == 'completed')
                      TextButton.icon(
                        onPressed: progress > 0
                            ? null
                            : () => _downloadVideo(url, caption),
                        icon: progress > 0
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 2,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.blue),
                                ),
                              )
                            : const Icon(Icons.download),
                        label: Text(
                          progress > 0
                              ? '${(progress * 100).toInt()}%'
                              : 'Download',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                  ],
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Video Generation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // Prompt Input
                      AIPromptInput(
                        type: AIGenerationType.video,
                        onSubmit: _generateVideo,
                        isLoading: _isGenerating,
                        hintText: 'Describe the video you want to generate...',
                        submitIcon: Icons.movie_creation_rounded,
                        submitLabel: 'Generate Video',
                        accentColor: Colors.purple,
                      ),
                      const SizedBox(height: 24),
                      // Tips Section
                      TipsSection(
                        title: 'Video Generation Tips',
                        icon: Icons.lightbulb_outline,
                        accentColor: Colors.amber,
                        isCollapsible: true,
                        tips: const [
                          'Be specific about the scene, actions, and mood you want.',
                          'Include details about lighting, camera angles, and movement.',
                          'Specify any particular style or visual effects desired.',
                          'Keep prompts clear and concise for best results.',
                          'Avoid complex narratives or multiple scene changes.',
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Generated Videos
                      if (_videoList.isNotEmpty) ...[
                        const Text(
                          'Your Generated Videos',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._videoList
                            .take(_videosPerPage)
                            .map(_buildVideoCard)
                            .toList(),
                        if (_hasMoreVideos)
                          Center(
                            child: TextButton(
                              onPressed:
                                  _isLoadingVideos ? null : () => _loadVideos(),
                              child: _isLoadingVideos
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Load More'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Loading Overlay
            if (_isGenerating)
              GestureDetector(
                onTap: _cancelGeneration,
                child: LoadingOverlay(
                  message: 'Generating Video',
                  subMessage: 'This may take a few minutes. Please wait or tap to cancel.',
                  isLoading: true,
                  child: const SizedBox.shrink(),
                  useGalaxyAnimation: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotatingIcon(Widget icon) {
    return RotationTransition(
      turns: _animationController,
      child: icon,
    );
  }
} 