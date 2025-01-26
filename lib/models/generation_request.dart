import 'package:cloud_firestore/cloud_firestore.dart';
import 'generation_type.dart';

class GenerationRequest {
  final String id;
  final String userId;
  final GenerationType type;
  final String prompt;
  final GenerationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int priority;
  final int attempts;
  final int maxAttempts;
  final int? progress;
  final int retryCount;
  final Map<String, dynamic> metadata;
  final int tokensUsed;
  final String? error;
  final String? result;
  final int? queuePosition;
  final int? estimatedTimeRemaining;

  bool get isInProgress => status == GenerationStatus.pending || status == GenerationStatus.processing;
  bool get canRetry => status == GenerationStatus.failed && retryCount < maxAttempts;
  bool get canCancel => status == GenerationStatus.pending || status == GenerationStatus.processing;
  bool get isCompleted => status == GenerationStatus.completed;
  bool get isFailed => status == GenerationStatus.failed;

  GenerationRequest({
    required this.id,
    required this.userId,
    required this.type,
    required this.prompt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.priority,
    required this.attempts,
    required this.maxAttempts,
    this.progress,
    required this.retryCount,
    required this.metadata,
    required this.tokensUsed,
    this.error,
    this.result,
    this.queuePosition,
    this.estimatedTimeRemaining,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'type': type.toString().split('.').last,
      'prompt': prompt,
      'status': status.value,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'priority': priority,
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      'progress': progress,
      'retryCount': retryCount,
      'metadata': metadata,
      'tokensUsed': tokensUsed,
      'error': error,
      'result': result,
      'queuePosition': queuePosition,
      'estimatedTimeRemaining': estimatedTimeRemaining,
    };
  }

  factory GenerationRequest.fromMap(Map<String, dynamic> map) {
    return GenerationRequest(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      type: GenerationType.values.firstWhere(
        (t) => t.toString().split('.').last == map['type'],
        orElse: () => GenerationType.image,
      ),
      prompt: map['prompt'] ?? '',
      status: GenerationStatus.fromString(map['status'] ?? 'pending'),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      priority: map['priority']?.toInt() ?? 1,
      attempts: map['attempts']?.toInt() ?? 0,
      maxAttempts: map['maxAttempts']?.toInt() ?? 3,
      progress: map['progress']?.toInt(),
      retryCount: map['retryCount']?.toInt() ?? 0,
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      tokensUsed: map['tokensUsed']?.toInt() ?? 0,
      error: map['error'],
      result: map['result'],
      queuePosition: map['queuePosition']?.toInt(),
      estimatedTimeRemaining: map['estimatedTimeRemaining']?.toInt(),
    );
  }

  String get statusText {
    return switch (status) {
      GenerationStatus.queued => 'Queued${queuePosition != null ? ' (#$queuePosition)' : ''}',
      GenerationStatus.pending => 'Pending',
      GenerationStatus.processing => 'Processing${progress != null ? ' ($progress%)' : ''}',
      GenerationStatus.completed => 'Completed',
      GenerationStatus.failed => 'Failed${error != null ? ': $error' : ''}',
      GenerationStatus.cancelled => 'Cancelled',
    };
  }

  String get timeRemaining {
    if (estimatedTimeRemaining == null) return '';
    final minutes = (estimatedTimeRemaining! / 60).floor();
    final seconds = estimatedTimeRemaining! % 60;
    if (minutes > 0) {
      return '$minutes min ${seconds}s';
    }
    return '${seconds}s';
  }
} 