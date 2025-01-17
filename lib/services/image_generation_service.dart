import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ImageGenerationService {
  final String deepAiApiKey = '8dd3a047-b8a1-4aa0-b85f-6bb2b71cf886';

  Future<String> generateImage(String prompt) async {
    try {
      print('Generating image with prompt: $prompt');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.deepai.org/api/text2img'),
      );

      // Add the API key header
      request.headers['api-key'] = deepAiApiKey;

      // Add the text field
      request.fields['text'] = prompt;

      print('Sending request to DeepAI...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      print('Response headers: ${response.headers}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Parsed response data: $data');
        
        if (data['output_url'] != null) {
          print('Generated image URL: ${data['output_url']}');
          return data['output_url'];
        }
        throw Exception('No image URL in response: $data');
      } else {
        Map<String, dynamic> errorData;
        try {
          errorData = jsonDecode(response.body);
          print('Error data: $errorData');
        } catch (e) {
          print('Error parsing error response: $e');
          errorData = {'error': 'Failed to parse error response'};
        }

        String errorMessage = errorData['error'] ?? 'Unknown error occurred';
        print('Error message from API: $errorMessage');
        
        if (response.statusCode == 401) {
          throw Exception('API key invalid or expired. Please check your API key.');
        } else if (response.statusCode == 429) {
          throw Exception('Rate limit exceeded. Please try again later.');
        }
        
        throw Exception('API Error (${response.statusCode}): $errorMessage');
      }
    } catch (e) {
      print('Error details: $e');
      if (e.toString().contains('unexpected end of input')) {
        throw Exception('Invalid response from API. Please try again.');
      }
      throw Exception('Error generating image: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<File> downloadImage(String imageUrl) async {
    try {
      print('Downloading image from: $imageUrl');
      final response = await http.get(Uri.parse(imageUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to download image: ${response.statusCode}');
      }

      final documentsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${documentsDir.path}/generated_image_$timestamp.png');
      await file.writeAsBytes(response.bodyBytes);
      print('Image saved to: ${file.path}');
      return file;
    } catch (e) {
      print('Download error: $e');
      throw Exception('Error downloading image: $e');
    }
  }

  Future<void> saveToGoogleDrive(File imageFile) async {
    // TODO: Implement Google Drive integration
    // For now, we'll just open the file in the default viewer
    final uri = Uri.file(imageFile.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
} 