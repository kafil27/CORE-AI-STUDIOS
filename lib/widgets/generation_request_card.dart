import 'dart:io';
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/generation_request.dart';

class GenerationRequestCard extends StatefulWidget {
  final GenerationRequest request;
  final bool isExpanded;
  final Function(String)? onRetry;

  const GenerationRequestCard({
    Key? key,
    required this.request,
    this.isExpanded = false,
    this.onRetry,
  }) : super(key: key);

  @override
  State<GenerationRequestCard> createState() => _GenerationRequestCardState();
}

class _GenerationRequestCardState extends State<GenerationRequestCard> {
  double? _downloadProgress;

  Future<Widget> _buildVideoThumbnail(String videoUrl) async {
    try {
      final uint8List = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128,
        quality: 25,
      );
      
      if (uint8List == null) {
        return const Icon(Icons.video_file, size: 48);
      }
      
      return Image.memory(uint8List, fit: BoxFit.cover);
    } catch (e) {
      return const Icon(Icons.video_file, size: 48);
    }
  }

  Widget _buildThumbnailSection(String videoUrl) {
    return FutureBuilder<Widget>(
      future: _buildVideoThumbnail(videoUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: LoadingAnimationWidget.staggeredDotsWave(
              color: Theme.of(context).primaryColor,
              size: 40,
            ),
          );
        }
        
        if (snapshot.hasError || !snapshot.hasData) {
          return const Icon(Icons.video_file, size: 48);
        }
        
        return snapshot.data!;
      },
    );
  }

  Future<void> _downloadVideo(String url) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      
      final List<int> bytes = [];
      
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        
        final progress = contentLength > 0 ? downloaded / contentLength : 0.0;
        setState(() {
          _downloadProgress = progress;
        });
      }
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await file.writeAsBytes(bytes);
      
      setState(() {
        _downloadProgress = null;
      });
      
    } catch (e) {
      setState(() {
        _downloadProgress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoUrl = widget.request.outputUrl ?? widget.request.storageUrl;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(widget.request.prompt),
            subtitle: Text(widget.request.status),
            trailing: videoUrl != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_downloadProgress != null)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            value: _downloadProgress,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadVideo(videoUrl),
                        ),
                      IconButton(
                        icon: const Icon(Icons.open_in_browser),
                        onPressed: () => launchUrl(Uri.parse(videoUrl)),
                      ),
                    ],
                  )
                : null,
          ),
          if (videoUrl != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildThumbnailSection(videoUrl),
            ),
          if (widget.request.errorMessage != null && widget.onRetry != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () => widget.onRetry?.call(widget.request.id),
                child: const Text('Retry'),
              ),
            ),
        ],
      ),
    );
  }
} 