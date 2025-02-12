import 'package:cloud_firestore/cloud_firestore.dart';
import 'generation_type.dart';

enum QueuePriority {
  high,
  medium,
  low;

  String get value {
    switch (this) {
      case QueuePriority.high:
        return 'high';
      case QueuePriority.medium:
        return 'medium';
      case QueuePriority.low:
        return 'low';
    }
  }

  static QueuePriority fromString(String value) {
    switch (value.toLowerCase()) {
      case 'high':
        return QueuePriority.high;
      case 'medium':
        return QueuePriority.medium;
      case 'low':
        return QueuePriority.low;
      default:
        return QueuePriority.low;
    }
  }
}

class GenerationRequest {
  final String id;
  final String userId;
  final GenerationType type;
  final String prompt;
  final String status;
  final DateTime timestamp;
  final int tokenCost;
  final Map<String, dynamic>? metadata;
  final double? progress;
  final int? queuePosition;
  final int? estimatedTimeRemaining;
  final Map<String, dynamic>? result;
  final String? errorMessage;
  final int attempts;
  final int maxAttempts;
  final String? processingError;
  final DateTime? processingStarted;
  final DateTime? processingCompleted;
  final String? storageUrl;
  final Map<String, dynamic>? apiResponse;
  final QueuePriority priority;
  final bool readyToProcess;

  bool get isInProgress => status == 'pending' || status == 'processing';
  bool get canCancel => status == 'pending' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get canRetry => isFailed && attempts < maxAttempts;
  String? get outputUrl => result?['outputUrl'] as String?;

  GenerationRequest({
    required this.id,
    required this.userId,
    required this.type,
    required this.prompt,
    required this.status,
    required this.timestamp,
    required this.tokenCost,
    this.metadata,
    this.progress = 0,
    this.queuePosition,
    this.estimatedTimeRemaining,
    this.result,
    this.errorMessage,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.processingError,
    this.processingStarted,
    this.processingCompleted,
    this.storageUrl,
    this.apiResponse,
    this.priority = QueuePriority.low,
    this.readyToProcess = false,
  });

  factory GenerationRequest.fromJson(Map<String, dynamic> json) {
    return GenerationRequest(
      id: json['id'] as String,
      userId: json['userId'] as String,
      type: GenerationType.values.firstWhere(
        (t) => t.toString().split('.').last == json['type'],
        orElse: () => GenerationType.image,
      ),
      prompt: json['prompt'] as String,
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      tokenCost: json['tokenCost'] as int,
      metadata: json['metadata'] as Map<String, dynamic>?,
      progress: json['progress'] as double?,
      queuePosition: json['queuePosition'] as int?,
      estimatedTimeRemaining: json['estimatedTimeRemaining'] as int?,
      result: json['result'] as Map<String, dynamic>?,
      errorMessage: json['errorMessage'] as String?,
      attempts: json['attempts']?.toInt() ?? 0,
      maxAttempts: json['maxAttempts']?.toInt() ?? 3,
      processingError: json['processingError'] as String?,
      processingStarted: json['processingStarted'] != null 
          ? DateTime.parse(json['processingStarted'])
          : null,
      processingCompleted: json['processingCompleted'] != null 
          ? DateTime.parse(json['processingCompleted'])
          : null,
      storageUrl: json['storageUrl'] as String?,
      apiResponse: json['apiResponse'] as Map<String, dynamic>?,
      priority: QueuePriority.fromString(json['priority'] ?? 'low'),
      readyToProcess: json['readyToProcess'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type.toString().split('.').last,
      'prompt': prompt,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      'tokenCost': tokenCost,
      'metadata': metadata,
      'progress': progress,
      'queuePosition': queuePosition,
      'estimatedTimeRemaining': estimatedTimeRemaining,
      'result': result,
      'errorMessage': errorMessage,
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      'processingError': processingError,
      'processingStarted': processingStarted?.toIso8601String(),
      'processingCompleted': processingCompleted?.toIso8601String(),
      'storageUrl': storageUrl,
      'apiResponse': apiResponse,
      'priority': priority.value,
      'readyToProcess': readyToProcess,
    };
  }

  GenerationRequest copyWith({
    String? id,
    String? userId,
    GenerationType? type,
    String? prompt,
    String? status,
    DateTime? timestamp,
    int? tokenCost,
    Map<String, dynamic>? metadata,
    double? progress,
    int? queuePosition,
    int? estimatedTimeRemaining,
    Map<String, dynamic>? result,
    String? errorMessage,
    int? attempts,
    int? maxAttempts,
    String? processingError,
    DateTime? processingStarted,
    DateTime? processingCompleted,
    String? storageUrl,
    Map<String, dynamic>? apiResponse,
    QueuePriority? priority,
    bool? readyToProcess,
  }) {
    return GenerationRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      prompt: prompt ?? this.prompt,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      tokenCost: tokenCost ?? this.tokenCost,
      metadata: metadata ?? this.metadata,
      progress: progress ?? this.progress,
      queuePosition: queuePosition ?? this.queuePosition,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      processingError: processingError ?? this.processingError,
      processingStarted: processingStarted ?? this.processingStarted,
      processingCompleted: processingCompleted ?? this.processingCompleted,
      storageUrl: storageUrl ?? this.storageUrl,
      apiResponse: apiResponse ?? this.apiResponse,
      priority: priority ?? this.priority,
      readyToProcess: readyToProcess ?? this.readyToProcess,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'type': type.toString().split('.').last,
      'prompt': prompt,
      'status': status,
      'timestamp': timestamp,
      'tokenCost': tokenCost,
      'metadata': metadata,
      'progress': progress,
      'queuePosition': queuePosition,
      'estimatedTimeRemaining': estimatedTimeRemaining,
      'result': result,
      'errorMessage': errorMessage,
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      'processingError': processingError,
      'processingStarted': processingStarted?.toIso8601String(),
      'processingCompleted': processingCompleted?.toIso8601String(),
      'storageUrl': storageUrl,
      'apiResponse': apiResponse,
      'priority': priority.value,
      'readyToProcess': readyToProcess,
    };
  }

  factory GenerationRequest.fromMap(Map<String, dynamic> map) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return null;
    }

    return GenerationRequest(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      type: GenerationType.values.firstWhere(
        (e) => e.value == map['type'],
        orElse: () => GenerationType.video,
      ),
      prompt: map['prompt'] ?? '',
      status: map['status'] ?? 'pending',
      timestamp: parseTimestamp(map['timestamp']) ?? DateTime.now(),
      tokenCost: map['tokenCost'] ?? 0,
      metadata: map['metadata'] != null ? Map<String, dynamic>.from(map['metadata'] as Map) : null,
      progress: (map['progress'] as num?)?.toDouble(),
      queuePosition: map['queuePosition'] as int?,
      estimatedTimeRemaining: map['estimatedTimeRemaining'] as int?,
      result: map['result'] != null ? Map<String, dynamic>.from(map['result'] as Map) : null,
      errorMessage: map['errorMessage'] as String?,
      attempts: map['attempts'] ?? 0,
      maxAttempts: map['maxAttempts'] ?? 3,
      processingError: map['processingError'] as String?,
      processingStarted: parseTimestamp(map['processingStarted']),
      processingCompleted: parseTimestamp(map['processingCompleted']),
      storageUrl: map['storageUrl'] as String?,
      apiResponse: map['apiResponse'] != null ? Map<String, dynamic>.from(map['apiResponse'] as Map) : null,
      priority: QueuePriority.fromString(map['priority'] ?? 'low'),
      readyToProcess: map['readyToProcess'] ?? false,
    );
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return queuePosition != null ? 'In Queue (#$queuePosition)' : 'Pending';
      case 'processing':
        return 'Processing${progress != null ? ' (${(progress! * 100).floor()}%)' : ''}';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed${errorMessage != null ? ': $errorMessage' : ''}';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
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