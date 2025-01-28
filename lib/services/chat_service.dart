import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/chat_message.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String mistralApiKey = dotenv.env['MISTRAL_API_KEY'] ?? '';
  final String openaiApiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  final String geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  final String getimgApiKey = dotenv.env['GETIMG_API_KEY'] ?? '';

  // Check if prompt contains image generation request
  bool _isImageGenerationPrompt(String prompt) {
    final imageKeywords = [
      'generate image',
      'create image',
      'draw',
      'picture',
      'photo',
      'image of',
      'generate a picture',
      'create a picture',
      'generate an image',
      'create an image',
      'make an image',
      'make a picture',
      'create a photo',
      'generate a photo',
      'draw me',
      'create art',
      'generate art',
    ];

    return imageKeywords.any((keyword) => 
      prompt.toLowerCase().contains(keyword.toLowerCase()));
  }

  // Get chat messages for a user
  Stream<List<ChatMessage>> getChatMessages(String userId, String modelId) {
    return _firestore
        .collection('chats')
        .doc(userId)
        .collection('messages')
        .where('modelId', isEqualTo: modelId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ChatMessage.fromMap(doc.data(), doc.id);
          }).toList();
        });
  }

  // Save a new message
  Future<void> saveMessage(ChatMessage message) async {
    final messageData = message.toMap();
    messageData['createdAt'] = FieldValue.serverTimestamp();

    await _firestore
        .collection('chats')
        .doc(message.userId)
        .collection('messages')
        .add(messageData);
  }

  // Get AI response based on selected model
  Future<String> getAIResponse(String prompt, String modelId) async {
    // Check for image generation request
    if (_isImageGenerationPrompt(prompt)) {
      throw Exception('Image generation is not supported in chat. Please use the Image Generation feature from the home screen.');
    }

    switch (modelId) {
      case 'mistral':
        return await getMistralResponse(prompt);
      case 'gpt':
        return await getOpenAIResponse(prompt);
      case 'gemini':
        return await getGeminiResponse(prompt);
      default:
        throw Exception('Unknown model selected');
    }
  }

  // Get response from Mistral
  Future<String> getMistralResponse(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.mistral.ai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $mistralApiKey',
        },
        body: jsonEncode({
          'model': 'mistral-tiny',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 800,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('Failed to get Mistral response: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error connecting to Mistral AI: $e');
    }
  }

  // Get response from OpenAI
  Future<String> getOpenAIResponse(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openaiApiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 800,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('Failed to get OpenAI response: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error connecting to OpenAI: $e');
    }
  }

  // Get response from Gemini
  Future<String> getGeminiResponse(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$geminiApiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 800,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        throw Exception('Failed to get Gemini response: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error connecting to Gemini: $e');
    }
  }

  // Delete a message
  Future<void> deleteMessage(String userId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(userId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  // Clear chat history
  Future<void> clearChatHistory(String userId, String modelId) async {
    final messages = await _firestore
        .collection('chats')
        .doc(userId)
        .collection('messages')
        .where('modelId', isEqualTo: modelId)
        .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
} 