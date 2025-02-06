import 'package:cloud_firestore/cloud_firestore.dart';
import 'generation_type.dart';
import 'package:flutter/foundation.dart';

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
  final String? errorMessage;
  final String? outputUrl;
  final String? generatedFileName;
  final Map<String, dynamic>? metadata;
  final int? progress;
  final int? queuePosition;
  final int? estimatedTimeRemaining;
  final QueuePriority priority;
  final bool readyToProcess;
  final int attempts;
  final int maxAttempts;
  final String? processingError;
  final DateTime? processingStarted;
  final DateTime? processingCompleted;
  final String? storageUrl;
  final Map<String, dynamic>? apiResponse;

  bool get isInProgress => status == 'pending' || status == 'processing';
  bool get canCancel => status == 'pending' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get canRetry => isFailed && attempts < maxAttempts;
  String? get error => errorMessage;
  String? get result => outputUrl;

  GenerationRequest({
    required this.id,
    required this.userId,
    required this.type,
    required this.prompt,
    required this.status,
    required this.timestamp,
    required this.tokenCost,
    this.errorMessage,
    this.outputUrl,
    this.generatedFileName,
    this.metadata,
    this.progress,
    this.queuePosition,
    this.estimatedTimeRemaining,
    this.priority = QueuePriority.low,
    this.readyToProcess = false,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.processingError,
    this.processingStarted,
    this.processingCompleted,
    this.storageUrl,
    this.apiResponse,
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
      errorMessage: json['errorMessage'] as String?,
      outputUrl: json['outputUrl'] as String?,
      generatedFileName: json['generatedFileName'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      progress: json['progress'] as int?,
      queuePosition: json['queuePosition'] as int?,
      estimatedTimeRemaining: json['estimatedTimeRemaining'] as int?,
      priority: QueuePriority.fromString(json['priority'] ?? 'low'),
      readyToProcess: json['readyToProcess'] ?? false,
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
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (outputUrl != null) 'outputUrl': outputUrl,
      if (generatedFileName != null) 'generatedFileName': generatedFileName,
      if (metadata != null) 'metadata': metadata,
      if (progress != null) 'progress': progress,
      if (queuePosition != null) 'queuePosition': queuePosition,
      if (estimatedTimeRemaining != null) 'estimatedTimeRemaining': estimatedTimeRemaining,
      'priority': priority.value,
      'readyToProcess': readyToProcess,
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      if (processingError != null) 'processingError': processingError,
      if (processingStarted != null) 'processingStarted': processingStarted?.toIso8601String(),
      if (processingCompleted != null) 'processingCompleted': processingCompleted?.toIso8601String(),
      if (storageUrl != null) 'storageUrl': storageUrl,
      if (apiResponse != null) 'apiResponse': apiResponse,
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
    String? errorMessage,
    String? outputUrl,
    String? generatedFileName,
    Map<String, dynamic>? metadata,
    int? progress,
    int? queuePosition,
    int? estimatedTimeRemaining,
    QueuePriority? priority,
    bool? readyToProcess,
    int? attempts,
    int? maxAttempts,
    String? processingError,
    DateTime? processingStarted,
    DateTime? processingCompleted,
    String? storageUrl,
    Map<String, dynamic>? apiResponse,
  }) {
    return GenerationRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      prompt: prompt ?? this.prompt,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      tokenCost: tokenCost ?? this.tokenCost,
      errorMessage: errorMessage ?? this.errorMessage,
      outputUrl: outputUrl ?? this.outputUrl,
      generatedFileName: generatedFileName ?? this.generatedFileName,
      metadata: metadata ?? this.metadata,
      progress: progress ?? this.progress,
      queuePosition: queuePosition ?? this.queuePosition,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      priority: priority ?? this.priority,
      readyToProcess: readyToProcess ?? this.readyToProcess,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      processingError: processingError ?? this.processingError,
      processingStarted: processingStarted ?? this.processingStarted,
      processingCompleted: processingCompleted ?? this.processingCompleted,
      storageUrl: storageUrl ?? this.storageUrl,
      apiResponse: apiResponse ?? this.apiResponse,
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
      'errorMessage': errorMessage,
      'outputUrl': outputUrl,
      'generatedFileName': generatedFileName,
      'metadata': metadata,
      'progress': progress,
      'queuePosition': queuePosition,
      'estimatedTimeRemaining': estimatedTimeRemaining,
      'priority': priority.value,
      'readyToProcess': readyToProcess,
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      'processingError': processingError,
      'processingStarted': processingStarted?.toIso8601String(),
      'processingCompleted': processingCompleted?.toIso8601String(),
      'storageUrl': storageUrl,
      'apiResponse': apiResponse,
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
      status: map['status'] ?? '',
      timestamp: map['timestamp'] is Timestamp 
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.parse(map['timestamp'].toString()),
      tokenCost: map['tokenCost']?.toInt() ?? 0,
      errorMessage: map['errorMessage'],
      outputUrl: map['outputUrl'],
      generatedFileName: map['generatedFileName'],
      metadata: map['metadata'] as Map<String, dynamic>?,
      progress: map['progress'] as int?,
      queuePosition: map['queuePosition'] as int?,
      estimatedTimeRemaining: map['estimatedTimeRemaining'] as int?,
      priority: QueuePriority.fromString(map['priority'] ?? 'low'),
      readyToProcess: map['readyToProcess'] ?? false,
      attempts: map['attempts']?.toInt() ?? 0,
      maxAttempts: map['maxAttempts']?.toInt() ?? 3,
      processingError: map['processingError'],
      processingStarted: map['processingStarted'] != null 
          ? DateTime.parse(map['processingStarted'])
          : null,
      processingCompleted: map['processingCompleted'] != null 
          ? DateTime.parse(map['processingCompleted'])
          : null,
      storageUrl: map['storageUrl'],
      apiResponse: map['apiResponse'] as Map<String, dynamic>?,
    );
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return queuePosition != null ? 'In Queue (#$queuePosition)' : 'Pending';
      case 'processing':
        return 'Processing${progress != null ? ' ($progress%)' : ''}';
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