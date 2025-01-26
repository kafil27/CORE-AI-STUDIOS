enum GenerationType {
  image,
  video,
  audio,
}

enum GenerationStatus {
  queued,
  pending,
  processing,
  completed,
  failed,
  cancelled;

  String get value {
    switch (this) {
      case GenerationStatus.queued:
        return 'queued';
      case GenerationStatus.pending:
        return 'pending';
      case GenerationStatus.processing:
        return 'processing';
      case GenerationStatus.completed:
        return 'completed';
      case GenerationStatus.failed:
        return 'failed';
      case GenerationStatus.cancelled:
        return 'cancelled';
    }
  }

  static GenerationStatus fromString(String value) {
    switch (value) {
      case 'queued':
        return GenerationStatus.queued;
      case 'pending':
        return GenerationStatus.pending;
      case 'processing':
        return GenerationStatus.processing;
      case 'completed':
        return GenerationStatus.completed;
      case 'failed':
        return GenerationStatus.failed;
      case 'cancelled':
        return GenerationStatus.cancelled;
      default:
        throw ArgumentError('Invalid status value: $value');
    }
  }
} 