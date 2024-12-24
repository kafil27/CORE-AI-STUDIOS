import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VideoGenerationNotifier extends StateNotifier<String?> {
  VideoGenerationNotifier() : super(null);

  Future<void> generateVideo(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.example.com/generate-video'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        state = data['videoUrl'];
      } else {
        state = 'Error: Unable to generate video';
      }
    } catch (e) {
      state = 'Error: $e';
    }
  }
}

final videoGenerationProvider = StateNotifierProvider<VideoGenerationNotifier, String?>((ref) {
  return VideoGenerationNotifier();
}); 