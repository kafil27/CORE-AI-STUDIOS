import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/ai_prompt_input.dart';
import '../../../models/generation_request.dart';
import '../../../models/generation_type.dart';
import '../../widgets/generation_request_card.dart';

import '../../widgets/tips_section.dart';
import '../../../services/generation_request_service.dart';
import '../../../services/image_generation_service.dart';
import '../../widgets/loading_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

final imageServiceProvider = Provider((ref) => ImageGenerationService());
final generationRequestServiceProvider = Provider((ref) => GenerationRequestService());

final recentPromptsProvider = StateNotifierProvider<RecentPromptsNotifier, List<String>>((ref) {
  return RecentPromptsNotifier();
});

class RecentPromptsNotifier extends StateNotifier<List<String>> {
  RecentPromptsNotifier() : super([]) {
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final prompts = prefs.getStringList('recent_prompts') ?? [];
    state = prompts;
  }

  Future<void> addPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final prompts = [...state, prompt];
    if (prompts.length > 10) prompts.removeAt(0); // Keep last 10 prompts
    await prefs.setStringList('recent_prompts', prompts);
    state = prompts;
  }
}

class ImageAIScreen extends ConsumerStatefulWidget {
  const ImageAIScreen({super.key});

  @override
  ConsumerState<ImageAIScreen> createState() => _ImageAIScreenState();
}

class _ImageAIScreenState extends ConsumerState<ImageAIScreen> {
  final GenerationRequestService _requestService = GenerationRequestService();
  String? _currentRequestId;

  Future<void> _generateImage(String prompt) async {
    final requestId = await _requestService.submitRequest(
      context: context,
      prompt: prompt,
      type: GenerationType.image,
      metadata: {
        'style': 'realistic', // or 'artistic', 'anime', etc.
        'quality': 'high',
        'width': 1024,
        'height': 1024,
      },
    );

    if (requestId != null) {
      setState(() => _currentRequestId = requestId);
    }
  }

  Widget _buildGenerationRequestCard(GenerationRequest request) {
    return GenerationRequestCard(
      request: request,
      isExpanded: true,
      showProgress: true,
    );
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
                        'Image Generation',
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
                        type: GenerationType.image,
                        onSubmit: _generateImage,
                        isLoading: currentRequest.when(
                          data: (request) => request?.isInProgress ?? false,
                          loading: () => true,
                          error: (_, __) => false,
                        ),
                        hintText: 'Describe the image you want to generate...',
                        submitIcon: Icons.image,
                        submitLabel: 'Generate Image',
                        accentColor: Colors.blue,
                      ),
                      const SizedBox(height: 24),
                      // Tips Section
                      const TipsSection(
                        title: 'Image Generation Tips',
                        icon: Icons.lightbulb_outline,
                        accentColor: Colors.amber,
                        
                      
                        tips: [
                          'Be specific about what you want in the image.',
                          'Include details about style, lighting, and composition.',
                          'Mention specific artistic styles or references.',
                          'Keep prompts clear and concise for best results.',
                          'Use descriptive adjectives for better accuracy.',
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
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  width: double.infinity,
                                  child: GenerationRequestCard(
                                    request: request,
                                    isExpanded: true,
                                    onRetry: () => _requestService.retryRequest(
                                      request.id,
                                      context,
                                    ),
                                  ),
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
                          final imageRequests = requests
                              .where((r) => r.type == GenerationType.image)
                              .where((r) => r.id != _currentRequestId)
                              .toList();

                          if (imageRequests.isEmpty) {
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
                              ...imageRequests.map((request) =>
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  width: double.infinity,
                                  child: GenerationRequestCard(
                                    request: request,
                                    isExpanded: true,
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
                        message: 'Generating Image',
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
}
