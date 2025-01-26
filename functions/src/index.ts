import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { getFirestore, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { defineInt } from 'firebase-functions/params';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();
const storage = admin.storage();

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
  status: 'queued' | 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled';
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
async function updateUserTokens(userId: string, amount: number, reason: string): Promise<void> {
  const userRef = db.collection('users').doc(userId);
  
  try {
    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      if (!userDoc.exists) {
        throw new Error('User not found');
      }

      const currentTokens = userDoc.data()?.tokens || 0;
      if (currentTokens + amount < 0) {
        throw new Error('Insufficient tokens');
      }

      transaction.update(userRef, {
        tokens: currentTokens + amount,
        lastUpdated: FieldValue.serverTimestamp(),
      });

      // Log token transaction
      transaction.create(db.collection('token_transactions').doc(), {
        userId,
        amount,
        reason,
        timestamp: FieldValue.serverTimestamp(),
        balanceAfter: currentTokens + amount,
      });
    });
  } catch (error) {
    const typedError = error as Error;
    console.error('Error updating user tokens:', typedError);
    throw new Error(`Failed to update tokens: ${typedError.message}`);
  }
}

async function processNextInQueue(): Promise<void> {
  const activeRequestsSnapshot = await db.collection('generation_queue')
    .where('status', 'in', ['pending', 'processing'])
    .orderBy('priority', 'desc')
    .orderBy('createdAt', 'asc')
    .limit(maxConcurrentRequests.value())
    .get();

  const activeRequests = activeRequestsSnapshot.docs.map(doc => {
    const data = doc.data() as GenerationRequest;
    return {
      ...data,
      id: doc.id,
    };
  });

  // Process each request based on type
  for (const request of activeRequests) {
    try {
      if (request.status === 'pending') {
        await db.collection('generation_queue').doc(request.id).update({
          status: 'processing',
          updatedAt: FieldValue.serverTimestamp(),
          attempts: FieldValue.increment(1),
        });

        // Process based on type
        switch (request.type) {
          case 'image':
            await processImageRequest(request);
            break;
          case 'video':
            await processVideoRequest(request);
            break;
          case 'audio':
            await processAudioRequest(request);
            break;
          default:
            throw new Error(`Unsupported generation type: ${request.type}`);
        }
      }
    } catch (error) {
      const typedError = error as Error;
      console.error(`Error processing request ${request.id}:`, typedError);
      
      if (request.attempts >= request.maxAttempts) {
        await db.collection('generation_queue').doc(request.id).update({
          status: 'failed',
          error: typedError.message || 'Maximum retry attempts reached',
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
  }
}

// Generation Functions
async function processImageRequest(request: GenerationRequest): Promise<void> {
  // Implementation
}

async function processVideoRequest(request: GenerationRequest): Promise<void> {
  // Implementation
}

async function processAudioRequest(request: GenerationRequest): Promise<void> {
  // Implementation
}

// API Key Management Functions
async function getAvailableApiKey(service: string): Promise<string | null> {
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
}

// User Tier Management
async function getUserTier(userId: string): Promise<UserTier> {
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
}

// Queue Management
async function updateQueuePositions() {
  const pendingRequests = await db.collection('generation_queue')
    .where('status', 'in', ['queued', 'pending'])
    .orderBy('priority', 'desc')
    .orderBy('createdAt', 'asc')
    .get();

  const batch = db.batch();
  pendingRequests.docs.forEach((doc, index) => {
    batch.update(doc.ref, { queuePosition: index + 1 });
  });

  await batch.commit();
}

// Cloud Functions

// Function to handle new generation requests
export const onNewGenerationRequest = onDocumentCreated('generation_queue/{requestId}', async (event) => {
  try {
    const request = event.data?.data() as GenerationRequest;
    const requestId = event.data?.id;
    
    // Validate request
    if (!request?.userId || !request?.type || !request?.prompt) {
      throw new Error('Invalid request data');
    }

    // Check user's active requests
    const activeRequestsCount = (await db.collection('generation_queue')
      .where('userId', '==', request.userId)
      .where('status', 'in', ['pending', 'processing'])
      .count()
      .get()).data().count;

    if (activeRequestsCount > maxConcurrentRequests.value()) {
      throw new Error('Too many active requests');
    }

    // Update request status and trigger queue processing
    await event.data?.ref.update({
      status: 'pending',
      updatedAt: FieldValue.serverTimestamp(),
    });

    await processNextInQueue();
  } catch (error) {
    const typedError = error as Error;
    await event.data?.ref.update({
      status: 'failed',
      error: typedError.message || 'Unknown error occurred',
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.error('Error processing generation request:', typedError);
  }
});

// Function to clean up timed out requests
export const cleanupTimedOutRequests = onSchedule('every-5-minutes', async (event) => {
  const timeoutThreshold = Timestamp.fromMillis(
    Date.now() - REQUEST_TIMEOUT
  );

  try {
    const timedOutRequests = await db.collection('generation_queue')
      .where('status', 'in', ['pending', 'processing'])
      .where('updatedAt', '<=', timeoutThreshold)
      .get();

    const batch = db.batch();
    timedOutRequests.docs.forEach(doc => {
      batch.update(doc.ref, {
        status: 'failed',
        error: 'Request timed out',
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
  } catch (error) {
    const typedError = error as Error;
    console.error('Error cleaning up timed out requests:', typedError);
  }
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
    updatedAt: FieldValue.serverTimestamp()
  });
  
  await processNextInQueue();
  
  return { success: true };
}); 