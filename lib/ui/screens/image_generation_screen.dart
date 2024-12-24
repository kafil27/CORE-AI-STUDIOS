import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/image_generation_provider.dart';

class ImageGenerationScreen extends ConsumerWidget {
  final TextEditingController promptController = TextEditingController();

  ImageGenerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.watch(imageGenerationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Image Generation')),
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
                  ref.read(imageGenerationProvider.notifier).generateImage(prompt);
                }
              },
              child: const Text('Generate Image'),
            ),
            const SizedBox(height: 16),
            if (imageUrl != null)
              imageUrl.startsWith('Error')
                  ? Text(imageUrl, style: const TextStyle(color: Colors.red))
                  : Image.network(imageUrl),
          ],
        ),
      ),
    );
  }
} 