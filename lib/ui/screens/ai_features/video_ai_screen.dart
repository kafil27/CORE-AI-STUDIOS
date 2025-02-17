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

final videoServiceProvider = Provider<PredisVideoService>((ref) => PredisVideoService(
  firestore: FirebaseFirestore.instance,
  auth: FirebaseAuth.instance,
  config: AIServiceFactory.getConfig(AIServiceType.predisAI),
));

final generationRequestServiceProvider = Provider((ref) => GenerationRequestService());

class VideoAIScreen extends ConsumerStatefulWidget {
  const VideoAIScreen({super.key});

  @override
  ConsumerState<VideoAIScreen> createState() => _VideoAIScreenState();
}

class _VideoAIScreenState extends ConsumerState<VideoAIScreen> {
  final _scrollController = ScrollController();
  late final PredisVideoService _predisService;
  String? _currentRequestId;
  final _focusNode = FocusNode();
  bool _isPromptValid = false;
  String _promptText = '';
  GenerationRequest? _currentRequest;
  String? _generatedVideoUrl;
  bool _isGenerating = false;
  bool _showOutput = false;
  bool _isAddedToCollection = false;
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  String? _error;

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
    _scrollController.dispose();
    _focusNode.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AIAppBar(
        type: GenerationType.video,
        title: 'Video Gen',
        onTipsPressed: _showTipsDialog,
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
                onSubmit: _handleGenerate,
                isLoading: _isGenerating,
                hintText: 'Describe the video you want to create...',
                submitIcon: Icons.movie_creation,
                submitLabel: 'Generate Video',
                accentColor: Colors.red.shade400,
                onChanged: (value) {
                  setState(() {
                    _promptText = value;
                    _isPromptValid = value.trim().length >= 10;
                  });
                },
                isEnabled: !_isGenerating && _isPromptValid,
                initialValue: _promptText,
                focusNode: _focusNode,
              ),
            ),
            _buildGeneratingMessage(),
            if (_currentRequest != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GenerationRequestCard(
                  request: _currentRequest!,
                  reference: FirebaseFirestore.instance.collection('generation_queue').doc(_currentRequest!.id),
                  onRetry: () => _retryGeneration(_currentRequest!.id),
                  onCancel: () => _cancelGeneration(_currentRequest!.id),
                  onCollectionToggle: _handleCollectionToggle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingMessage() {
    if (!_isGenerating || _currentRequest?.status.toLowerCase() == 'completed') {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: _isGenerating ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.red.shade400,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              'Generating your masterpiece...',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.w500,
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
      ),
    );
  }

  Widget _buildNewGenerationButton() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _resetGeneration,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red.shade800,
                  Colors.red.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.shade900.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: Colors.grey[100],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Start New Generation',
                  style: TextStyle(
                    color: Colors.grey[100],
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
      _showOutput = false;
      _generatedVideoUrl = null;
      _currentRequest = null;
      _isAddedToCollection = false;
    });

    try {
      final videoService = ref.read(videoServiceProvider);
      final requestId = await videoService.generateVideo(
        prompt,
        {
          'type': 'video',
          'prompt': prompt,
          'status': 'pending',
          'progress': 0,
          'addedToCollection': false,
        },
      );

      if (requestId != null) {
        setState(() {
          _currentRequestId = requestId;
        });

        // Listen to request updates
        StreamSubscription<DocumentSnapshot>? subscription;
        subscription = FirebaseFirestore.instance
            .collection('generation_queue')
            .doc(requestId)
            .snapshots()
            .listen((snapshot) {
          if (!mounted || !snapshot.exists) {
            subscription?.cancel();
            return;
          }
          
          try {
            final data = snapshot.data()!;
            // Handle string result case
            if (data['result'] is String) {
              data['result'] = {'video_url': data['result']};
            }
            
            final request = GenerationRequest.fromMap(data);
            _updateGenerationStatus(request);

            // Show appropriate notifications
            if (request.status.toLowerCase() == 'completed') {
              NotificationService.showSuccess(
                context: context,
                title: 'Video Generated',
                message: 'Your video has been generated successfully!',
                playSound: true,
              );
              subscription?.cancel(); // Cancel subscription after completion
            } else if (request.status.toLowerCase() == 'failed') {
              NotificationService.showError(
                context: context,
                title: 'Generation Failed',
                message: request.errorMessage ?? 'Failed to generate video',
                showPopup: true,
              );
              setState(() {
                _isGenerating = false;
              });
              subscription?.cancel(); // Cancel subscription after failure
            }
          } catch (e) {
            debugPrint('Error parsing request data: $e');
            subscription?.cancel();
          }
        }, onError: (error) {
          debugPrint('Error listening to request updates: $error');
          subscription?.cancel();
        });
      } else {
        throw Exception('Failed to start video generation');
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError(
          context: context,
          title: 'Generation Error',
          message: 'Failed to start video generation',
          technicalDetails: e.toString(),
        );
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _updateGenerationStatus(GenerationRequest request) {
    if (!mounted) return;
    
    setState(() {
      _currentRequest = request;
      
      // Update progress based on status
      if (request.status.toLowerCase() == 'pending') {
        _currentRequest = request.copyWith(progress: 20.0);
      } else if (request.status.toLowerCase() == 'processing') {
        final currentProgress = request.progress ?? 0.0;
        if (currentProgress < 20) {
          _currentRequest = request.copyWith(progress: 40.0);
        } else if (currentProgress < 40) {
          _currentRequest = request.copyWith(progress: 60.0);
        } else if (currentProgress < 60) {
          _currentRequest = request.copyWith(progress: 80.0);
        }
      } else if (request.status.toLowerCase() == 'completed') {
        _currentRequest = request.copyWith(progress: 100.0);
        _isGenerating = false; // Ensure we stop generating state when complete
      }
      
      if (request.status.toLowerCase() == 'completed') {
        _showOutput = true;
        if (request.result is Map<String, dynamic>) {
          final resultMap = request.result as Map<String, dynamic>;
          _generatedVideoUrl = resultMap['video_url'] as String?;
        } else if (request.result is String) {
          _generatedVideoUrl = request.result as String;
        }
      }
    });
  }

  Future<void> _handleCancelRequest(String requestId) async {
    try {
      final videoService = ref.read(videoServiceProvider);
      await videoService.cancelRequest(requestId, context);
      setState(() {
        _isGenerating = false;
      });
    } catch (e) {
      if (mounted) {
        NotificationService.showError(
          context: context,
          title: 'Cancel Error',
          message: 'Failed to cancel request',
          technicalDetails: e.toString(),
        );
      }
    }
  }

  Future<void> _handleCollectionToggle(bool shouldAdd) async {
    if (_currentRequest == null) return;

    try {
      final videoService = ref.read(videoServiceProvider);
      if (shouldAdd) {
        // Add to collection
        await videoService.addToCollection(
          _currentRequest!.id,
          _generatedVideoUrl!,
          _currentRequest!.prompt,
          _currentRequest!.metadata ?? {},
        );
        setState(() => _isAddedToCollection = true);
        
        if (mounted) {
          NotificationService.showSuccess(
            context: context,
            title: 'Added to Collection',
            message: 'Video has been saved to your collection',
          );
        }
      } else {
        // Remove from collection
        await videoService.removeFromCollection(_currentRequest!.id);
        setState(() => _isAddedToCollection = false);
        
        if (mounted) {
          NotificationService.showSuccess(
            context: context,
            title: 'Removed from Collection',
            message: 'Video has been removed from your collection',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError(
          context: context,
          title: shouldAdd ? 'Add to Collection Failed' : 'Remove from Collection Failed',
          message: 'Failed to update collection. Please ensure you have the necessary permissions.',
          technicalDetails: e.toString(),
        );
      }
      // Reset the state to reflect the failed operation
      setState(() => _isAddedToCollection = !shouldAdd);
    }
  }

  void _resetGeneration() {
    setState(() {
      _currentRequest = null;
      _generatedVideoUrl = null;
      _showOutput = false;
      _isGenerating = false;
      _isAddedToCollection = false;
      _promptText = '';
      _isPromptValid = false;
    });
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

  Widget _buildGenerationRequestCard(GenerationRequest request) {
    return GenerationRequestCard(
      request: request,
      reference: FirebaseFirestore.instance.collection('generation_queue').doc(request.id),
      onRetry: () => _retryGeneration(request.id),
      onCancel: () => _cancelGeneration(request.id),
    );
  }

  Future<void> _generateVideo(String prompt) async {
    if (!mounted) return;
    
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final videoService = ref.read(videoServiceProvider);
      final requestId = await videoService.submitRequest(prompt, context);

      if (requestId != null) {
        if (!mounted) return;
        NotificationService.showSuccess(
          context: context,
          title: 'Generation Started',
          message: 'Your video is being generated',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
      NotificationService.showError(
        context: context,
        title: 'Generation Failed',
        message: 'Failed to start video generation',
        technicalDetails: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _retryGeneration(String requestId) async {
    if (!mounted) return;
    
    try {
      final videoService = ref.read(videoServiceProvider);
      await videoService.retryRequest(requestId, context);
      setState(() {
        _isGenerating = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        context: context,
        title: 'Retry Failed',
        message: 'Failed to retry video generation',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<void> _cancelGeneration(String requestId) async {
    if (!mounted) return;
    
    try {
      final videoService = ref.read(videoServiceProvider);
      await videoService.cancelRequest(requestId, context);
      setState(() {
        _isGenerating = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        context: context,
        title: 'Cancel Failed',
        message: 'Failed to cancel video generation',
        technicalDetails: e.toString(),
      );
    }
  }
} 