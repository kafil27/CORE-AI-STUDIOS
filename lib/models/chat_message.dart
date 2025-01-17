class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String modelId;
  final String userId;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    required this.modelId,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'modelId': modelId,
      'userId': userId,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      content: map['content'] ?? '',
      isUser: map['isUser'] ?? true,
      timestamp: DateTime.parse(map['timestamp']),
      modelId: map['modelId'] ?? '',
      userId: map['userId'] ?? '',
    );
  }
} 