import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatNotifier extends StateNotifier<List<Message>> {
  ChatNotifier() : super([]);

  void addMessage(Message message) {
    state = [...state, message];
  }

  Future<void> sendMessage(String text) async {
    // Add user message
    addMessage(Message(text: text, isUser: true));

    // Replace with actual API call
    try {
      final response = await http.post(
        Uri.parse('https://api.example.com/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiResponse = data['response'];
        addMessage(Message(text: aiResponse, isUser: false));
      } else {
        addMessage(Message(text: 'Error: Unable to get response', isUser: false));
      }
    } catch (e) {
      addMessage(Message(text: 'Error: $e', isUser: false));
    }
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<Message>>((ref) {
  return ChatNotifier();
}); 