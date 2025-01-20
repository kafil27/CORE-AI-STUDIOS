import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

enum ErrorType {
  apiNotFound,
  serviceError,
  maintenanceMode,
  insufficientBalance,
  networkError,
  otherError
}

class CustomErrorPopup extends StatelessWidget {
  final ErrorType errorType;
  final String message;
  final String? technicalDetails;
  final VoidCallback? onRetry;
  final String? supportEmail;

  const CustomErrorPopup({
    Key? key,
    required this.errorType,
    required this.message,
    this.technicalDetails,
    this.onRetry,
    this.supportEmail,
  }) : super(key: key);

  String get _errorImage {
    switch (errorType) {
      case ErrorType.apiNotFound:
        return 'assets/error_404.png';
      case ErrorType.serviceError:
        return 'assets/error_503.png';
      case ErrorType.maintenanceMode:
        return 'assets/maintenance.png';
      default:
        return 'assets/bad_error.png';
    }
  }

  String get _errorTitle {
    switch (errorType) {
      case ErrorType.apiNotFound:
        return 'Service Not Found';
      case ErrorType.serviceError:
        return 'Service Error';
      case ErrorType.maintenanceMode:
        return 'Under Maintenance';
      case ErrorType.insufficientBalance:
        return 'Insufficient Balance';
      case ErrorType.networkError:
        return 'Network Error';
      case ErrorType.otherError:
        return 'Oops! Something Went Wrong';
    }
  }

  Future<String> _saveErrorLog() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String();
      final file = File('${directory.path}/error_log_$timestamp.txt');
      
      final logContent = '''
Error Type: ${errorType.toString()}
Time: $timestamp
Message: $message
${technicalDetails != null ? '\nTechnical Details: $technicalDetails' : ''}
''';

      await file.writeAsString(logContent);
      return file.path;
    } catch (e) {
      print('Error saving log: $e');
      rethrow;
    }
  }

  Future<void> _reportError() async {
    if (supportEmail == null) return;
    
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=Error Report: ${_errorTitle}&body=Error Details:\n$message',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey[800]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              _errorImage,
              height: 120,
              width: 120,
            ),
            SizedBox(height: 24),
            Text(
              _errorTitle,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[300],
              ),
            ),
            SizedBox(height: 24),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh),
                label: Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                  foregroundColor: Theme.of(context).primaryColor,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (supportEmail != null)
                  TextButton.icon(
                    onPressed: _reportError,
                    icon: Icon(Icons.report_problem_outlined, size: 16),
                    label: Text('Report Issue'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[400],
                    ),
                  ),
                if (technicalDetails != null) ...[
                  SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: _saveErrorLog,
                    icon: Icon(Icons.download_outlined, size: 16),
                    label: Text('Download Log'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[400],
                    ),
                  ),
                ],
              ],
            ),
            if (technicalDetails != null)
              ExpansionTile(
                title: Text(
                  'Developer Details',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      technicalDetails!,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
} 