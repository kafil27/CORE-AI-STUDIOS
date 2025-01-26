import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'notification_service.dart';

class VideoPlayerService {
  static Future<void> playVideo(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        NotificationService.showError(
          context: context,
          title: 'Error',
          message: 'Could not open video player',
        );
      }
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to play video',
        technicalDetails: e.toString(),
      );
    }
  }

  static Future<void> downloadVideo(String url, BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);
        
        NotificationService.showSuccess(
          context: context,
          title: 'Success',
          message: 'Video downloaded successfully',
        );
      } else {
        throw Exception('Failed to download video');
      }
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Download Error',
        message: 'Failed to download video',
        technicalDetails: e.toString(),
      );
    }
  }
} 