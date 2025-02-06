import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { QueuePriority, GenerationStatus } from './types';

const MAX_CONCURRENT_REQUESTS = 10;
const MAX_PROCESSING_TIME = 15 * 60 * 1000; // 15 minutes
const MAX_RETRIES = 3;

export const processQueue = functions.runWith({
  timeoutSeconds: 540,
  memory: '2GB',
}).pubsub.schedule('every 1 minutes').onRun(async (context) => {
  const db = admin.firestore();
  const rtdb = admin.database();

  try {
    // Get current processing requests count
    const processingRequests = await db
      .collection('generation_queue')
      .where('status', '==', 'processing')
      .get();

    if (processingRequests.size >= MAX_CONCURRENT_REQUESTS) {
      console.log('Maximum concurrent requests reached');
      return null;
    }

    // Process requests by priority
    for (const priority of Object.values(QueuePriority)) {
      const queueRef = rtdb.ref(`queues/${priority}`);
      const snapshot = await queueRef
        .orderByChild('timestamp')
        .limitToFirst(MAX_CONCURRENT_REQUESTS - processingRequests.size)
        .get();

      if (!snapshot.exists()) continue;

      const requests = Object.entries(snapshot.val()).map(([id, data]) => ({
        id,
        ...(data as any),
      }));

      for (const request of requests) {
        await processRequest(request.id, db, rtdb);
      }

      if (processingRequests.size + requests.length >= MAX_CONCURRENT_REQUESTS) {
        break;
      }
    }

    return null;
  } catch (error) {
    console.error('Error processing queue:', error);
    return null;
  }
});

export const cleanupStuckRequests = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async (context) => {
    const db = admin.firestore();
    const rtdb = admin.database();
    const cutoffTime = Date.now() - MAX_PROCESSING_TIME;

    try {
      const stuckRequests = await db
        .collection('generation_queue')
        .where('status', '==', 'processing')
        .where('processingStarted', '<', cutoffTime)
        .get();

      for (const doc of stuckRequests.docs) {
        const data = doc.data();
        const attempts = (data.attempts || 0) + 1;

        if (attempts >= MAX_RETRIES) {
          // Mark as failed if max retries reached
          await doc.ref.update({
            status: 'failed',
            error: 'Request timed out after maximum retries',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Remove from RTDB queue
          await rtdb.ref(`queues/${data.priority}/${doc.id}`).remove();
        } else {
          // Reset for retry
          await doc.ref.update({
            status: 'pending',
            attempts: attempts,
            processingStarted: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      return null;
    } catch (error) {
      console.error('Error cleaning up stuck requests:', error);
      return null;
    }
  });

async function processRequest(
  requestId: string,
  db: admin.firestore.Firestore,
  rtdb: admin.database.Database
) {
  const requestRef = db.collection('generation_queue').doc(requestId);
  const requestDoc = await requestRef.get();

  if (!requestDoc.exists) {
    console.log(`Request ${requestId} not found in Firestore`);
    return;
  }

  const requestData = requestDoc.data()!;

  // Skip if already processing or completed
  if (['processing', 'completed', 'failed'].includes(requestData.status)) {
    return;
  }

  try {
    // Update status to processing
    await requestRef.update({
      status: 'processing',
      processingStarted: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Call appropriate generation service based on type
    const result = await callGenerationService(requestData);

    // Store result in Firebase Storage if it's a file
    let storageUrl = null;
    if (result.isFile) {
      storageUrl = await uploadToStorage(result.data, requestData);
    }

    // Update request with success
    await requestRef.update({
      status: 'completed',
      result: result.isFile ? storageUrl : result.data,
      processingCompleted: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Remove from RTDB queue
    await rtdb.ref(`queues/${requestData.priority}/${requestId}`).remove();

    // Add to social feed if public
    if (requestData.metadata?.isPublic) {
      await addToSocialFeed(requestId, requestData, storageUrl || result.data);
    }

  } catch (error) {
    console.error(`Error processing request ${requestId}:`, error);

    const attempts = (requestData.attempts || 0) + 1;
    if (attempts >= MAX_RETRIES) {
      await requestRef.update({
        status: 'failed',
        error: error.message || 'Unknown error occurred',
        attempts: attempts,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Remove from RTDB queue
      await rtdb.ref(`queues/${requestData.priority}/${requestId}`).remove();
    } else {
      // Reset for retry
      await requestRef.update({
        status: 'pending',
        attempts: attempts,
        error: error.message || 'Unknown error occurred',
        processingStarted: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
}

async function callGenerationService(requestData: any) {
  // Implementation will vary based on generation type
  // This is a placeholder that should be replaced with actual service calls
  switch (requestData.type) {
    case 'video':
      // Call video generation service
      break;
    case 'image':
      // Call image generation service
      break;
    case 'audio':
      // Call audio generation service
      break;
    case 'text':
      // Call text generation service
      break;
    default:
      throw new Error(`Unsupported generation type: ${requestData.type}`);
  }

  // Placeholder return
  return {
    isFile: true,
    data: 'generated_content',
  };
}

async function uploadToStorage(
  fileData: any,
  requestData: any
): Promise<string> {
  const bucket = admin.storage().bucket();
  const fileName = `generated/${requestData.type}/${requestData.userId}/${Date.now()}_${requestData.id}`;
  
  // Implementation will vary based on how the file data is provided
  // This is a placeholder that should be replaced with actual upload logic
  await bucket.file(fileName).save(fileData);
  
  return `gs://${bucket.name}/${fileName}`;
}

async function addToSocialFeed(
  requestId: string,
  requestData: any,
  result: string
) {
  const db = admin.firestore();
  
  await db.collection('social_feed').add({
    userId: requestData.userId,
    requestId: requestId,
    type: requestData.type,
    prompt: requestData.prompt,
    result: result,
    likes: 0,
    shares: 0,
    comments: 0,
    metadata: requestData.metadata,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
} 