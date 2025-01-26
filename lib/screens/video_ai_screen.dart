import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/generation_progress_bar.dart';
import '../widgets/ai_prompt_input.dart';
import '../models/generation_type.dart';
import '../services/generation_request_service.dart';
import '../services/token_balance_service.dart';
import '../widgets/animated_icon_button.dart';
import '../services/video_player_service.dart';

class VideoAIScreen extends ConsumerStatefulWidget {
  const VideoAIScreen({super.key});

  @override
  ConsumerState<VideoAIScreen> createState() => _VideoAIScreenState();
}

class _VideoAIScreenState extends ConsumerState<VideoAIScreen> {
  final _requestService = GenerationRequestService();
  String? _currentRequestId;
  bool _isLoading = false;

  void _showTips() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.grey[900],
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates, color: Colors.amber[400]),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Video Generation Tips',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTip(
                        icon: Icons.style,
                        title: 'Style and Mood',
                        description: 'Use descriptive terms like "cinematic", "dramatic", or "upbeat" to set the tone.',
                      ),
                      _buildTip(
                        icon: Icons.video_settings,
                        title: 'Scene Elements',
                        description: 'Specify key visual elements, actions, and the flow of scenes.',
                      ),
                      _buildTip(
                        icon: Icons.timer,
                        title: 'Timing and Flow',
                        description: 'Describe how scenes should transition and the overall pacing.',
                      ),
                      _buildTip(
                        icon: Icons.music_note,
                        title: 'Audio Elements',
                        description: 'Mention preferred background music style or specific sound effects.',
                      ),
                      _buildTip(
                        icon: Icons.high_quality,
                        title: 'Quality Focus',
                        description: 'Include specific quality requirements like resolution or frame rate.',
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

  Widget _buildTip({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.amber[400], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentRequest = ref.watch(
      generationRequestProvider(_currentRequestId ?? ''),
    );
    final userRequests = ref.watch(userRequestsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            const Icon(Icons.movie_creation, size: 20),
            const SizedBox(width: 8),
            const Text('Video Generation'),
          ],
        ),
        actions: [
          AnimatedIconButton(
            icon: Icons.tips_and_updates,
            color: Colors.amber[400]!,
            onPressed: _showTips,
            tooltip: 'Generation Tips',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AIPromptInput(
                    type: GenerationType.video,
                    hintText: 'Describe your video...',
                    isLoading: _isLoading,
                    submitIcon: Icons.movie_creation,
                    submitLabel: 'Generate Video',
                    accentColor: Colors.blue,
                    onSubmit: (prompt) async {
                      setState(() => _isLoading = true);
                      try {
                        final requestId = await _requestService.submitRequest(
                          context: context,
                          prompt: prompt,
                          type: GenerationType.video,
                          metadata: const {},
                        );
                        if (requestId != null) {
                          setState(() => _currentRequestId = requestId);
                        }
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    },
                  ),
                  if (_currentRequestId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: currentRequest.when(
                        data: (request) => request != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GenerationProgressBar(
                                    progress: (request.progress ?? 0) / 100,
                                    status: request.statusText,
                                    showLabel: true,
                                  ),
                                  if (request.result != null && request.isCompleted) ...[
                                    const SizedBox(height: 16),
                                    AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey[900],
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                request.result!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Center(
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.error_outline,
                                                        color: Colors.red[400],
                                                        size: 32,
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Failed to load preview',
                                                        style: TextStyle(
                                                          color: Colors.red[400],
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton.filled(
                                                  onPressed: () => VideoPlayerService.playVideo(
                                                    request.result!,
                                                    context,
                                                  ),
                                                  icon: const Icon(Icons.play_arrow),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.blue,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton.filled(
                                                  onPressed: () => VideoPlayerService.downloadVideo(
                                                    request.result!,
                                                    context,
                                                  ),
                                                  icon: const Icon(Icons.download),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : const SizedBox.shrink(),
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red[400], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Failed to load request: ${error.toString()}',
                                  style: TextStyle(color: Colors.red[400], fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Text(
                    'Previous Generations',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: userRequests.when(
                      data: (requests) => Text(
                        requests.where((r) => r.type == GenerationType.video).length.toString(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      loading: () => const Text('...', style: TextStyle(color: Colors.white70)),
                      error: (_, __) => const Text('?', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(top: 16)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: userRequests.when(
              data: (requests) {
                final videoRequests = requests
                    .where((r) => r.type == GenerationType.video)
                    .where((r) => r.id != _currentRequestId)
                    .toList();

                if (videoRequests.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.movie_creation_outlined, 
                            color: Colors.grey[700],
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No previous generations',
                            style: TextStyle(
                              color: Colors.grey[600],
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
                      final request = videoRequests[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.grey[900],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: Icon(
                                request.isCompleted
                                    ? Icons.check_circle
                                    : request.isFailed
                                        ? Icons.error
                                        : Icons.pending,
                                color: request.isCompleted
                                    ? Colors.green
                                    : request.isFailed
                                        ? Colors.red
                                        : Colors.orange,
                              ),
                              title: Text(
                                request.prompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: request.isCompleted
                                            ? Colors.green.withOpacity(0.2)
                                            : request.isFailed
                                                ? Colors.red.withOpacity(0.2)
                                                : Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        request.statusText,
                                        style: TextStyle(
                                          color: request.isCompleted
                                              ? Colors.green[300]
                                              : request.isFailed
                                                  ? Colors.red[300]
                                                  : Colors.orange[300],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (request.result != null && request.isCompleted)
                              Container(
                                height: 120,
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[850],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        request.result!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.error_outline,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton.filled(
                                          onPressed: () => VideoPlayerService.playVideo(
                                            request.result!,
                                            context,
                                          ),
                                          icon: const Icon(Icons.play_arrow, size: 20),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                            padding: const EdgeInsets.all(8),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton.filled(
                                          onPressed: () => VideoPlayerService.downloadVideo(
                                            request.result!,
                                            context,
                                          ),
                                          icon: const Icon(Icons.download, size: 20),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            padding: const EdgeInsets.all(8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                    childCount: videoRequests.length,
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[400], size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load requests',
                        style: TextStyle(color: Colors.red[400], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: TextStyle(color: Colors.red[400], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
} 