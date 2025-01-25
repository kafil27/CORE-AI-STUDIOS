import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { defineInt } from 'firebase-functions/params';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

// Initialize Firebase Admin
initializeApp();

// Set global options
setGlobalOptions({
  maxInstances: 10,
  timeoutSeconds: 540,
  memory: '1GiB',
  region: 'us-central1'
});

// Environment parameters
const maxConcurrentRequests = defineInt('MAX_CONCURRENT_REQUESTS', { default: 5 });
const requestTimeoutMinutes = defineInt('REQUEST_TIMEOUT_MINUTES', { default: 10 });

// Constants
const REQUEST_TIMEOUT = requestTimeoutMinutes.value() * 60 * 1000;

// API Key Management
interface ApiKeyConfig {
  key: string;
  service: 'stability' | 'getimg' | 'predis' | 'custom';
  usageCount: number;
  lastUsed: Timestamp;
  dailyLimit: number;
  isActive: boolean;
}

interface UserTier {
  name: 'free' | 'premium' | 'enterprise';
  maxConcurrentRequests: number;
  priorityLevel: number;
  maxQueueSize: number;
}

// Enhanced Generation Request
interface GenerationRequest {
  id: string;
  userId: string;
  type: 'image' | 'video' | 'audio';
  prompt: string;
  status: 'queued' | 'pending' | 'processing' | 'completed' | 'failed';
  createdAt: Timestamp;
  updatedAt: Timestamp;
  startedAt?: Timestamp;
  completedAt?: Timestamp;
  result?: string;
  error?: string;
  tokensUsed?: number;
  priority: number;
  attempts: number;
  maxAttempts: number;
  apiKeyUsed?: string;
  serviceUsed?: string;
  progress?: number;
  estimatedTimeRemaining?: number;
  metadata?: {
    width?: number;
    height?: number;
    style?: string;
    duration?: number;
    quality?: string;
    [key: string]: any;
  };
  userTier: UserTier;
  retryCount: number;
  queuePosition?: number;
}

// Helper Functions
async function updateUserTokens(userId: string, tokensToDeduct: number): Promise<boolean> {
  const db = getFirestore();
  
  try {
    const userRef = db.collection('users').doc(userId);
    
    return await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      if (!userDoc.exists) {
        throw new HttpsError('not-found', 'User not found');
      }
      
      const currentTokens = userDoc.data()?.tokens || 0;
      if (currentTokens < tokensToDeduct) {
        return false;
      }
      
      transaction.update(userRef, {
        tokens: currentTokens - tokensToDeduct,
        'token_history': FieldValue.arrayUnion({
          amount: -tokensToDeduct,
          timestamp: Timestamp.now(),
          type: 'deduction'
        })
      });
      
      return true;
    });
  } catch (error) {
    console.error('Error updating user tokens:', error);
    throw new HttpsError('internal', 'Failed to update user tokens');
  }
}

async function processNextInQueue() {
  const db = getFirestore();
  const queue = db.collection('generation_queue');
  
  try {
    // Get active requests count per user tier
    const activeRequests = await queue
      .where('status', '==', 'processing')
      .get();
      
    const activeRequestsByTier = activeRequests.docs.reduce((acc, doc) => {
      const request = doc.data() as GenerationRequest;
      acc[request.userTier.name] = (acc[request.userTier.name] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    // Get next pending request with highest priority
    const nextRequest = await queue
      .where('status', 'in', ['queued', 'pending'])
      .orderBy('priority', 'desc')
      .orderBy('createdAt', 'asc')
      .limit(10)
      .get();
      
    if (nextRequest.empty) return;

    // Find the first request that can be processed based on tier limits
    const eligibleRequest = nextRequest.docs.find(doc => {
      const request = doc.data() as GenerationRequest;
      const activeTierRequests = activeRequestsByTier[request.userTier.name] || 0;
      return activeTierRequests < request.userTier.maxConcurrentRequests;
    });

    if (!eligibleRequest) return;

    const request = eligibleRequest.data() as GenerationRequest;
    
    // Update status to processing
    await eligibleRequest.ref.update({
      status: 'processing',
      startedAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      attempts: FieldValue.increment(1)
    });

    // Get API key for the service
    const apiKey = await getAvailableApiKey(
      request.type === 'image' ? 'stability' :
      request.type === 'video' ? 'predis' : 'custom'
    );

    if (!apiKey) {
      await eligibleRequest.ref.update({
        status: 'failed',
        error: 'No available API keys',
        updatedAt: Timestamp.now()
      });
      return;
    }

    // Process based on type
    let result;
    try {
      switch (request.type) {
        case 'image':
          result = await processImageGeneration(request, apiKey);
          break;
        case 'video':
          result = await processVideoGeneration(request, apiKey);
          break;
        case 'audio':
          result = await processAudioGeneration(request, apiKey);
          break;
        default:
          throw new HttpsError('invalid-argument', 'Invalid generation type');
      }
      
      // Update with success result
      await eligibleRequest.ref.update({
        status: 'completed',
        result: result,
        completedAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
        progress: 100,
        apiKeyUsed: apiKey
      });

    } catch (error) {
      console.error(`Error processing ${request.type} generation:`, error);
      
      // Handle retry logic
      if (request.attempts < request.maxAttempts) {
        await eligibleRequest.ref.update({
          status: 'queued',
          error: error.message,
          updatedAt: Timestamp.now(),
          retryCount: FieldValue.increment(1)
        });
      } else {
        await eligibleRequest.ref.update({
          status: 'failed',
          error: error.message,
          updatedAt: Timestamp.now()
        });
      }
    }

    // Update queue positions
    await updateQueuePositions();
    
  } catch (error) {
    console.error('Error processing queue:', error);
    throw new HttpsError('internal', 'Failed to process queue');
  }
}

// Enhanced processing functions with progress updates
async function processImageGeneration(request: GenerationRequest, apiKey: string): Promise<string> {
  const db = getFirestore();
  const requestRef = db.collection('generation_queue').doc(request.id);

  try {
    // Update progress to 25%
    await requestRef.update({
      progress: 25,
      updatedAt: Timestamp.now()
    });

    // TODO: Implement actual image generation with the API key
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Update progress to 75%
    await requestRef.update({
      progress: 75,
      updatedAt: Timestamp.now()
    });

    // TODO: Replace with actual API call
    return 'image_url';
  } catch (error) {
    console.error('Error in image generation:', error);
    throw new HttpsError(
      'internal',
      error instanceof Error ? error.message : 'Unknown error in image generation'
    );
  }
}

async function processVideoGeneration(request: GenerationRequest, apiKey: string): Promise<string> {
  const db = getFirestore();
  const requestRef = db.collection('generation_queue').doc(request.id);
  
  try {
    const progressSteps = [25, 50, 75, 90];
    for (const progress of progressSteps) {
      await requestRef.update({
        progress,
        updatedAt: Timestamp.now(),
        estimatedTimeRemaining: ((100 - progress) / 25) * 30 // Rough estimate in seconds
      });
      
      // Simulate processing time
      await new Promise(resolve => setTimeout(resolve, 3000));
    }

    // TODO: Replace with actual API call
    return 'video_url';
  } catch (error) {
    console.error('Error in video generation:', error);
    throw new HttpsError(
      'internal',
      error instanceof Error ? error.message : 'Unknown error in video generation'
    );
  }
}

async function processAudioGeneration(request: GenerationRequest, apiKey: string): Promise<string> {
  const db = getFirestore();
  const requestRef = db.collection('generation_queue').doc(request.id);
  
  try {
    // Update progress to 50%
    await requestRef.update({
      progress: 50,
      updatedAt: Timestamp.now()
    });

    // TODO: Implement actual audio generation
    await new Promise(resolve => setTimeout(resolve, 1500));

    return 'audio_url';
  } catch (error) {
    console.error('Error in audio generation:', error);
    throw new HttpsError(
      'internal',
      error instanceof Error ? error.message : 'Unknown error in audio generation'
    );
  }
}

// API Key Management Functions
async function getAvailableApiKey(service: string): Promise<string | null> {
  const db = getFirestore();
  
  try {
    const apiKeysRef = db.collection('api_keys')
      .where('service', '==', service)
      .where('isActive', '==', true);
      
    const snapshot = await apiKeysRef.get();
    if (snapshot.empty) return null;

    const now = Timestamp.now();
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    // Filter and sort API keys based on usage
    const availableKeys = await Promise.all(
      snapshot.docs.map(async doc => {
        const key = doc.data() as ApiKeyConfig;
        const todayUsage = await db.collection('api_usage')
          .where('keyId', '==', doc.id)
          .where('timestamp', '>=', Timestamp.fromDate(startOfDay))
          .count()
          .get();

        return {
          ...key,
          id: doc.id,
          todayUsage: todayUsage.data().count
        };
      })
    );

    // Find the best key to use
    const validKey = availableKeys
      .filter(key => key.todayUsage < key.dailyLimit)
      .sort((a, b) => a.todayUsage - b.todayUsage)[0];

    if (!validKey) return null;

    // Update key usage
    await db.collection('api_keys').doc(validKey.id).update({
      usageCount: FieldValue.increment(1),
      lastUsed: now
    });

    return validKey.key;
  } catch (error) {
    console.error('Error getting API key:', error);
    return null;
  }
}

// User Tier Management
async function getUserTier(userId: string): Promise<UserTier> {
  const db = getFirestore();
  
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      return {
        name: 'free',
        maxConcurrentRequests: 1,
        priorityLevel: 0,
        maxQueueSize: 5
      };
    }

    const userData = userDoc.data();
    switch (userData?.tier) {
      case 'premium':
        return {
          name: 'premium',
          maxConcurrentRequests: 3,
          priorityLevel: 1,
          maxQueueSize: 15
        };
      case 'enterprise':
        return {
          name: 'enterprise',
          maxConcurrentRequests: 10,
          priorityLevel: 2,
          maxQueueSize: 50
        };
      default:
        return {
          name: 'free',
          maxConcurrentRequests: 1,
          priorityLevel: 0,
          maxQueueSize: 5
        };
    }
  } catch (error) {
    console.error('Error getting user tier:', error);
    return {
      name: 'free',
      maxConcurrentRequests: 1,
      priorityLevel: 0,
      maxQueueSize: 5
    };
  }
}

// Queue Management
async function updateQueuePositions() {
  const db = getFirestore();
  const queue = db.collection('generation_queue');
  
  try {
    const pendingRequests = await queue
      .where('status', 'in', ['queued', 'pending'])
      .orderBy('priority', 'desc')
      .orderBy('createdAt', 'asc')
      .get();

    const batch = db.batch();
    pendingRequests.docs.forEach((doc, index) => {
      batch.update(doc.ref, { queuePosition: index + 1 });
    });

    await batch.commit();
  } catch (error) {
    console.error('Error updating queue positions:', error);
  }
}

// Cloud Functions

// Function to handle new generation requests
export const onNewGenerationRequest = onDocumentCreated({
  document: 'generation_queue/{requestId}',
  timeoutSeconds: 540,
  memory: '2GiB'
}, async (event) => {
  const request = event.data?.data() as GenerationRequest;
  const requestId = event.data?.id;
  
  // Validate request
  if (!request?.userId || !request?.type || !request?.prompt || !requestId) {
    await event.data?.ref.update({
      status: 'failed',
      error: 'Invalid request parameters',
      updatedAt: Timestamp.now()
    });
    return;
  }

  try {
    // Get user tier
    const userTier = await getUserTier(request.userId);

    // Check user's queue limit
    const userActiveRequests = await event.data?.ref.parent
      .where('userId', '==', request.userId)
      .where('status', 'in', ['queued', 'pending', 'processing'])
      .count()
      .get();

    if ((userActiveRequests?.data().count || 0) >= userTier.maxQueueSize) {
      await event.data?.ref.update({
        status: 'failed',
        error: 'Queue limit reached for your tier',
        updatedAt: Timestamp.now()
      });
      return;
    }

    // Calculate token cost based on type and tier
    const baseTokenCost = request.type === 'video' ? 50 : request.type === 'image' ? 30 : 20;
    const tokenCost = Math.floor(baseTokenCost * (userTier.name === 'enterprise' ? 0.8 : 1));

    // Check and deduct tokens
    const hasTokens = await updateUserTokens(request.userId, tokenCost);
    
    if (!hasTokens) {
      await event.data?.ref.update({
        status: 'failed',
        error: 'Insufficient tokens',
        updatedAt: Timestamp.now()
      });
      return;
    }

    // Initialize the request with enhanced fields
    await event.data?.ref.update({
      id: requestId,
      status: 'queued',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      priority: userTier.priorityLevel,
      attempts: 0,
      maxAttempts: userTier.name === 'enterprise' ? 5 : userTier.name === 'premium' ? 3 : 2,
      progress: 0,
      retryCount: 0,
      userTier,
      tokensUsed: tokenCost,
      metadata: {
        ...request.metadata,
        quality: userTier.name === 'enterprise' ? 'ultra' : userTier.name === 'premium' ? 'high' : 'standard'
      }
    });

    // Update queue positions
    await updateQueuePositions();
    
    // Trigger queue processing
    await processNextInQueue();

  } catch (error) {
    console.error('Error creating generation request:', error);
    if (error instanceof Error) {
      await event.data?.ref.update({
        status: 'failed',
        error: error.message,
        updatedAt: Timestamp.now()
      });
    } else {
      await event.data?.ref.update({
        status: 'failed',
        error: 'Unknown error occurred',
        updatedAt: Timestamp.now()
      });
    }
  }
});

// Function to clean up timed out requests
export const cleanupTimedOutRequests = onSchedule({
  schedule: 'every 5 minutes',
  timeoutSeconds: 120,
  memory: '256MiB'
}, async (event) => {
  const db = getFirestore();
  const queue = db.collection('generation_queue');
  
  const timeoutThreshold = Timestamp.fromMillis(
    Date.now() - REQUEST_TIMEOUT
  );
  
  const timedOutRequests = await queue
    .where('status', '==', 'processing')
    .where('updatedAt', '<=', timeoutThreshold)
    .get();
    
  const batch = db.batch();
  timedOutRequests.docs.forEach((doc) => {
    batch.update(doc.ref, {
      status: 'failed',
      error: 'Request timed out',
      updatedAt: Timestamp.now()
    });
  });
  
  await batch.commit();
});

// Function to retry failed requests
export const retryFailedRequest = onCall({
  timeoutSeconds: 540,
  memory: '2GiB',
  maxInstances: 10
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const { requestId } = request.data;
  if (!requestId) {
    throw new HttpsError('invalid-argument', 'Request ID is required');
  }
  
  const db = getFirestore();
  const requestRef = db.collection('generation_queue').doc(requestId);
  
  const requestDoc = await requestRef.get();
  if (!requestDoc.exists) {
    throw new HttpsError('not-found', 'Request not found');
  }
  
  const requestData = requestDoc.data() as GenerationRequest;
  if (requestData.userId !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'Not authorized to retry this request');
  }
  
  if (requestData.status !== 'failed') {
    throw new HttpsError('failed-precondition', 'Only failed requests can be retried');
  }
  
  await requestRef.update({
    status: 'pending',
    error: null,
    updatedAt: Timestamp.now()
  });
  
  await processNextInQueue();
  
  return { success: true };
}); 