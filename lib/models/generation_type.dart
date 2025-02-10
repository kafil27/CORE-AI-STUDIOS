enum GenerationType {
  image,
  video,
  audio,
  text;

  String get value {
    switch (this) {
      case GenerationType.image:
        return 'image';
      case GenerationType.video:
        return 'video';
      case GenerationType.audio:
        return 'audio';
      case GenerationType.text:
        return 'text';
    }
  }

  String get displayName {
    switch (this) {
      case GenerationType.image:
        return 'Image';
      case GenerationType.video:
        return 'Video';
      case GenerationType.audio:
        return 'Audio';
      case GenerationType.text:
        return 'Text';
    }
  }

  int get defaultTokenCost {
    switch (this) {
      case GenerationType.image:
        return 10;
      case GenerationType.video:
        return 50;
      case GenerationType.audio:
        return 30;
      case GenerationType.text:
        return 5;
    }
  }

  String get icon {
    switch (this) {
      case GenerationType.image:
        return 'image';
      case GenerationType.video:
        return 'video';
      case GenerationType.audio:
        return 'audio';
      case GenerationType.text:
        return 'text';
    }
  }
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