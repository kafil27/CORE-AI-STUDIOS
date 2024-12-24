import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VoiceGenerationNotifier extends StateNotifier<String?> {
  VoiceGenerationNotifier() : super(null);

  Future<void> generateVoice(String text) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.example.com/generate-voice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        state = data['audioUrl'];
      } else {
        state = 'Error: Unable to generate voice';
      }
    } catch (e) {
      state = 'Error: $e';
    }
  }
}

final voiceGenerationProvider = StateNotifierProvider<VoiceGenerationNotifier, String?>((ref) {
  return VoiceGenerationNotifier();
}); 