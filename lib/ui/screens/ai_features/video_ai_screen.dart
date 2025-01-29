import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/video_generation_service.dart';
import '../../../services/notification_service.dart';
import '../../widgets/ai_prompt_input.dart';
import '../../../models/generation_request.dart';
import '../../../models/generation_type.dart';
import '../../widgets/generation_request_card.dart';
import '../../../services/predis_video_service.dart';
import '../../widgets/generation_progress_bar.dart';
import '../../widgets/ai_app_bar.dart';
import 'package:flutter_animated_loadingkit/flutter_animated_loadingkit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/token_balance_service.dart';
import '../../widgets/loading_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/tips_section.dart';
import '../../../providers/token_provider.dart';
import '../../../services/generation_request_service.dart';

final videoServiceProvider = Provider((ref) => VideoGenerationService());
final generationRequestServiceProvider = Provider((ref) => GenerationRequestService());

final recentVideosProvider = StreamProvider.autoDispose<List<GenerationRequest>>((ref) async* {
  final predisService = PredisVideoService();
  final navigator = ref.read(navigatorKeyProvider);
  
  while (true) {
    try {
      if (navigator.currentContext != null) {
        final videos = await predisService.getRecentVideos(
          context: navigator.currentContext!,
          limit: 5,
        );
        yield videos;
      }
    } catch (e) {
      debugPrint('Error fetching videos: $e');
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
  const VideoAIScreen({super.key});

  @override
  ConsumerState<VideoAIScreen> createState() => _VideoAIScreenState();
}

class _VideoAIScreenState extends ConsumerState<VideoAIScreen> {
  final _scrollController = ScrollController();
  final _predisService = PredisVideoService();
  String? _currentRequestId;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentVideos = ref.watch(recentVideosProvider);

    // Show notification when service changes
    ref.listen<VideoGenerationService>(videoServiceProvider, (previous, next) {
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
                            onSubmit: _generateVideo,
                            isLoading: _currentRequestId != null,
                            hintText: 'Describe the video you want to create...',
                            submitIcon: Icons.movie_creation,
                            submitLabel: 'Generate Video',
                            accentColor: Colors.red.shade400,
                            focusNode: _focusNode,
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
              recentVideos.when(
                data: (videos) {
                  if (videos.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: 0.8,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.movie_creation_outlined,
                                size: 48,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No videos generated yet',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your generated videos will appear here',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final request = videos[index];
                        return AnimatedSlide(
                          duration: Duration(milliseconds: 300 + (index * 100)),
                          offset: Offset.zero,
                          child: AnimatedOpacity(
                            duration: Duration(milliseconds: 300 + (index * 100)),
                            opacity: 1.0,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: GenerationRequestCard(
                                request: request,
                                showProgress: true,
                                showControls: true,
                                isExpanded: true,
                                onRetry: () => _predisService.retryRequest(
                                  request.id,
                                  context,
                                ),
                                onCancel: () => _predisService.cancelRequest(
                                  request.id,
                                  context,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: videos.length,
                    ),
                  );
                },
                loading: () => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: AnimatedLoadingSideWaySurge(
                        expandWidth: 24,
                        borderWidth: 2,
                        borderColor: Colors.red.shade400,
                        speed: const Duration(milliseconds: 800),
                      ),
                    ),
                  ),
                ),
                error: (error, stack) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: 0.8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load videos',
                            style: TextStyle(
                              color: Colors.red[400],
                              fontSize: 16,
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                                left: 32,
                                right: 32,
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

  void _showTipsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade400.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: Colors.amber[400],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Video Generation Tips',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTipSection(
                        'Scene Description',
                        [
                          'Be specific about scene details and actions',
                          'Describe the setting and environment',
                          'Specify time of day and weather if relevant',
                          'Include character descriptions and emotions',
                        ],
                        Icons.movie_creation_outlined,
                      ),
                      const SizedBox(height: 24),
                      _buildTipSection(
                        'Technical Aspects',
                        [
                          'Specify camera angles and movements',
                          'Describe lighting conditions',
                          'Mention any special effects needed',
                          'Include transition preferences',
                        ],
                        Icons.camera_alt_outlined,
                      ),
                      const SizedBox(height: 24),
                      _buildTipSection(
                        'Style & Mood',
                        [
                          'Define the overall mood or atmosphere',
                          'Specify artistic style (realistic, animated, etc.)',
                          'Include color palette preferences',
                          'Mention any reference styles or inspirations',
                        ],
                        Icons.palette_outlined,
                      ),
                      const SizedBox(height: 24),
                      _buildTipSection(
                        'Best Practices',
                        [
                          'Keep prompts clear and focused',
                          'Avoid contradictory instructions',
                          'Use simple language and avoid jargon',
                          'Break complex scenes into separate generations',
                        ],
                        Icons.tips_and_updates_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipSection(String title, List<String> tips, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.red[400],
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...tips.map((tip) => Padding(
          padding: const EdgeInsets.only(left: 32, bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: Colors.green[400],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tip,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[300],
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ],
    );
  }

  Future<void> _generateVideo(String prompt) async {
    // Unfocus keyboard
    _focusNode.unfocus();
    
    try {
      final requestId = await _predisService.generateVideo(
        context: context,
        prompt: prompt,
      );

      if (requestId != null) {
        setState(() => _currentRequestId = requestId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentRequestId = null);
      }
      rethrow;
    }
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
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GenerationProgressBar(
                progress: (request.progress ?? 0) / 100,
                status: request.statusText ?? 'Processing...',
                showLabel: true,
                height: 4,
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }
} 