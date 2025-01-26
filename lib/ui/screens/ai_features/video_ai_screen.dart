import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/video_generation_service.dart';
import '../../../services/token_balance_service.dart';
import '../../widgets/loading_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/notification_service.dart';
import '../../widgets/ai_prompt_input.dart';
import '../../widgets/tips_section.dart';
import '../../../providers/token_provider.dart';
import '../../../services/generation_request_service.dart';
import '../../../models/generation_request.dart';
import '../../../models/generation_type.dart';
import '../../widgets/generation_request_card.dart';

final videoServiceProvider = Provider((ref) => VideoGenerationService());
final generationRequestServiceProvider = Provider((ref) => GenerationRequestService());

enum VideoModel {
  predisShort,
  predisLong,
}

class VideoAIScreen extends ConsumerStatefulWidget {
  const VideoAIScreen({super.key});

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
  final GenerationRequestService _requestService = GenerationRequestService();
  String? _currentRequestId;

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
    final requestId = await _requestService.submitRequest(
      context: context,
      prompt: prompt,
      type: GenerationType.video,
      metadata: {
        'duration': 'short', // or 'long'
        'quality': 'high',
        'width': 1024,
        'height': 1024,
      },
    );

    if (requestId != null) {
      setState(() => _currentRequestId = requestId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRequest = _currentRequestId != null
        ? ref.watch(generationRequestProvider(_currentRequestId!))
        : const AsyncValue.data(null);
    
    final userRequests = ref.watch(userRequestsProvider);

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
                        isLoading: currentRequest.when(
                          data: (request) => request?.isInProgress ?? false,
                          loading: () => true,
                          error: (_, __) => false,
                        ),
                        hintText: 'Describe the video you want to generate...',
                        submitIcon: Icons.movie_creation_rounded,
                        submitLabel: 'Generate Video',
                        accentColor: Colors.purple,
                      ),
                      const SizedBox(height: 24),
                      // Tips Section
                      const TipsSection(
                        title: 'Video Generation Tips',
                        icon: Icons.lightbulb_outline,
                        accentColor: Colors.amber,
                        isCollapsible: true,
                        tips: [
                          'Be specific about the scene, actions, and mood you want.',
                          'Include details about lighting, camera angles, and movement.',
                          'Specify any particular style or visual effects desired.',
                          'Keep prompts clear and concise for best results.',
                          'Avoid complex narratives or multiple scene changes.',
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Current Generation
                      if (currentRequest.when(
                        data: (request) => request != null,
                        loading: () => false,
                        error: (_, __) => false,
                      )) ...[
                        const Text(
                          'Current Generation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        currentRequest.when(
                          data: (request) => request != null
                              ? GenerationRequestCard(
                                  request: request,
                                  onCancel: () => _requestService.cancelRequest(
                                    request.id,
                                    context,
                                  ),
                                  onRetry: () => _requestService.retryRequest(
                                    request.id,
                                    context,
                                  ),
                                  isExpanded: true,
                                )
                              : const SizedBox.shrink(),
                          loading: () => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          error: (error, _) => Text(
                            'Error: $error',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Previous Generations
                      userRequests.when(
                        data: (requests) {
                          final videoRequests = requests
                              .where((r) => r.type == GenerationType.video)
                              .where((r) => r.id != _currentRequestId)
                              .toList();

                          if (videoRequests.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Previous Generations',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...videoRequests.map((request) =>
                                GenerationRequestCard(
                                  request: request,
                                  onRetry: request.canRetry
                                      ? () => _requestService.retryRequest(
                                          request.id,
                                          context,
                                        )
                                      : null,
                                  onCancel: request.canCancel
                                      ? () => _requestService.cancelRequest(
                                          request.id,
                                          context,
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (error, _) => Text(
                          'Error: $error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Loading Overlay
            currentRequest.when(
              data: (request) => request?.isInProgress ?? false
                  ? GestureDetector(
                      onTap: () => _requestService.cancelRequest(
                        request!.id,
                        context,
                      ),
                      child: LoadingOverlay(
                        message: 'Generating Video',
                        subMessage: request?.progress != null
                            ? 'Progress: ${request!.progress}%'
                            : 'This may take a few minutes. Please wait or tap to cancel.',
                        isLoading: true,
                        child: const SizedBox.shrink(),
                        useGalaxyAnimation: true,
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
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