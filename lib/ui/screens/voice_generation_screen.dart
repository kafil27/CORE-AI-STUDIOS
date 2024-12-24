import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/voice_generation_provider.dart';

class VoiceGenerationScreen extends ConsumerWidget {
  final TextEditingController textController = TextEditingController();

  VoiceGenerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioUrl = ref.watch(voiceGenerationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Synthesis')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(labelText: 'Enter text'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final text = textController.text;
                if (text.isNotEmpty) {
                  ref.read(voiceGenerationProvider.notifier).generateVoice(text);
                }
              },
              child: const Text('Generate Voice'),
            ),
            const SizedBox(height: 16),
            if (audioUrl != null)
              audioUrl.startsWith('Error')
                  ? Text(audioUrl, style: const TextStyle(color: Colors.red))
                  : Text('Audio generated: $audioUrl'),
          ],
        ),
      ),
    );
  }
} 