import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum ImageModel {
  stable_diffusion_v3,
  core_diffusion,
  ultra_diffusion,
}

class ImageGenerationException implements Exception {
  final String message;
  final String? technicalDetails;

  ImageGenerationException(this.message, {this.technicalDetails}) {
    if (technicalDetails != null) {
      print('ImageService Error: $message');
      print('Technical Details: $technicalDetails');
    }
  }

  @override
  String toString() => message;
}

class ImageGenerationService {
  final String apiKey = dotenv.env['STABILITY_API_KEY'] ?? '';
  final String baseUrl = 'https://api.stability.ai/v1';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<String> generateImage(String prompt, {
    ImageModel model = ImageModel.stable_diffusion_v3,
    int width = 1024,
    int height = 1024,
    int steps = 30,
    double cfgScale = 7.0,
    String style = 'enhance',
    int samples = 1,
  }) async {
    if (apiKey.isEmpty) {
      throw ImageGenerationException(
        'API key is missing',
        technicalDetails: 'Stability AI API key not found in environment variables',
      );
    }

    try {
      final endpoint = _getEndpoint(model);
      final uri = Uri.parse('$baseUrl$endpoint');

      final Map<String, dynamic> requestBody = {
        'text_prompts': [
          {
            'text': prompt,
          }
        ],
        'cfg_scale': cfgScale,
        'height': height,
        'width': width,
        'steps': steps,
        'samples': samples,
        'style_preset': style,
      };

      print('Sending request to: $uri');
      print('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(requestBody),
      ).timeout(
        Duration(seconds: 60),
        onTimeout: () {
          throw ImageGenerationException(
            'Request timed out',
            technicalDetails: 'Generation request timed out after 60 seconds',
          );
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = data['artifacts'] as List;
        if (images.isNotEmpty) {
          final base64Image = images[0]['base64'];
          return 'data:image/png;base64,$base64Image';
        }
        throw ImageGenerationException(
          'No image generated',
          technicalDetails: 'Response contained no images',
        );
      } else {
        _handleApiError(response.statusCode, response.body);
      }
    } catch (e) {
      if (e is ImageGenerationException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        throw ImageGenerationException(
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
      throw ImageGenerationException(
        'Failed to generate image',
        technicalDetails: e.toString(),
      );
    }

    throw ImageGenerationException(
      'Unknown error occurred',
      technicalDetails: 'No response data available',
    );
  }

  String _getEndpoint(ImageModel model) {
    switch (model) {
      case ImageModel.stable_diffusion_v3:
        return '/generation/stable-diffusion-xl-1024-v1-0/text-to-image';
      case ImageModel.core_diffusion:
        return '/generation/stable-diffusion-v1-6/text-to-image';
      case ImageModel.ultra_diffusion:
        return '/generation/stable-diffusion-xl-1024-v1-0/text-to-image';
    }
  }

  void _handleApiError(int statusCode, String body) {
    Map<String, dynamic> errorData;
    try {
      errorData = jsonDecode(body);
    } catch (_) {
      errorData = {'message': 'Unknown error occurred'};
    }

    final message = errorData['message'] ?? 'Unknown error occurred';
    
    switch (statusCode) {
      case 400:
        throw ImageGenerationException(
          'Invalid request parameters',
          technicalDetails: message,
        );
      case 401:
        throw ImageGenerationException(
          'Invalid API key',
          technicalDetails: message,
        );
      case 403:
        throw ImageGenerationException(
          'Access denied',
          technicalDetails: message,
        );
      case 429:
        throw ImageGenerationException(
          'Rate limit exceeded',
          technicalDetails: message,
        );
      default:
        throw ImageGenerationException(
          'Server error occurred',
          technicalDetails: 'Status code: $statusCode, Message: $message',
        );
    }
  }

  Future<File> downloadImage(String imageUrl) async {
    try {
      final bytes = base64.decode(imageUrl.split(',')[1]);
      
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/generated_image_$timestamp.png');
      
      await file.writeAsBytes(bytes);
      print('Image saved to: ${file.path}');
      return file;
    } catch (e) {
      throw ImageGenerationException(
        'Failed to save image',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<void> openImage(File imageFile) async {
    final uri = Uri.file(imageFile.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw ImageGenerationException(
        'Could not open image',
        technicalDetails: 'Failed to launch URL: $uri',
      );
    }
  }
} 