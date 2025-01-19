import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/image_generation_service.dart';
import '../../../services/token_service.dart';
import '../../../providers/token_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'dart:math';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:elegant_notification/resources/arrays.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

final imageGenerationServiceProvider =
    Provider((ref) => ImageGenerationService());

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
  @override
  ConsumerState<ImageAIScreen> createState() => _ImageAIScreenState();
}

class _ImageAIScreenState extends ConsumerState<ImageAIScreen>
    with TickerProviderStateMixin {
  final TextEditingController _promptController = TextEditingController();
  String? _generatedImageUrl;
  bool _isLoading = false;
  bool _isDownloading = false;
  bool _showAdvancedOptions = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  ImageModel _selectedModel = ImageModel.stable_diffusion_v3;
  String _selectedStyle = 'enhance';
  int _steps = 30;
  double _cfgScale = 7.0;
  String? _downloadedFilePath;
  bool _isGenerating = false;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _starAnimationController;
  late AnimationController _pulseAnimationController;

  final List<String> _stylePresets = [
    'enhance',
    'anime',
    'photographic',
    'digital-art',
    'comic-book',
    'fantasy-art',
    '3d-model',
    'neon-punk',
    'isometric',
    'low-poly',
    'origami',
    'line-art',
    'cinematic',
    'analog-film',
    'tile-texture',
  ];

  Map<ImageModel, int> modelTokens = {
    ImageModel.stable_diffusion_v3: 20,
    ImageModel.core_diffusion: 25,
    ImageModel.ultra_diffusion: 30,
  };

  int get _currentTokenCost => modelTokens[_selectedModel] ?? 20;

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

    _starAnimationController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    _pulseAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _animationController.dispose();
    _starAnimationController.dispose();
    _pulseAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _generateImage() async {
    if (_promptController.text.trim().isEmpty || _isGenerating) return;

    final prompt = _promptController.text.trim();
    final modelId = _selectedModel.toString().split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'stability_ai_$timestamp.png';

    try {
      await ref.read(tokenServiceProvider).checkTokenBalance(_currentTokenCost);

      setState(() {
        _isGenerating = true;
        _generatedImageUrl = null;
        _downloadedFilePath = null;
        _showAdvancedOptions = false;
      });

      // Store prompt locally
      await ref.read(recentPromptsProvider.notifier).addPrompt(prompt);

      final imageUrl = await ref.read(imageGenerationServiceProvider).generateImage(
            prompt,
            model: _selectedModel,
            style: _selectedStyle,
            steps: _steps,
            cfgScale: _cfgScale,
          );

      // Save image URL without base64 data for Firestore
      final truncatedUrl = imageUrl.split(',')[0] + ',<base64_data>';

      // Deduct tokens and store usage history
      await ref.read(tokenServiceProvider).deductTokens(
            _currentTokenCost,
            'Image Generation',
            prompt: prompt,
            modelId: modelId,
            outputUrl: truncatedUrl,
            generatedFileName: fileName,
            serviceSpecificData: {
              'model': modelId,
              'style': _selectedStyle,
              'steps': _steps,
              'cfgScale': _cfgScale,
              'width': 1024,
              'height': 1024,
              'format': 'png',
            },
          );

      setState(() {
        _generatedImageUrl = imageUrl;
      });

      // Save to recent generations
      await _saveToRecentGenerations(
        prompt: prompt,
        filePath: _downloadedFilePath ?? '',
        timestamp: DateTime.now(),
        modelId: modelId,
        outputUrl: truncatedUrl,
      );

      // Scroll to the generated image
      await Future.delayed(Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }

      _showSuccessNotification();
    } catch (e) {
      String errorMessage = 'An error occurred';
      
      if (e.toString().contains('Insufficient tokens')) {
        errorMessage = 'Insufficient tokens. Please purchase more tokens to continue.';
      } else if (e.toString().contains('User not authenticated')) {
        errorMessage = 'Please sign in to generate images.';
      } else if (e.toString().contains('Failed to generate image')) {
        errorMessage = 'Failed to generate image. Please try again.';
      } else if (e.toString().contains('Failed to deduct tokens')) {
        errorMessage = 'Error processing tokens. Please try again.';
      } else if (e.toString().contains('Failed to save usage history')) {
        errorMessage = 'Error saving generation history. Please try again.';
      }
      
      _showErrorNotification(errorMessage);
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _downloadImage() async {
    if (_generatedImageUrl == null || _isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final bytes = base64.decode(_generatedImageUrl!.split(',')[1]);
      final downloadsPath = '/storage/emulated/0/Download';
      final directory = Directory(downloadsPath);
      if (!await directory.exists()) {
        throw Exception('Downloads directory not found');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'stability_ai_$timestamp.png';
      final filePath = path.join(downloadsPath, fileName);
      final file = File(filePath);

      await file.writeAsBytes(bytes);

      setState(() {
        _downloadedFilePath = filePath;
      });

      // Save to recent generations
      await _saveToRecentGenerations(
        prompt: _promptController.text,
        filePath: filePath,
        timestamp: DateTime.now(),
        modelId: _selectedModel.toString().split('.').last,
        outputUrl: _generatedImageUrl!.split(',')[0] + ',<base64_data>',
      );
    } catch (e) {
      _showErrorNotification('Error downloading image: ${e.toString()}');
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _openImage() async {
    if (_downloadedFilePath == null) return;

    try {
      final file = File(_downloadedFilePath!);
      if (!await file.exists()) {
        throw Exception('File not found');
      }

      final result = await OpenFile.open(_downloadedFilePath!);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      _showErrorNotification('Error opening image: ${e.toString()}');
    }
  }

  Future<void> _saveToRecentGenerations({
    required String prompt,
    required String filePath,
    required DateTime timestamp,
    required String modelId,
    required String outputUrl,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing generations or initialize empty list
      final List<String> generations = prefs.getStringList('recent_generations') ?? [];
      
      // Create generation data
      final Map<String, dynamic> generationData = {
        'prompt': prompt,
        'filePath': filePath,
        'timestamp': timestamp.toIso8601String(),
        'modelId': modelId,
        'outputUrl': outputUrl,
        'style': _selectedStyle,
        'steps': _steps,
        'cfgScale': _cfgScale,
      };
      
      // Add new generation at the beginning
      generations.insert(0, jsonEncode(generationData));
      
      // Keep only last 10 generations
      if (generations.length > 10) {
        generations.removeLast();
      }
      
      // Save updated list
      await prefs.setStringList('recent_generations', generations);
    } catch (e) {
      print('Error saving to recent generations: $e');
    }
  }

  void _resetGeneration() {
    setState(() {
      _promptController.clear();
      _generatedImageUrl = null;
      _downloadedFilePath = null;
      _isGenerating = false;
      _isDownloading = false;
    });
  }

  void _showSuccessNotification() {
    ElegantNotification(
      width: MediaQuery.of(context).size.width * 0.9,
      position: Alignment.bottomCenter,
      animation: AnimationType.fromBottom,
      background: Theme.of(context).primaryColor.withOpacity(0.95),
      height: 80,
      description: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image Generated Successfully',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  _selectedModel.toString().split('.').last.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.token, size: 14, color: Colors.amber),
                SizedBox(width: 4),
                Text(
                  '-${_currentTokenCost}',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      displayCloseButton: false,
      autoDismiss: true,
      animationDuration: Duration(milliseconds: 400),
      toastDuration: Duration(seconds: 2),
    ).show(context);
  }

  void _showErrorNotification(String message) {
    ElegantNotification(
      width: MediaQuery.of(context).size.width * 0.9,
      position: Alignment.bottomCenter,
      animation: AnimationType.fromBottom,
      background: Colors.red.shade900.withOpacity(0.95),
      height: 80,
      description: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      displayCloseButton: false,
      autoDismiss: true,
      animationDuration: Duration(milliseconds: 400),
      toastDuration: Duration(seconds: 3),
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: 22),
            SizedBox(width: 8),
            Text('Image Gen'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: () => _showTipsDialog(),
            tooltip: 'Tips & Tricks',
          ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: _generatedImageUrl != null ? 80 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPromptInput(),
                  SizedBox(height: 16),
                  if (!_isGenerating) ...[
                    AnimatedSlide(
                      duration: Duration(milliseconds: 300),
                      offset: _isGenerating ? Offset(0, -0.1) : Offset.zero,
                      child: AnimatedOpacity(
                        duration: Duration(milliseconds: 200),
                        opacity: _isGenerating ? 0 : 1,
                        child: _buildAdvancedOptionsHeader(),
                      ),
                    ),
                    if (_showAdvancedOptions) ...[
                      SizedBox(height: 16),
                      AnimatedSlide(
                        duration: Duration(milliseconds: 300),
                        offset: _isGenerating ? Offset(0, -0.1) : Offset.zero,
                        child: AnimatedOpacity(
                          duration: Duration(milliseconds: 200),
                          opacity: _isGenerating ? 0 : 1,
                          child: _buildAdvancedOptions(),
                        ),
                      ),
                    ],
                  ],
                  SizedBox(height: 24),
                  if (_isGenerating)
                    _buildLoadingIndicator()
                  else if (_generatedImageUrl != null)
                    _buildGeneratedImage()
                  else
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _animation.value),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/bot_image.png',
                                height: 120,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Enter a prompt to generate an image',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_generatedImageUrl != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isDownloading ? null : (_downloadedFilePath != null ? _openImage : _downloadImage),
                                icon: Icon(
                                  _isDownloading 
                                    ? Icons.hourglass_empty 
                                    : (_downloadedFilePath != null ? Icons.open_in_new : Icons.download),
                                  size: 18,
                                ),
                                label: Text(
                                  _isDownloading 
                                    ? 'Downloading...' 
                                    : (_downloadedFilePath != null ? 'Open Image' : 'Download'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.3),
                                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ).copyWith(
                                  overlayColor: MaterialStateProperty.resolveWith((states) {
                                    if (states.contains(MaterialState.pressed)) {
                                      return Theme.of(context).primaryColor.withOpacity(0.4);
                                    }
                                    if (states.contains(MaterialState.hovered)) {
                                      return Theme.of(context).primaryColor.withOpacity(0.35);
                                    }
                                    return null;
                                  }),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  onTap: _resetGeneration,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.refresh,
                                      size: 18,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdvancedOptionsHeader() {
    return InkWell(
      onTap: () {
        setState(() {
          _showAdvancedOptions = !_showAdvancedOptions;
        });
      },
      onLongPress: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            width: MediaQuery.of(context).size.width * 0.9,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: Colors.grey[850],
            content: Text(
              'Modify steps, CFG scale, and style to fine-tune your generation',
              style: TextStyle(color: Colors.white),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.tune,
                color: Theme.of(context).primaryColor,
                size: 20,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Advanced Options',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
            AnimatedRotation(
              turns: _showAdvancedOptions ? 0.5 : 0,
              duration: Duration(milliseconds: 300),
              child: Icon(
                Icons.expand_more,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(top: 8),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    decoration: InputDecoration(
                      hintText: 'Describe your imagination...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: 3,
                    enabled: !_isGenerating,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).primaryColor.withOpacity(0.1)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.token,
                        size: 14,
                        color: Colors.amber,
                      ),
                      SizedBox(width: 4),
                      Text(
                        _currentTokenCost.toString(),
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _generateImage,
                    icon: _isGenerating
                        ? Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            child: _buildGenerateButtonAnimation(),
                          )
                        : Icon(Icons.auto_awesome),
                    label: Text(_isGenerating ? '' : 'Generate'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButtonAnimation() {
    return AnimatedBuilder(
      animation: _starAnimationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _starAnimationController.value * 2 * pi,
          child: Icon(
            Icons.auto_awesome,
            color: Colors.white.withOpacity(0.7),
            size: 20,
          ),
        );
      },
    );
  }

  Widget _buildAdvancedOptions() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelSelector(),
          SizedBox(height: 16),
          _buildStyleSelector(),
          SizedBox(height: 16),
          _buildStepsSlider(),
          SizedBox(height: 16),
          _buildCfgScaleSlider(),
        ],
      ),
    );
  }

  Widget _buildModelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withOpacity(0.2),
                    Colors.blue.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.model_training, size: 18, color: Colors.blue),
            ),
            SizedBox(width: 8),
            Text(
              'Model',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.blue.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ImageModel>(
              value: _selectedModel,
              isExpanded: true,
              dropdownColor: Colors.grey[900],
              style: TextStyle(color: Colors.white),
              items: ImageModel.values.map((model) {
                final tokens = modelTokens[model] ?? 20;
                return DropdownMenuItem(
                  value: model,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.toString().split('.').last.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.token, size: 12, color: Colors.amber),
                            SizedBox(width: 4),
                            Text(
                              tokens.toString(),
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (model) {
                if (model != null) {
                  setState(() {
                    _selectedModel = model;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withOpacity(0.2),
                    Colors.purple.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.style, size: 18, color: Colors.purple),
            ),
            SizedBox(width: 8),
            Text(
              'Style',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.purple.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedStyle,
              isExpanded: true,
              dropdownColor: Colors.grey[900],
              style: TextStyle(color: Colors.white),
              items: _stylePresets.map((style) {
                return DropdownMenuItem(
                  value: style,
                  child: Text(
                    style.replaceAll('-', ' ').toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (style) {
                if (style != null) {
                  setState(() {
                    _selectedStyle = style;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepsSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withOpacity(0.2),
                        Colors.orange.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.timeline, size: 18, color: Colors.orange),
                ),
                SizedBox(width: 8),
                Text(
                  'Steps',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _steps.toString(),
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Colors.orange.withOpacity(0.6),
            inactiveTrackColor: Colors.orange.withOpacity(0.1),
            thumbColor: Colors.orange,
            overlayColor: Colors.orange.withOpacity(0.1),
            valueIndicatorColor: Colors.orange,
            valueIndicatorTextStyle: TextStyle(color: Colors.white),
          ),
          child: Slider(
            value: _steps.toDouble(),
            min: 10,
            max: 50,
            divisions: 40,
            label: _steps.toString(),
            onChanged: (value) {
              setState(() {
                _steps = value.round();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCfgScaleSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.teal.withOpacity(0.2),
                        Colors.teal.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.tune, size: 18, color: Colors.teal),
                ),
                SizedBox(width: 8),
                Text(
                  'CFG Scale',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _cfgScale.toStringAsFixed(1),
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Colors.teal.withOpacity(0.6),
            inactiveTrackColor: Colors.teal.withOpacity(0.1),
            thumbColor: Colors.teal,
            overlayColor: Colors.teal.withOpacity(0.1),
            valueIndicatorColor: Colors.teal,
            valueIndicatorTextStyle: TextStyle(color: Colors.white),
          ),
          child: Slider(
            value: _cfgScale,
            min: 0,
            max: 35,
            divisions: 70,
            label: _cfgScale.toStringAsFixed(1),
            onChanged: (value) {
              setState(() {
                _cfgScale = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildRotatingStars(
                  count: 8,
                  radius: 80,
                  duration: Duration(seconds: 8),
                  starSize: 10,
                  color: Colors.blue.shade300,
                  glowIntensity: 1.2,
                ),
                _buildRotatingStars(
                  count: 6,
                  radius: 60,
                  duration: Duration(seconds: 6),
                  starSize: 8,
                  color: Colors.purple.shade300,
                  reverse: true,
                  glowIntensity: 1.0,
                ),
                _buildRotatingStars(
                  count: 4,
                  radius: 40,
                  duration: Duration(seconds: 4),
                  starSize: 6,
                  color: Colors.teal.shade200,
                  glowIntensity: 0.8,
                ),
                _buildPulsingStar(),
              ],
            ),
          ),
          SizedBox(height: 32),
          Text(
            'Generating your masterpiece...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotatingStars({
    required int count,
    required double radius,
    required Duration duration,
    required double starSize,
    required Color color,
    bool reverse = false,
    double glowIntensity = 1.0,
  }) {
    return AnimatedBuilder(
      animation: _starAnimationController,
      builder: (context, child) {
        final value = _starAnimationController.value * 2 * pi;
        return Transform.rotate(
          angle: reverse ? -value : value,
          child: Stack(
            alignment: Alignment.center,
            children: List.generate(count, (index) {
              final angle = (index * 2 * pi) / count;
              return Transform.translate(
                offset: Offset(
                  radius * cos(angle),
                  radius * sin(angle),
                ),
                child: _buildStar(color, starSize, glowIntensity),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildStar(Color color, double size, double glowIntensity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.6),
            color.withOpacity(0.2),
          ],
          stops: [0.1, 1.0],
        ),
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: size * glowIntensity,
            spreadRadius: size * glowIntensity / 3,
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingStar() {
    return AnimatedBuilder(
      animation: _pulseAnimationController,
      builder: (context, child) {
        final scale = 0.5 + (_pulseAnimationController.value * 0.8);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.6),
                  Colors.white.withOpacity(0.2),
                ],
                stops: [0.1, 1.0],
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.2),
                  blurRadius: 24,
                  spreadRadius: 6,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGeneratedImage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final padding = 8.0;
    final imageSize = screenWidth - (padding * 2);
    final maxHeight = screenHeight * 0.75;

    return Hero(
      tag: 'generated_image',
      child: Container(
        width: imageSize,
        constraints: BoxConstraints(
          maxHeight: maxHeight,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Image.memory(
            base64Decode(_generatedImageUrl!.split(',')[1]),
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame == null) {
                return Container(
                  height: maxHeight * 0.9,
                  color: Colors.grey[900],
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return child;
            },
          ),
        ),
      ),
    );
  }

  void _showTipsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.tips_and_updates,
                        color: Theme.of(context).primaryColor,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Image Generation Tips',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      _buildTipItem(
                        Icons.lightbulb_outline,
                        'Be Descriptive',
                        'Include details about style, mood, lighting, and composition.',
                        Colors.amber,
                      ),
                      _buildTipItem(
                        Icons.style,
                        'Choose Model',
                        'Different models excel at different types of images.',
                        Colors.blue,
                      ),
                      _buildTipItem(
                        Icons.tune,
                        'Parameters',
                        'Fine-tune steps and CFG scale for better quality.',
                        Colors.purple,
                      ),
                      _buildTipItem(
                        Icons.palette,
                        'Style Presets',
                        'Try different presets for specific artistic looks.',
                        Colors.green,
                      ),
                      _buildTipItem(
                        Icons.token,
                        'Token Usage',
                        'Costs vary by model:\n'
                            '• Stable Diffusion: 20 tokens\n'
                            '• Core Diffusion: 25 tokens\n'
                            '• Ultra Diffusion: 30 tokens',
                        Colors.orange,
                      ),
                      _buildTipItem(
                        Icons.warning_amber,
                        'Save Images',
                        'Download generated images to keep them permanently.',
                        Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(12),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Got it',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w600,
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

  Widget _buildTipItem(IconData icon, String title, String text, Color color) {
    if (title == 'Token Usage') {
      text = 'Costs vary by model:\n'
          '• Stable Diffusion: 20 tokens\n'
          '• Core Diffusion: 25 tokens\n'
          '• Ultra Diffusion: 30 tokens';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.2),
                  color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[300],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getFormattedServiceType() {
    final modelName = _selectedModel.toString().split('.').last
      .split('_')
      .map((word) => word.substring(0, 1).toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
    return 'Image Generation ($modelName)';
  }
}
