import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/video_generation_service.dart';
import '../../widgets/error_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/token_service.dart';
import '../../../providers/token_provider.dart';

final videoServiceProvider = Provider((ref) => VideoGenerationService());

enum VideoModel {
  predisShort,
  predisLong,
}

class VideoAIScreen extends ConsumerStatefulWidget {
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
  List<Map<String, dynamic>> _videoList = [];
  int _currentPage = 1;
  bool _hasMoreVideos = true;
  Map<String, double> _downloadProgress = {};
  Map<String, String> _downloadedFiles = {};

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

    _loadVideos();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildGeneratingOverlay() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      padding: EdgeInsets.all(24),
      margin: EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(Icons.close, color: Colors.white70, size: 20),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: _cancelGeneration,
              ),
            ],
          ),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: _buildRotatingIcon(
              Icon(Icons.movie_filter, color: Colors.white, size: 32),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Generating Your Video',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This may take 2-5 minutes...',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 24),
          LinearProgressIndicator(
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateVideo() async {
    if (_promptController.text.trim().isEmpty || _isGenerating) return;

    try {
      // Check token balance first
      await ref.read(tokenServiceProvider).checkTokenBalance(TokenCost.video);

      setState(() {
        _isGenerating = true;
      });

      final response = await ref.read(videoServiceProvider).generateVideo(
        prompt: _promptController.text.trim(),
      );

      _currentVideoId = response['post_id'];
      _promptController.clear();
      _startPolling();
    } on TokenServiceException catch (e) {
      setState(() {
        _isGenerating = false;
      });
      _showInsufficientTokensDialog(e.message);
    } on VideoServiceException catch (e) {
      setState(() {
        _isGenerating = false;
      });
      _showErrorView(e.error, e.message);
    }
  }

  void _showInsufficientTokensDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.token,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Insufficient Tokens',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: Navigate to token purchase screen
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text('Get More Tokens'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startPolling() {
    Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        if (_currentVideoId == null) {
          timer.cancel();
          return;
        }

        final status = await ref.read(videoServiceProvider).getVideoStatus(_currentVideoId!);
        
        if (status['status'] == VideoGenerationService.STATUS_COMPLETED) {
          await ref.read(tokenServiceProvider).deductTokens(
            TokenCost.video,
            'video',
          );

          setState(() {
            _isGenerating = false;
            _currentVideoId = null;
          });
          timer.cancel();
          
          _showSuccessNotification('Video generated successfully! (-${TokenCost.video} tokens)');
          await _refreshVideos();
        } else if (status['status'] == VideoGenerationService.STATUS_FAILED) {
          setState(() {
            _isGenerating = false;
            _currentVideoId = null;
          });
          timer.cancel();
          
          _showErrorNotification('Video generation failed. No tokens deducted.');
        }
      } catch (e) {
        print('Polling error: $e');
      }
    });
  }

  Future<void> _refreshVideos() async {
    setState(() {
      _videoList.clear();
      _currentPage = 1;
      _hasMoreVideos = true;
    });
    await _loadVideos();
  }

  Widget _buildActionButtons(Map<String, dynamic> video) {
    final String videoUrl = video['video_url'] ?? '';
    final String videoId = video['post_id'] ?? '';
    final bool isDownloading = _downloadProgress.containsKey(videoId);
    final bool isDownloaded = _downloadedFiles.containsKey(videoId);
    final double progress = _downloadProgress[videoId] ?? 0.0;

    if (isDownloading) {
      return Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).primaryColor,
            ),
          ),
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              fontSize: 8,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      );
    } else if (isDownloaded) {
      return IconButton(
        icon: Icon(Icons.play_circle_outline, 
          color: Colors.white70,
          size: 20,
        ),
        tooltip: 'Open Video',
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        onPressed: () async {
          final filePath = _downloadedFiles[videoId];
          if (filePath != null) {
            if (Platform.isAndroid) {
              final uri = Uri.parse('content://$filePath');
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
                webViewConfiguration: WebViewConfiguration(
                  enableJavaScript: true,
                  enableDomStorage: true,
                ),
              );
            } else {
              final uri = Uri.file(filePath);
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            }
          }
        },
      );
    } else {
      return IconButton(
        icon: Icon(Icons.download_rounded, 
          color: Colors.white70,
          size: 20,
        ),
        tooltip: 'Download',
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        onPressed: () => _downloadVideo(videoUrl, videoId),
      );
    }
  }

  Future<void> _downloadVideo(String videoUrl, String videoId) async {
    try {
      setState(() {
        _downloadProgress[videoId] = 0;
      });

      final file = await ref.read(videoServiceProvider).downloadVideo(
        videoUrl,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[videoId] = progress;
          });
        },
      );

      setState(() {
        _downloadProgress.remove(videoId);
        _downloadedFiles[videoId] = file.path;
      });

      // Show a more compact success notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          width: MediaQuery.of(context).size.width * 0.9,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.check_circle, color: Colors.green, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Complete',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Saved to Downloads folder',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(Icons.play_circle_outline, size: 18),
                label: Text('Play', style: TextStyle(fontSize: 12)),
                onPressed: () async {
                  if (Platform.isAndroid) {
                    final uri = Uri.parse('content://${file.path}');
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                      webViewConfiguration: WebViewConfiguration(
                        enableJavaScript: true,
                        enableDomStorage: true,
                      ),
                    );
                  } else {
                    final uri = Uri.file(file.path);
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
              ),
            ],
          ),
          backgroundColor: Colors.grey[900],
          duration: Duration(seconds: 4),
        ),
      );
    } on VideoServiceException catch (e) {
      setState(() {
        _downloadProgress.remove(videoId);
      });
      
      // Show error notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          width: MediaQuery.of(context).size.width * 0.9,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.error_outline, color: Colors.red, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Failed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      e.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Retry', style: TextStyle(fontSize: 12)),
                onPressed: () => _downloadVideo(videoUrl, videoId),
              ),
            ],
          ),
          backgroundColor: Colors.grey[900],
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildVideoList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _videoList.length + (_hasMoreVideos ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _videoList.length) {
          return Center(
            child: TextButton(
              onPressed: _loadVideos,
              child: Text('Load More'),
            ),
          );
        }

        final video = _videoList[index];
        return Container(
          margin: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (video['thumbnail_url'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                  child: Image.network(
                    video['thumbnail_url'],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (video['caption'] != null)
                      Text(
                        video['caption'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                video['status']?.toLowerCase() == 'completed'
                                  ? Icons.check_circle
                                  : video['status']?.toLowerCase() == 'processing'
                                    ? Icons.sync
                                    : Icons.error,
                                color: _getStatusColor(video['status']),
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                video['status'] ?? 'Unknown',
                                style: TextStyle(
                                  color: _getStatusColor(video['status']),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(width: 12),
                              Icon(Icons.token, size: 14, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(
                                '${TokenCost.video}',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (video['video_url'] != null)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: _buildActionButtons(video),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Generation'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  backgroundColor: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
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
                                  size: 24,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
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
                                icon: Icon(Icons.close, color: Colors.white70),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: Colors.grey[800]),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildTipItem(
                                  Icons.timer,
                                  'Processing Time',
                                  'Video generation takes 2-5 minutes to complete',
                                ),
                                _buildTipItem(
                                  Icons.ad_units,
                                  'Optimized for Ads',
                                  'Currently designed for advertisement-style videos',
                                ),
                                _buildTipItem(
                                  Icons.smart_toy,
                                  'AI Technology',
                                  'Powered by Predis AI for short video generation',
                                ),
                                _buildTipItem(
                                  Icons.warning_amber,
                                  'Content Guidelines',
                                  '• No mature or adult content\n• No nudity or explicit material\n• No hate speech or abuse\n• No violence or harmful content',
                                ),
                                _buildTipItem(
                                  Icons.lightbulb,
                                  'Tips for Better Results',
                                  '• Use clear, descriptive language\n• Focus on product features\n• Keep prompts concise\n• Specify target audience',
                                ),
                                _buildTipItem(
                                  Icons.description,
                                  'Prompt Examples',
                                  '• "Create a product showcase for a modern smartwatch"\n• "Design a social media ad for a fitness app"\n• "Generate a promotional video for a coffee shop"',
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(height: 1, color: Colors.grey[800]),
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Got it',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: Duration(milliseconds: 300),
                height: _isGenerating ? 0 : null,
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).primaryColor,
                                  Theme.of(context).primaryColor.withOpacity(0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.movie_filter,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Video Generation',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.token, size: 14, color: Colors.amber),
                                    SizedBox(width: 4),
                                    Text(
                                      '${TokenCost.video} tokens per generation',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _promptController,
                        enabled: !_isGenerating,
                        decoration: InputDecoration(
                          hintText: 'Describe the video you want to generate...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.grey[850],
                          suffixIcon: Container(
                            margin: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).primaryColor,
                                  Theme.of(context).primaryColor.withOpacity(0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.movie_filter, color: Colors.white),
                                  onPressed: _generateVideo,
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          ),
                        ),
                        maxLines: 3,
                        onSubmitted: (_) => _generateVideo(),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _videoList.isEmpty && !_isGenerating
                  ? Center(
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _animation.value),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/bot_image.png',
                                  height: 120,
                                ),
                                SizedBox(height: 24),
                                Text(
                                  'Start generating amazing videos!',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_videoList.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.video_library, size: 20, color: Colors.grey[400]),
                                SizedBox(width: 8),
                                Text(
                                  'Your Videos',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            _buildVideoList(),
                          ],
                        ],
                      ),
                    ),
              ),
            ],
          ),
          if (_isGenerating)
            Container(
              color: Colors.black54,
              child: Center(
                child: _buildGeneratingOverlay(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTipItem(IconData icon, String title, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[300],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'processing':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRotatingIcon(Widget icon) {
    return RotationTransition(
      turns: _animationController,
      child: icon,
    );
  }

  Future<void> _loadVideos() async {
    if (_isLoadingVideos || !_hasMoreVideos) return;

    setState(() {
      _isLoadingVideos = true;
    });

    try {
      final response = await ref.read(videoServiceProvider).listVideos(
        page: _currentPage,
        limit: 10,
      );

      setState(() {
        _videoList.addAll(List<Map<String, dynamic>>.from(response['data'] ?? []));
        _hasMoreVideos = (response['data'] ?? []).length >= 10;
        _currentPage++;
        _isLoadingVideos = false;
      });
    } on VideoServiceException catch (e) {
      setState(() {
        _isLoadingVideos = false;
      });
      _showErrorView(e.error, e.message);
    }
  }

  void _showError(String message) {
    if (message.contains('API key not found')) {
      _showErrorView(VideoServiceError.apiKeyMissing, message);
    } else if (message.contains('Network connection error')) {
      _showErrorView(VideoServiceError.networkError, message);
    } else if (message.contains('timed out')) {
      _showErrorView(VideoServiceError.timeoutError, message);
    } else if (message.contains('Server responded')) {
      _showErrorView(VideoServiceError.serverError, message);
    } else {
      _showErrorView(VideoServiceError.unknownError, message);
    }
  }

  void _showErrorView(VideoServiceError error, String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ErrorView(
          error: error,
          message: message,
          onRetry: () {
            Navigator.pop(context);
            if (error == VideoServiceError.networkError || 
                error == VideoServiceError.timeoutError) {
              _loadVideos();
            }
          },
        ),
      ),
    );
  }

  Future<void> _cancelGeneration() async {
    if (_currentVideoId == null) return;

    try {
      // Show confirmation dialog
      final bool? shouldCancel = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.warning_amber_rounded, 
                    color: Colors.red,
                    size: 32,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Cancel Generation?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Are you sure you want to cancel\nthe video generation?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        'Keep',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (shouldCancel == true) {
        setState(() {
          _isGenerating = false;
          _currentVideoId = null;
        });

        // Show cancellation message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              width: MediaQuery.of(context).size.width * 0.9,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              content: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[800]?.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.info_outline, color: Colors.white70, size: 20),
                  ),
                  SizedBox(width: 12),
                  Text('Video generation cancelled'),
                ],
              ),
              backgroundColor: Colors.grey[900],
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Try to cancel on server in background
        try {
          await ref.read(videoServiceProvider).cancelGeneration(_currentVideoId!);
        } catch (e) {
          print('Error cancelling generation on server: $e');
          // Don't show error to user since we've already cancelled locally
        }
      }
    } catch (e) {
      print('Error in cancel dialog: $e');
    }
  }

  Widget _buildTokenBalance() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.token, size: 16, color: Theme.of(context).primaryColor),
          SizedBox(width: 4),
          ref.watch(tokenBalanceProvider).when(
            data: (balance) => Text(
              '$balance tokens',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            loading: () => SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
            ),
            error: (_, __) => Text(
              '-- tokens',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessNotification(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        width: MediaQuery.of(context).size.width * 0.9,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, color: Colors.green, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey[900],
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showErrorNotification(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        width: MediaQuery.of(context).size.width * 0.9,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.error_outline, color: Colors.red, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey[900],
        duration: Duration(seconds: 4),
      ),
    );
  }
} 