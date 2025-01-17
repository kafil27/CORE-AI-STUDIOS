import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/image_generation_service.dart';
import 'dart:io';

final imageGenerationServiceProvider = Provider((ref) => ImageGenerationService());

class ImageAIScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<ImageAIScreen> createState() => _ImageAIScreenState();
}

class _ImageAIScreenState extends ConsumerState<ImageAIScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _promptController = TextEditingController();
  String? _generatedImageUrl;
  bool _isLoading = false;
  bool _isDownloading = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

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
  }

  @override
  void dispose() {
    _promptController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _generateImage() async {
    if (_promptController.text.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _generatedImageUrl = null;
    });

    try {
      final imageUrl = await ref.read(imageGenerationServiceProvider).generateImage(
        _promptController.text.trim(),
      );
      setState(() {
        _generatedImageUrl = imageUrl;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadImage() async {
    if (_generatedImageUrl == null) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final file = await ref.read(imageGenerationServiceProvider).downloadImage(_generatedImageUrl!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image saved to: ${file.path}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => ref.read(imageGenerationServiceProvider).saveToGoogleDrive(file),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading image: $e')),
      );
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gemini Image Generation'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Google Gemini Pro Vision',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Advanced AI image generation powered by Google',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Animated Bot
              if (!_isLoading && _generatedImageUrl == null)
                Center(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _animation.value),
                        child: Image.asset(
                          'assets/bot_image.png',
                          height: 120,
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),

              // Prompt Input
              TextField(
                controller: _promptController,
                decoration: InputDecoration(
                  hintText: 'Describe the image you want to generate...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[900],
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send_rounded),
                    onPressed: _isLoading ? null : _generateImage,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                maxLines: 3,
                enabled: !_isLoading,
              ),

              const SizedBox(height: 24),

              // Generated Image or Loading
              if (_isLoading)
                Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Generating your masterpiece with Gemini...'),
                    ],
                  ),
                )
              else if (_generatedImageUrl != null)
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.network(
                          _generatedImageUrl!,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 300,
                              color: Colors.grey[900],
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isDownloading ? null : _downloadImage,
                          icon: Icon(_isDownloading ? Icons.hourglass_empty : Icons.download),
                          label: Text(_isDownloading ? 'Downloading...' : 'Download'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _generatedImageUrl = null;
                              _promptController.clear();
                            });
                          },
                          icon: Icon(Icons.refresh),
                          label: Text('Generate Another'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
} 