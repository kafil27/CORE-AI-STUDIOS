import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/video_generation_provider.dart';

class VideoGenerationScreen extends ConsumerWidget {
  final TextEditingController promptController = TextEditingController();

  VideoGenerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videoUrl = ref.watch(videoGenerationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Video Generation')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: promptController,
              decoration: const InputDecoration(labelText: 'Enter prompt'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final prompt = promptController.text;
                if (prompt.isNotEmpty) {
                  ref.read(videoGenerationProvider.notifier).generateVideo(prompt);
                }
              },
              child: const Text('Generate Video'),
            ),
            const SizedBox(height: 16),
            if (videoUrl != null)
              videoUrl.startsWith('Error')
                  ? Text(videoUrl, style: const TextStyle(color: Colors.red))
                  : Text('Video generated: $videoUrl'),
          ],
        ),
      ),
    );
  }
} 