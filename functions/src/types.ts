export enum QueuePriority {
  high = 'high',
  medium = 'medium',
  low = 'low',
}

export enum GenerationStatus {
  pending = 'pending',
  processing = 'processing',
  completed = 'completed',
  failed = 'failed',
  cancelled = 'cancelled',
}

export enum GenerationType {
  video = 'video',
  image = 'image',
  audio = 'audio',
  text = 'text',
}

export interface GenerationRequest {
  id: string;
  userId: string;
  type: GenerationType;
  prompt: string;
  status: GenerationStatus;
  timestamp: Date;
  tokenCost: number;
  priority: QueuePriority;
  readyToProcess: boolean;
  attempts: number;
  maxAttempts: number;
  processingError?: string;
  processingStarted?: Date;
  processingCompleted?: Date;
  storageUrl?: string;
  apiResponse?: any;
  metadata: {
    isPublic?: boolean;
    subscriptionLevel?: string;
    [key: string]: any;
  };
}

export interface QueueItem {
  id: string;
  userId: string;
  timestamp: number;
}

export interface GenerationResult {
  isFile: boolean;
  data: any;
}

export interface SocialFeedItem {
  userId: string;
  requestId: string;
  type: GenerationType;
  prompt: string;
  result: string;
  likes: number;
  shares: number;
  comments: number;
  metadata: {
    isPublic: boolean;
    [key: string]: any;
  };
  createdAt: Date;
} 