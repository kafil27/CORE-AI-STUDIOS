import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/video_generation_service.dart';
import '../widgets/ai_prompt_input.dart';
import '../../../services/generation_request_service.dart';
import '../../../models/generation_request.dart';
import '../../../models/generation_type.dart';
import '../widgets/generation_request_card.dart';
import '../../../services/predis_video_service.dart';

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

class VideoAIScreen extends ConsumerStatefulWidget {
  const VideoAIScreen({super.key});

  @override
  ConsumerState<VideoAIScreen> createState() => _VideoAIScreenState();
}

class _VideoAIScreenState extends ConsumerState<VideoAIScreen> {
  final _scrollController = ScrollController();
  final _predisService = PredisVideoService();
  bool _isLoading = false;

  void _showTipsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lightbulb_outline, color: Colors.amber[400]),
            const SizedBox(width: 8),
            const Text('Video Generation Tips'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTip('Be specific about scene details and actions'),
              _buildTip('Describe lighting and camera movements'),
              _buildTip('Specify mood and atmosphere'),
              _buildTip('Keep prompts clear and focused'),
              _buildTip('Include any specific style preferences'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String tip) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: Colors.green[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tip),
          ),
        ],
      ),
    );
  }

  Future<void> _generateVideo(String prompt) async {
    setState(() => _isLoading = true);

    try {
      await _predisService.generateVideo(
        context: context,
        prompt: prompt,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentVideos = ref.watch(recentVideosProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Video Gen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: () => Navigator.pushNamed(context, '/image-gen'),
          ),
          IconButton(
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: _showTipsDialog,
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AIPromptInput(
                    type: GenerationType.video,
                    onSubmit: _generateVideo,
                    isLoading: _isLoading,
                    hintText: 'Describe the video you want to create...',
                    submitIcon: Icons.movie_creation,
                    submitLabel: 'Generate Video',
                    accentColor: Colors.blue,
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
                  const Text(
                    'Recent Generations',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          recentVideos.when(
            data: (videos) {
              if (videos.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.movie_creation_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No videos generated yet',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final request = videos[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: GenerationRequestCard(
                        request: request,
                        showProgress: true,
                        showControls: true,
                        isExpanded: true,
                      ),
                    );
                  },
                  childCount: videos.length,
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load videos',
                      style: TextStyle(color: Colors.red[400], fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 