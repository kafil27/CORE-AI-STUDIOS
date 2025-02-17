import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import '../../services/predis_video_service.dart';
import '../../services/notification_service.dart';
import '../../config/ai_service_config.dart';

class GeneratedVideoCard extends StatefulWidget {
  final String videoId;
  final String videoUrl;
  final String thumbnailUrl;
  final String filename;
  final String prompt;
  final bool isDownloaded;
  final VoidCallback? onRegenerate;

  const GeneratedVideoCard({
    Key? key,
    required this.videoId,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.filename,
    required this.prompt,
    this.isDownloaded = false,
    this.onRegenerate,
  }) : super(key: key);

  @override
  State<GeneratedVideoCard> createState() => _GeneratedVideoCardState();
}

class _GeneratedVideoCardState extends State<GeneratedVideoCard> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _localPath;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    if (widget.isDownloaded && _localPath != null) {
      _controller = VideoPlayerController.file(File(_localPath!));
    } else {
      _controller = VideoPlayerController.network(widget.videoUrl);
    }

    try {
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
      });
      _controller.addListener(() {
        if (_controller.value.isPlaying != _isPlaying) {
          setState(() {
            _isPlaying = _controller.value.isPlaying;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }

  Future<void> _downloadVideo(BuildContext context) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      // Get the downloads directory
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception('Could not access external storage');
      }

      // Create core_ai_studio directory structure
      final baseDir = Directory('${directory.path}/core_ai_studio/generated_content/video');
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      final file = File('${baseDir.path}/${widget.filename}');
      
      // Download with progress tracking
      final response = await http.Client().send(
        http.Request('GET', Uri.parse(widget.videoUrl))
          ..headers['Accept'] = 'video/mp4'
      );

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 0;
        int received = 0;

        final sink = file.openWrite();
        await response.stream.map((chunk) {
          received += chunk.length;
          setState(() {
            _downloadProgress = contentLength > 0 ? received / contentLength : 0;
          });
          return chunk;
        }).pipe(sink);
        await sink.close();

        setState(() {
          _localPath = file.path;
          _isDownloading = false;
          _downloadProgress = 1.0;
        });

        // Mark as downloaded in Firestore
        await PredisVideoService(
          firestore: FirebaseFirestore.instance,
          auth: FirebaseAuth.instance,
          config: PredisAIConfig(),
        ).markVideoAsDownloaded(widget.videoId);

        // Reinitialize player with local file
        await _controller.dispose();
        await _initializePlayer();

        NotificationService.showSuccess(
          context: context,
          title: 'Download Complete',
          message: 'Video saved to ${baseDir.path}',
        );
      } else {
        throw Exception('Failed to download video');
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
      });
      
      NotificationService.showError(
        context: context,
        title: 'Download Failed',
        message: 'Failed to download video: ${e.toString()}',
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video preview or thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isInitialized && _isPlaying)
                  VideoPlayer(_controller)
                else
                  CachedNetworkImage(
                    imageUrl: widget.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                // Play/Pause button
                if (_isInitialized)
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 48,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                        _isPlaying = !_isPlaying;
                      });
                    },
                  ),
              ],
            ),
          ),
          // Video information
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.filename,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.prompt,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (!widget.isDownloaded && !_isDownloading)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                        onPressed: () => _downloadVideo(context),
                      )
                    else if (_isDownloading)
                      CircularProgressIndicator(
                        value: _downloadProgress,
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: widget.onRegenerate,
                      tooltip: 'Regenerate Video',
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen),
                      onPressed: () {
                        // TODO: Implement fullscreen view
                      },
                      tooltip: 'Open in Editor',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 