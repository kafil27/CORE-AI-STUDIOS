"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.retryFailedRequest = exports.cleanupTimedOutRequests = exports.onNewGenerationRequest = void 0;
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const params_1 = require("firebase-functions/params");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const https_1 = require("firebase-functions/v2/https");
// Initialize Firebase Admin
(0, app_1.initializeApp)();
// Set global options
(0, v2_1.setGlobalOptions)({
    maxInstances: 10,
    timeoutSeconds: 540,
    memory: '1GiB',
    region: 'us-central1'
});
// Environment parameters
const maxConcurrentRequests = (0, params_1.defineInt)('MAX_CONCURRENT_REQUESTS', { default: 5 });
const requestTimeoutMinutes = (0, params_1.defineInt)('REQUEST_TIMEOUT_MINUTES', { default: 10 });
// Constants
const REQUEST_TIMEOUT = requestTimeoutMinutes.value() * 60 * 1000;
// Helper Functions
async function updateUserTokens(userId, tokensToDeduct) {
    const db = (0, firestore_1.getFirestore)();
    try {
        const userRef = db.collection('users').doc(userId);
        return await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new https_1.HttpsError('not-found', 'User not found');
            }
            const currentTokens = userDoc.data()?.tokens || 0;
            if (currentTokens < tokensToDeduct) {
                return false;
            }
            transaction.update(userRef, {
                tokens: currentTokens - tokensToDeduct,
                'token_history': firestore_1.FieldValue.arrayUnion({
                    amount: -tokensToDeduct,
                    timestamp: firestore_1.Timestamp.now(),
                    type: 'deduction'
                })
            });
            return true;
        });
    }
    catch (error) {
        console.error('Error updating user tokens:', error);
        throw new https_1.HttpsError('internal', 'Failed to update user tokens');
    }
}
async function processNextInQueue() {
    const db = (0, firestore_1.getFirestore)();
    const queue = db.collection('generation_queue');
    try {
        // Get active requests count
        const activeRequests = await queue
            .where('status', '==', 'processing')
            .get();
        if (activeRequests.size >= maxConcurrentRequests.value()) {
            return;
        }
        // Get next pending request
        const nextRequest = await queue
            .where('status', '==', 'pending')
            .orderBy('createdAt')
            .limit(1)
            .get();
        if (nextRequest.empty) {
            return;
        }
        const requestDoc = nextRequest.docs[0];
        const request = requestDoc.data();
        // Update status to processing
        await requestDoc.ref.update({
            status: 'processing',
            updatedAt: firestore_1.Timestamp.now()
        });
        // Process based on type
        let result;
        switch (request.type) {
            case 'image':
                result = await processImageGeneration(request);
                break;
            case 'video':
                result = await processVideoGeneration(request);
                break;
            case 'audio':
                result = await processAudioGeneration(request);
                break;
            default:
                throw new https_1.HttpsError('invalid-argument', 'Invalid generation type');
        }
        // Update with result
        await requestDoc.ref.update({
            status: 'completed',
            result: result,
            updatedAt: firestore_1.Timestamp.now()
        });
    }
    catch (error) {
        console.error('Error processing queue:', error);
        throw new https_1.HttpsError('internal', 'Failed to process queue');
    }
}
// Placeholder processing functions
async function processImageGeneration(request) {
    // TODO: Implement actual image generation
    return 'image_url';
}
async function processVideoGeneration(request) {
    // TODO: Implement actual video generation
    return 'video_url';
}
async function processAudioGeneration(request) {
    // TODO: Implement actual audio generation
    return 'audio_url';
}
// Cloud Functions
// Function to handle new generation requests
exports.onNewGenerationRequest = (0, firestore_2.onDocumentCreated)({
    document: 'generation_queue/{requestId}',
    timeoutSeconds: 540,
    memory: '2GiB'
}, async (event) => {
    const request = event.data?.data();
    // Validate request
    if (!request?.userId || !request?.type || !request?.prompt) {
        await event.data?.ref.update({
            status: 'failed',
            error: 'Invalid request parameters',
            updatedAt: firestore_1.Timestamp.now()
        });
        return;
    }
    // Check and deduct tokens
    const tokenCost = request.type === 'video' ? 50 : request.type === 'image' ? 30 : 20;
    const hasTokens = await updateUserTokens(request.userId, tokenCost);
    if (!hasTokens) {
        await event.data?.ref.update({
            status: 'failed',
            error: 'Insufficient tokens',
            updatedAt: firestore_1.Timestamp.now()
        });
        return;
    }
    // Trigger queue processing
    await processNextInQueue();
});
// Function to clean up timed out requests
exports.cleanupTimedOutRequests = (0, scheduler_1.onSchedule)({
    schedule: 'every 5 minutes',
    timeoutSeconds: 120,
    memory: '256MiB'
}, async (event) => {
    const db = (0, firestore_1.getFirestore)();
    const queue = db.collection('generation_queue');
    const timeoutThreshold = firestore_1.Timestamp.fromMillis(Date.now() - REQUEST_TIMEOUT);
    const timedOutRequests = await queue
        .where('status', '==', 'processing')
        .where('updatedAt', '<=', timeoutThreshold)
        .get();
    const batch = db.batch();
    timedOutRequests.docs.forEach((doc) => {
        batch.update(doc.ref, {
            status: 'failed',
            error: 'Request timed out',
            updatedAt: firestore_1.Timestamp.now()
        });
    });
    await batch.commit();
});
// Function to retry failed requests
exports.retryFailedRequest = (0, https_1.onCall)({
    timeoutSeconds: 540,
    memory: '2GiB',
    maxInstances: 10
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const { requestId } = request.data;
    if (!requestId) {
        throw new https_1.HttpsError('invalid-argument', 'Request ID is required');
    }
    const db = (0, firestore_1.getFirestore)();
    const requestRef = db.collection('generation_queue').doc(requestId);
    const requestDoc = await requestRef.get();
    if (!requestDoc.exists) {
        throw new https_1.HttpsError('not-found', 'Request not found');
    }
    const requestData = requestDoc.data();
    if (requestData.userId !== request.auth.uid) {
        throw new https_1.HttpsError('permission-denied', 'Not authorized to retry this request');
    }
    if (requestData.status !== 'failed') {
        throw new https_1.HttpsError('failed-precondition', 'Only failed requests can be retried');
    }
    await requestRef.update({
        status: 'pending',
        error: null,
        updatedAt: firestore_1.Timestamp.now()
    });
    await processNextInQueue();
    return { success: true };
});
//# sourceMappingURL=index.js.map