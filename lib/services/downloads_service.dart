import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:downloadsfolder/downloadsfolder.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ContentType {
  image,
  video,
  audio,
}

class DownloadsService {
  static const String _appFolderName = 'core_ai_studios';

  static Future<String> getAppDownloadsPath() async {
    try {
      final Directory? downloadDirectory = await getDownloadDirectory();
      if (downloadDirectory == null) {
        throw Exception('Could not access downloads folder');
      }
      
      final appPath = path.join(downloadDirectory.path, _appFolderName);
      final appDir = Directory(appPath);
      
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      
      return appPath;
    } catch (e) {
      throw Exception('Failed to access downloads folder: $e');
    }
  }

  static Future<String> getContentTypePath(ContentType type) async {
    final appPath = await getAppDownloadsPath();
    final typePath = path.join(
      appPath,
      type == ContentType.image
        ? 'images'
        : type == ContentType.video
          ? 'videos'
          : 'audios',
    );
    
    final typeDir = Directory(typePath);
    if (!await typeDir.exists()) {
      await typeDir.create(recursive: true);
    }
    
    return typePath;
  }

  static Future<String> getUserContentPath(ContentType type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    final typePath = await getContentTypePath(type);
    final userPath = path.join(typePath, user.uid);
    
    final userDir = Directory(userPath);
    if (!await userDir.exists()) {
      await userDir.create(recursive: true);
    }
    
    return userPath;
  }

  static Future<File> getLocalFile(String fileName, ContentType type) async {
    final userPath = await getUserContentPath(type);
    return File(path.join(userPath, fileName));
  }

  static Future<bool> fileExists(String fileName, ContentType type) async {
    try {
      final file = await getLocalFile(fileName, type);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  static Future<String> generateFileName(String baseName, ContentType type) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = type == ContentType.image
      ? '.png'
      : type == ContentType.video
        ? '.mp4'
        : '.mp3';
    
    // Sanitize base name
    final sanitized = baseName
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .toLowerCase();
    
    return '${sanitized}_$timestamp$extension';
  }

  static Future<File> moveToDownloads(File sourceFile, String fileName, ContentType type) async {
    try {
      final userPath = await getUserContentPath(type);
      final newPath = path.join(userPath, fileName);
      
      if (await File(newPath).exists()) {
        return File(newPath);
      }
      
      // Copy the file to downloads
      final copiedFile = await sourceFile.copy(newPath);
      
      // Open downloads folder
      await openDownloadFolder();
      
      return copiedFile;
    } catch (e) {
      throw Exception('Failed to move file to downloads: $e');
    }
  }

  static Future<List<FileSystemEntity>> listUserContent(ContentType type, {int? limit}) async {
    try {
      final userPath = await getUserContentPath(type);
      final dir = Directory(userPath);
      
      if (!await dir.exists()) {
        return [];
      }
      
      final files = await dir
        .list()
        .where((entity) => entity is File)
        .toList();
      
      // Sort by creation time, newest first
      files.sort((a, b) {
        final aTime = (a as File).lastModifiedSync();
        final bTime = (b as File).lastModifiedSync();
        return bTime.compareTo(aTime);
      });
      
      if (limit != null && files.length > limit) {
        return files.take(limit).toList();
      }
      
      return files;
    } catch (e) {
      print('Error listing user content: $e');
      return [];
    }
  }

  static Future<void> cleanupOldContent(ContentType type, {int maxFiles = 50}) async {
    try {
      final files = await listUserContent(type);
      if (files.length <= maxFiles) return;
      
      // Keep the newest maxFiles files, delete the rest
      final filesToDelete = files.skip(maxFiles);
      for (final file in filesToDelete) {
        await file.delete();
      }
    } catch (e) {
      print('Error cleaning up old content: $e');
    }
  }
} 