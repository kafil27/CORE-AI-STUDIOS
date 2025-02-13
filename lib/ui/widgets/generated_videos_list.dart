import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/predis_video_service.dart';
import '../../config/ai_service_config.dart';
import 'generated_video_card.dart';

class GeneratedVideosList extends StatelessWidget {
  final int limit;
  final bool showRegenerateButton;

  const GeneratedVideosList({
    Key? key,
    this.limit = 5,
    this.showRegenerateButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('generated_videos')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final videos = snapshot.data!.docs;
        if (videos.isEmpty) {
          return const Center(
            child: Text('No videos generated yet'),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index].data() as Map<String, dynamic>;
            return GeneratedVideoCard(
              videoId: videos[index].id,
              videoUrl: video['downloadUrl'] ?? '',
              thumbnailUrl: video['thumbnailUrl'] ?? '',
              filename: video['filename'] ?? 'Untitled Video',
              prompt: video['prompt'] ?? '',
              isDownloaded: video['isDownloaded'] ?? false,
              onRegenerate: showRegenerateButton
                  ? () async {
                      final service = PredisVideoService(
                        firestore: FirebaseFirestore.instance,
                        auth: FirebaseAuth.instance,
                        config: PredisAIConfig(),
                      );
                      await service.regenerateVideo(videos[index].id, context);
                    }
                  : null,
            );
          },
        );
      },
    );
  }
} 