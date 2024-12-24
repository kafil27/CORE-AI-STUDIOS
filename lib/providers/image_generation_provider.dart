import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ImageGenerationNotifier extends StateNotifier<String?> {
  ImageGenerationNotifier() : super(null);

  Future<void> generateImage(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.example.com/generate-image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        state = data['imageUrl'];
      } else {
        state = 'Error: Unable to generate image';
      }
    } catch (e) {
      state = 'Error: $e';
    }
  }
}

final imageGenerationProvider = StateNotifierProvider<ImageGenerationNotifier, String?>((ref) {
  return ImageGenerationNotifier();
}); 