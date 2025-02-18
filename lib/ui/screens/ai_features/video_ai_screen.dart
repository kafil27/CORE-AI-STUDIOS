import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../../services/notification_service.dart';
import '../../widgets/ai_prompt_input.dart';
import '../../../models/generation_request.dart';
import '../../../models/generation_type.dart';
import '../../widgets/generation_request_card.dart';
import '../../../services/predis_video_service.dart';
import '../../widgets/ai_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/tips_section.dart';
import '../../../services/generation_request_service.dart';
import '../../../config/ai_service_config.dart';

// State class for video generation
class VideoGenerationState {
  final bool isGenerating;
  final bool showOutput;
  final String? currentRequestId;
  final GenerationRequest? currentRequest;
  final String? generatedVideoUrl;
  final bool isAddedToCollection;
  final String promptText;
  final bool isPromptValid;
  final String? error;
  final bool isTogglingCollection;
  final bool isCompleted;

  const VideoGenerationState({
    this.isGenerating = false,
    this.showOutput = false,
    this.currentRequestId,
    this.currentRequest,
    this.generatedVideoUrl,
    this.isAddedToCollection = false,
    this.promptText = '',
    this.isPromptValid = false,
    this.error,
    this.isTogglingCollection = false,
    this.isCompleted = false,
  });

  VideoGenerationState copyWith({
    bool? isGenerating,
    bool? showOutput,
    String? currentRequestId,
    GenerationRequest? currentRequest,
    String? generatedVideoUrl,
    bool? isAddedToCollection,
    String? promptText,
    bool? isPromptValid,
    String? error,
    bool? isTogglingCollection,
    bool? isCompleted,
  }) {
    return VideoGenerationState(
      isGenerating: isGenerating ?? this.isGenerating,
      showOutput: showOutput ?? this.showOutput,
      currentRequestId: currentRequestId ?? this.currentRequestId,
      currentRequest: currentRequest ?? this.currentRequest,
      generatedVideoUrl: generatedVideoUrl ?? this.generatedVideoUrl,
      isAddedToCollection: isAddedToCollection ?? this.isAddedToCollection,
      promptText: promptText ?? this.promptText,
      isPromptValid: isPromptValid ?? this.isPromptValid,
      error: error ?? this.error,
      isTogglingCollection: isTogglingCollection ?? this.isTogglingCollection,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

// State notifier for managing video generation state
class VideoGenerationNotifier extends StateNotifier<VideoGenerationState> {
  final PredisVideoService _videoService;
  StreamSubscription<DocumentSnapshot>? _requestSubscription;

  VideoGenerationNotifier(this._videoService) : super(const VideoGenerationState());

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  void updatePrompt(String prompt) {
    state = state.copyWith(
      promptText: prompt,
      isPromptValid: prompt.trim().length >= 10,
    );
  }

  Future<void> generateVideo(String prompt, BuildContext context) async {
    if (prompt.isEmpty) {
      NotificationService.showError(
        context: context,
        title: 'Invalid Prompt',
        message: 'Please enter a prompt',
      );
      return;
    }

    state = state.copyWith(
      isGenerating: true,
      showOutput: false,
      generatedVideoUrl: null,
      currentRequest: null,
      isAddedToCollection: false,
      error: null,
    );

    try {
      final requestId = await _videoService.submitRequest(prompt, context);

      if (requestId != null) {
        state = state.copyWith(currentRequestId: requestId);
        _listenToRequestUpdates(requestId, context);
      }
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: e.toString(),
      );
      if (context.mounted) {
        NotificationService.showError(
          context: context,
          title: 'Generation Error',
          message: 'Failed to start video generation',
          technicalDetails: e.toString(),
        );
      }
    }
  }

  void _listenToRequestUpdates(String requestId, BuildContext context) {
    _requestSubscription?.cancel();
    _requestSubscription = FirebaseFirestore.instance
        .collection('generation_queue')
        .doc(requestId)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) {
          _requestSubscription?.cancel();
          return;
        }

        try {
          final request = GenerationRequest.fromMap(snapshot.data()!);
          _updateGenerationStatus(request, context);
        } catch (e) {
          debugPrint('Error parsing request data: $e');
          state = state.copyWith(
            isGenerating: false,
            error: e.toString(),
          );
        }
      },
      onError: (error) {
        debugPrint('Error listening to request updates: $error');
        state = state.copyWith(
          isGenerating: false,
          error: error.toString(),
        );
      },
    );
  }

  void _updateGenerationStatus(GenerationRequest request, BuildContext context) {
    final bool wasGenerating = state.isGenerating;
    
    // Update progress immediately
    if (request.progress != null && request.progress != state.currentRequest?.progress) {
      state = state.copyWith(
        currentRequest: request,
        isGenerating: true,
      );
    }

    switch (request.status.toLowerCase()) {
      case 'completed':
        if (!state.isCompleted) {
          state = state.copyWith(
            isGenerating: false,
            showOutput: true,
            generatedVideoUrl: _extractVideoUrl(request.result),
            isCompleted: true,
            currentRequest: request.copyWith(progress: 100),
          );
          _requestSubscription?.cancel();
        }
        break;
      case 'failed':
        state = state.copyWith(
          isGenerating: false,
          error: request.errorMessage,
          isCompleted: false,
          currentRequest: request,
        );
        if (context.mounted) {
          NotificationService.showError(
            context: context,
            title: 'Generation Failed',
            message: request.errorMessage ?? 'Failed to generate video',
            showPopup: true,
          );
        }
        _requestSubscription?.cancel();
        break;
      case 'processing':
      case 'pending':
        state = state.copyWith(
          isGenerating: true,
          isCompleted: false,
          currentRequest: request,
        );
        break;
    }
  }

  String? _extractVideoUrl(dynamic result) {
    if (result is Map<String, dynamic>) {
      return result['video_url'] as String?;
    } else if (result is String) {
      return result;
    }
    return null;
  }

  Future<void> cancelRequest(String requestId, BuildContext context) async {
    try {
      await _videoService.cancelRequest(requestId, context);
      state = state.copyWith(isGenerating: false);
    } catch (e) {
      if (context.mounted) {
        NotificationService.showError(
          context: context,
          title: 'Cancel Error',
          message: 'Failed to cancel request',
          technicalDetails: e.toString(),
        );
      }
    }
  }

  Future<void> retryRequest(String requestId, BuildContext context) async {
    try {
      await _videoService.retryRequest(requestId, context);
      state = state.copyWith(
        isGenerating: true,
        error: null,
      );
    } catch (e) {
      if (context.mounted) {
        NotificationService.showError(
          context: context,
          title: 'Retry Failed',
          message: 'Failed to retry video generation',
          technicalDetails: e.toString(),
        );
      }
    }
  }

  Future<void> toggleCollection(bool shouldAdd, BuildContext context) async {
    if (state.currentRequest == null || 
        state.generatedVideoUrl == null || 
        state.isTogglingCollection || 
        !state.isCompleted) {
      return;
    }

    state = state.copyWith(isTogglingCollection: true);

    try {
      if (shouldAdd) {
        await _videoService.addToCollection(
          state.currentRequest!.id,
          state.generatedVideoUrl!,
          state.currentRequest!.prompt,
          state.currentRequest!.metadata ?? {},
        );
        
        state = state.copyWith(
          isAddedToCollection: true,
          isTogglingCollection: false,
        );
      } else {
        await _videoService.removeFromCollection(state.currentRequest!.id);
        
        state = state.copyWith(
          isAddedToCollection: false,
          isTogglingCollection: false,
        );
      }
    } catch (e) {
      debugPrint('Collection toggle error: $e');
      state = state.copyWith(
        isAddedToCollection: !shouldAdd,
        isTogglingCollection: false,
      );
    }
  }

  void reset() {
    _requestSubscription?.cancel();
    state = const VideoGenerationState();
  }
}

// Providers
final videoServiceProvider = Provider<PredisVideoService>((ref) => PredisVideoService(
  firestore: FirebaseFirestore.instance,
  auth: FirebaseAuth.instance,
  config: AIServiceFactory.getConfig(AIServiceType.predisAI),
));

final videoGenerationProvider = StateNotifierProvider<VideoGenerationNotifier, VideoGenerationState>((ref) {
  final videoService = ref.watch(videoServiceProvider);
  return VideoGenerationNotifier(videoService);
});

// UI Component
class VideoAIScreen extends ConsumerWidget {
  const VideoAIScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoGenerationProvider);
    final notifier = ref.read(videoGenerationProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AIAppBar(
        type: GenerationType.video,
        title: 'Video Gen',
        onTipsPressed: () => _showTipsDialog(context),
        onBackPressed: () => Navigator.pop(context),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: AIPromptInput(
                type: GenerationType.video,
                onSubmit: (prompt) => notifier.generateVideo(prompt, context),
                isLoading: state.isGenerating,
                hintText: 'Describe the video you want to create...',
                submitIcon: Icons.movie_creation,
                submitLabel: 'Generate Video',
                accentColor: Colors.red.shade400,
                onChanged: (value) => notifier.updatePrompt(value),
                isEnabled: !state.isGenerating && state.isPromptValid,
                initialValue: state.promptText,
              ),
            ),
            _buildGeneratingIndicator(state),
            if (state.currentRequest != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GenerationRequestCard(
                  request: state.currentRequest!,
                  reference: FirebaseFirestore.instance.collection('generation_queue').doc(state.currentRequest!.id),
                  onRetry: () => notifier.retryRequest(state.currentRequest!.id, context),
                  onCancel: () => notifier.cancelRequest(state.currentRequest!.id, context),
                  onCollectionToggle: state.isTogglingCollection ? null : (shouldAdd) {
                    notifier.toggleCollection(shouldAdd, context);
                    return state.isAddedToCollection;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingIndicator(VideoGenerationState state) {
    if (!state.isGenerating || state.currentRequest?.status.toLowerCase() == 'completed') {
      return const SizedBox.shrink();
    }

    final progress = state.currentRequest?.progress ?? 0;

    return AnimatedOpacity(
      opacity: state.isGenerating ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 32),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: Colors.red.shade400,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Generating your masterpiece...',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            // Progress percentage
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.currentRequest?.status ?? 'Processing...',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${progress.toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(3),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: constraints.maxWidth * (progress / 100),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade400,
                              Colors.red.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade400.withOpacity(0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTipsDialog(BuildContext context) {
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
} 