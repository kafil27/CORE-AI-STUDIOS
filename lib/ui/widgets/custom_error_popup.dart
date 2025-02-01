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

class CustomErrorPopup extends StatefulWidget {
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

  @override
  State<CustomErrorPopup> createState() => _CustomErrorPopupState();
}

class _CustomErrorPopupState extends State<CustomErrorPopup> {
  String? _logFilePath;
  bool _isDownloading = false;

  String get _errorImage {
    switch (widget.errorType) {
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
    switch (widget.errorType) {
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

  Future<void> _saveAndOpenErrorLog() async {
    if (_isDownloading) return;
    
    setState(() => _isDownloading = true);
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/error_log_$timestamp.txt');
      
      final logContent = '''
Error Type: ${widget.errorType.toString()}
Time: $timestamp
Message: ${widget.message}
${widget.technicalDetails != null ? '\nTechnical Details:\n${widget.technicalDetails}' : ''}
''';

      await file.writeAsString(logContent);
      setState(() {
        _logFilePath = file.path;
        _isDownloading = false;
      });
    } catch (e) {
      setState(() => _isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save log: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openLogFile() async {
    if (_logFilePath == null) return;
    
    final uri = Uri.file(_logFilePath!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _reportError() async {
    if (widget.supportEmail == null) return;
    
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: widget.supportEmail,
      query: 'subject=Error Report: ${_errorTitle}&body=Error Details:\n${widget.message}',
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
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
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
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ),
            Image.asset(
              _errorImage,
              height: 100,
              width: 100,
            ),
            SizedBox(height: 16),
            Text(
              _errorTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 24),
            if (widget.onRetry != null)
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: Icon(Icons.refresh),
                label: Text('Try Again'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.supportEmail != null)
                  TextButton.icon(
                    onPressed: _reportError,
                    icon: Icon(Icons.report_problem_outlined, size: 16),
                    label: Text('Report Issue'),
                  ),
                if (widget.technicalDetails != null) ...[
                  SizedBox(width: 16),
                  if (_logFilePath == null)
                    TextButton.icon(
                      onPressed: _isDownloading ? null : _saveAndOpenErrorLog,
                      icon: _isDownloading 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        : Icon(Icons.download_outlined, size: 16),
                      label: Text(_isDownloading ? 'Saving...' : 'Download Log'),
                    )
                  else
                    TextButton.icon(
                      onPressed: _openLogFile,
                      icon: Icon(Icons.folder_open_outlined, size: 16),
                      label: Text('Open Log'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
} 