import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/chat_message.dart';
import '../../../services/chat_service.dart';
import 'package:uuid/uuid.dart';

final selectedModelProvider = StateProvider<String>((ref) => 'mistral');
final chatServiceProvider = Provider((ref) => ChatService());

class ChatAIScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatAIScreen> createState() => _ChatAIScreenState();
}

class _ChatAIScreenState extends ConsumerState<ChatAIScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  final List<Map<String, dynamic>> _models = [
    {
      'id': 'mistral',
      'name': 'Mistral AI',
      'icon': Icons.auto_awesome,
    },
    {
      'id': 'gemini',
      'name': 'Google Gemini',
      'icon': Icons.psychology,
    },
    {
      'id': 'gpt',
      'name': 'ChatGPT',
      'icon': Icons.chat_bubble,
    },
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    _messageController.clear();

    try {
      final selectedModel = ref.read(selectedModelProvider);
      final chatService = ref.read(chatServiceProvider);

      // Save user message
      final userMessage = ChatMessage(
        id: const Uuid().v4(),
        content: message,
        isUser: true,
        timestamp: DateTime.now(),
        modelId: selectedModel,
        userId: user.uid,
      );
      await chatService.saveMessage(userMessage);

      // Get AI response
      try {
        final response = await chatService.getAIResponse(message, selectedModel);
        
        // Save AI response
        final aiMessage = ChatMessage(
          id: const Uuid().v4(),
          content: response,
          isUser: false,
          timestamp: DateTime.now(),
          modelId: selectedModel,
          userId: user.uid,
        );
        await chatService.saveMessage(aiMessage);
      } catch (e) {
        if (e.toString().contains('Image generation')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              action: SnackBarAction(
                label: 'Go to Image Gen',
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          );
        } else {
          rethrow;
        }
      }

      // Scroll to bottom
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedModel = ref.watch(selectedModelProvider);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              'AI Chat',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              'Using ${_models.firstWhere((m) => m['id'] == selectedModel)['name']}',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.model_training),
            onSelected: (modelId) {
              ref.read(selectedModelProvider.notifier).state = modelId;
            },
            itemBuilder: (context) {
              return _models.map((model) {
                return PopupMenuItem<String>(
                  value: model['id'] as String,
                  child: Row(
                    children: [
                      Icon(
                        model['icon'] as IconData,
                        color: selectedModel == model['id']
                            ? Theme.of(context).primaryColor
                            : null,
                      ),
                      SizedBox(width: 8),
                      Text(model['name'] as String),
                      if (selectedModel == model['id'])
                        Icon(Icons.check, size: 16),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: user == null
                ? Center(child: Text('Please sign in to use chat'))
                : StreamBuilder<List<ChatMessage>>(
                    stream: ref
                        .read(chatServiceProvider)
                        .getChatMessages(user.uid, selectedModel),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      if (!snapshot.hasData) {
                        return Center(child: CircularProgressIndicator());
                      }

                      final messages = snapshot.data!;
                      if (messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 48,
                                color: Colors.grey[700],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Start a conversation',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return _ChatBubble(
                            message: message,
                            isLatest: index == 0 && _isLoading,
                          );
                        },
                      );
                    },
                  ),
          ),
          if (user != null) _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey[800]!,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[900],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: _isLoading
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    )
                  : Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: _sendMessage,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.send_rounded,
                            color: Colors.tealAccent,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLatest;

  const _ChatBubble({
    required this.message,
    this.isLatest = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).primaryColor.withOpacity(0.2)
              : Colors.grey[900],
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: message.isUser ? Radius.circular(0) : null,
            bottomLeft: !message.isUser ? Radius.circular(0) : null,
          ),
          border: Border.all(
            color: message.isUser
                ? Theme.of(context).primaryColor.withOpacity(0.5)
                : Colors.grey[800]!,
            width: 1,
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Stack(
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: message.isUser ? Colors.white : Colors.grey[300],
              ),
            ),
            if (!message.isUser && isLatest)
              Positioned(
                right: 0,
                bottom: 0,
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
} 