import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../../services/video_generation_service.dart';
import '../../../services/notification_service.dart';
import '../../widgets/ai_prompt_input.dart';
import '../../../models/generation_request.dart';
import '../../../models/generation_type.dart';
import '../../widgets/generation_request_card.dart';
import '../../../services/predis_video_service.dart';
import '../../widgets/generation_progress_bar.dart';
import '../../widgets/ai_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/token_balance_service.dart';
import '../../widgets/loading_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/tips_section.dart';
import '../../../providers/token_provider.dart';
import '../../../services/generation_request_service.dart';
import '../../../config/ai_service_config.dart';

final videoServiceProvider = Provider<PredisVideoService>((ref) => PredisVideoService(
  firestore: FirebaseFirestore.instance,
  auth: FirebaseAuth.instance,
  config: AIServiceFactory.getConfig(AIServiceType.predisAI),
));

final generationRequestServiceProvider = Provider((ref) => GenerationRequestService());

final recentVideosProvider = StreamProvider.autoDispose<List<GenerationRequest>>((ref) async* {
  debugPrint('[VideoAI] Starting recent videos stream');
  final predisService = ref.watch(videoServiceProvider);
  final navigator = ref.read(navigatorKeyProvider);
  
  while (true) {
    try {
      if (navigator.currentContext != null) {
        debugPrint('[VideoAI] Fetching recent videos...');
        final videos = await predisService.getRecentVideos(
          context: navigator.currentContext!,
          limit: 5,
        );
        debugPrint('[VideoAI] Fetched ${videos.length} videos successfully');
        yield videos;
      }
    } catch (e, stack) {
      debugPrint('[VideoAI] Error fetching videos: $e\n$stack');
      rethrow;
    }
    await Future.delayed(const Duration(seconds: 10));
  }
});

final navigatorKeyProvider = Provider((ref) => GlobalKey<NavigatorState>());

final generationRequestProvider = StreamProvider.family<GenerationRequest?, String>((ref, requestId) async* {
  final snapshot = await FirebaseFirestore.instance
      .collection('generation_queue')
      .doc(requestId)
      .get();

  if (!snapshot.exists) {
    yield null;
    return;
  }

  yield GenerationRequest.fromMap(snapshot.data()!);

  // Listen to real-time updates
  yield* FirebaseFirestore.instance
      .collection('generation_queue')
      .doc(requestId)
      .snapshots()
      .map((snapshot) => snapshot.exists 
          ? GenerationRequest.fromMap(snapshot.data()!)
          : null);
});

class VideoAIScreen extends ConsumerStatefulWidget {
  const VideoAIScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<VideoAIScreen> createState() => _VideoAIScreenState();
}

class _VideoAIScreenState extends ConsumerState<VideoAIScreen> {
  final _scrollController = ScrollController();
  late final PredisVideoService _predisService;
  String? _currentRequestId;
  final _focusNode = FocusNode();
  bool _isPromptValid = false;
  String _prompt = '';
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _predisService = PredisVideoService(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
      config: AIServiceFactory.getConfig(AIServiceType.predisAI),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentVideos = ref.watch(recentVideosProvider);
    final videoService = ref.watch(videoServiceProvider);

    // Show notification when service changes
    ref.listen(videoServiceProvider, (previous, next) {
      NotificationService.showSuccess(
        context: context,
        title: 'Service Ready',
        message: 'Video generation service is ready',
        playSound: true,
      );
    });

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AIAppBar(
          type: GenerationType.video,
          title: 'Video Gen',
          onTipsPressed: _showTipsDialog,
          onBackPressed: () => Navigator.pop(context),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: CustomScrollView(
            key: ValueKey(recentVideos.hashCode),
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: 'video_input',
                        child: Material(
                          type: MaterialType.transparency,
                          child: AIPromptInput(
                            type: GenerationType.video,
                            onSubmit: _handleGenerate,
                            isLoading: _currentRequestId != null,
                            hintText: 'Describe the video you want to create...',
                            submitIcon: Icons.movie_creation,
                            submitLabel: 'Generate Video',
                            accentColor: Colors.red.shade400,
                            focusNode: _focusNode,
                            onChanged: (value) {
                              setState(() {
                                _prompt = value;
                                _isPromptValid = value.trim().length >= 10;
                              });
                            },
                            isEnabled: _isPromptValid && _currentRequestId == null,
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: _buildProgressBar(),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.history,
                            size: 20,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Recent Generations',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: recentVideos.when(
                  data: (videos) => videos.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.movie_creation_outlined,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No videos generated yet',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => GenerationRequestCard(
                              request: videos[index],
                              onRetry: () => _predisService.retryRequest(
                                videos[index].id,
                                context,
                              ),
                              onCancel: () => _predisService.cancelRequest(
                                videos[index].id,
                                context,
                              ),
                            ),
                            childCount: videos.length,
                          ),
                        ),
                  loading: () => SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: LoadingAnimationWidget.dotsTriangle(
                        color: Colors.red.shade400,
                        size: 50,
                      ),
                    ),
                  ),
                  error: (error, stack) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.shade400,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load recent videos',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 8,
                              ),
                              child: Text(
                                error.toString(),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () => ref.refresh(recentVideosProvider),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    if (_currentRequestId == null) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, child) {
        final requestAsync = ref.watch(
          generationRequestProvider(_currentRequestId!),
        );

        return requestAsync.when(
          data: (request) {
            if (request?.status == GenerationStatus.completed ||
                request?.status == GenerationStatus.failed ||
                request?.status == GenerationStatus.cancelled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _currentRequestId = null);
                }
              });
            }
            
            if (request == null) return const SizedBox.shrink();
            
            return Container(
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.shade400.withOpacity(0.1),
                    Colors.red.shade600.withOpacity(0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getStatusIcon(request.status),
                        color: _getStatusColor(request.status),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        request.statusText ?? 'Processing...',
                        style: TextStyle(
                          color: _getStatusColor(request.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (request.status == GenerationStatus.queued ||
                          request.status == GenerationStatus.pending)
                        Text(
                          'In Queue',
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (request.progress ?? 0) / 100,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getStatusColor(request.status),
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.queue;
      case 'processing':
        return Icons.movie_creation_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      case 'queued':
        return Icons.queue;
      default:
        return Icons.pending_outlined;
    }
  }

  void _showTipsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: TipsSection(
          title: 'Video Generation Tips',
          icon: Icons.movie_creation_outlined,
          accentColor: Colors.red.shade400,
          closeIconGradient: LinearGradient(
            colors: [
              Colors.red.shade300,
              Colors.red.shade600,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          tips: const [
            'Predis AI excels at creating short-form video content like ads and social media posts',
            'Keep your prompts clear and specific about the video style, mood, and target audience',
            'Optimal video length is 15-60 seconds for best results',
            'Include key information like brand message, target audience, and desired call-to-action',
            'Specify if you want text overlays, music, or specific visual elements',
            'For best results, mention the platform (Instagram, TikTok, etc.) in your prompt',
            'Use industry-specific terms to get more relevant content',
          ],
        ),
      ),
    );
  }

  Future<void> _handleGenerate(String prompt) async {
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _prompt = prompt;
    });

    try {
      final videoService = ref.read(videoServiceProvider);
      final requestId = await videoService.generateVideo(
        prompt,
        {
          'type': 'video',
          'prompt': prompt,
          'status': 'pending',
        },
      );

      if (requestId != null) {
        setState(() {
          _currentRequestId = requestId;
        });
      } else {
        throw Exception('Failed to start video generation');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Widget _buildStatusIndicator(GenerationRequest request) {
    if (request.status == 'pending') {
      return _buildPendingIndicator();
    } else if (request.status == 'processing') {
      return _buildProcessingIndicator();
    } else if (request.status == 'completed') {
      return _buildCompletedIndicator();
    } else if (request.status == 'failed') {
      return _buildFailedIndicator();
    }
    return const SizedBox();
  }

  Widget _buildPendingIndicator() {
    // Implementation of _buildPendingIndicator
    return const SizedBox();
  }

  Widget _buildProcessingIndicator() {
    // Implementation of _buildProcessingIndicator
    return const SizedBox();
  }

  Widget _buildCompletedIndicator() {
    // Implementation of _buildCompletedIndicator
    return const SizedBox();
  }

  Widget _buildFailedIndicator() {
    // Implementation of _buildFailedIndicator
    return const SizedBox();
  }

  Widget _buildStatusBadge(GenerationRequest request) {
    final color = _getStatusColor(request.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(
          red: color.red.toDouble(),
          green: color.green.toDouble(),
          blue: color.blue.toDouble(),
          alpha: 25.5, // 0.1 * 255
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(
            red: color.red.toDouble(),
            green: color.green.toDouble(),
            blue: color.blue.toDouble(),
            alpha: 127.5, // 0.5 * 255
          ),
        ),
      ),
      child: Text(
        request.statusText,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
} 