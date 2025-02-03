import 'package:flutter/material.dart';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:elegant_notification/resources/arrays.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import '../ui/widgets/custom_error_popup.dart';
import '../ui/widgets/insufficient_balance_popup.dart';
import 'package:flutter/services.dart';

enum NotificationType {
  info,
  success,
  error,
  warning,
}

class NotificationService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _hasVibrator = false;
  static bool _hasCustomVibrationsSupport = false;
  static bool _hasVibrationPermission = false;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // On Android, we don't need explicit permission for vibration
      // On iOS, vibration is controlled by system settings
      _hasVibrationPermission = true;
      _hasVibrator = await Vibration.hasVibrator() ?? false;
      _hasCustomVibrationsSupport = await Vibration.hasCustomVibrationsSupport() ?? false;
      
      // Initialize audio player
      await _audioPlayer.setSource(AssetSource('success.mp3'));
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  static Future<void> _vibrate(NotificationType type) async {
    if (!_hasVibrationPermission || !_hasVibrator) return;

    try {
      if (_hasCustomVibrationsSupport) {
        switch (type) {
          case NotificationType.success:
            await Vibration.vibrate(duration: 50, amplitude: 128);
            break;
          case NotificationType.error:
            await Vibration.vibrate(pattern: [0, 100, 100, 100], intensities: [0, 128, 0, 128]);
            break;
          case NotificationType.warning:
            await Vibration.vibrate(duration: 150, amplitude: 64);
            break;
          case NotificationType.info:
            await Vibration.vibrate(duration: 50, amplitude: 32);
            break;
        }
      } else {
        // Fallback for devices without custom vibration support
        switch (type) {
          case NotificationType.success:
          case NotificationType.info:
            await Vibration.vibrate(duration: 50);
            break;
          case NotificationType.error:
            await Vibration.vibrate(duration: 300);
            break;
          case NotificationType.warning:
            await Vibration.vibrate(duration: 150);
            break;
        }
      }
    } catch (e) {
      debugPrint('Error during vibration: $e');
    }
  }

  static Future<void> _playSuccessSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.resume();
    } catch (e) {
      debugPrint('Error playing success sound: $e');
    }
  }

  static void _showNotification({
    required BuildContext context,
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    bool showPopup = false,
    VoidCallback? onRetry,
    String? technicalDetails,
    bool playSound = false,
  }) {
    // Don't show info notifications unless explicitly requested
    if (type == NotificationType.info && !showPopup) return;

    // For errors and important notifications, show the custom popup
    if (showPopup || type == NotificationType.error) {
      showDialog(
        context: context,
        builder: (context) => CustomErrorPopup(
          errorType: _getErrorType(type),
          message: message,
          technicalDetails: technicalDetails,
          onRetry: onRetry,
        ),
      );
      return;
    }

    // For other notifications, use elegant_notification
    ElegantNotification(
      title: Text(
        title,
        style: TextStyle(
          color: _getNotificationColor(type),
          fontWeight: FontWeight.bold,
        ),
      ),
      description: Text(message),
      icon: Icon(
        _getNotificationIcon(type),
        color: _getNotificationColor(type),
      ),
      progressIndicatorColor: _getNotificationColor(type),
      autoDismiss: true,
      showProgressIndicator: false,
      width: 400,
      onDismiss: () {},
    ).show(context);

    // Play sound only if explicitly requested
    if (playSound) {
      _playNotificationSound(type);
    }
  }

  static void showError({
    required BuildContext context,
    required String title,
    required String message,
    ErrorType errorType = ErrorType.otherError,
    String? technicalDetails,
    VoidCallback? onRetry,
    bool showPopup = false,
  }) async {
    await _vibrate(NotificationType.error);

    if (showPopup) {
      showDialog(
        context: context,
        builder: (context) => CustomErrorPopup(
          errorType: errorType,
          message: message,
          technicalDetails: technicalDetails,
          onRetry: onRetry,
        ),
      );
    } else {
      ElegantNotification.error(
        title: Text(title),
        description: Text(message),
        position: Alignment.bottomCenter,
        animation: AnimationType.fromBottom,
        showProgressIndicator: false,
        width: MediaQuery.of(context).size.width * 0.9,
        height: 80,
        toastDuration: Duration(seconds: 3),
        action: onRetry != null ? TextButton(
          onPressed: () {
            onRetry();
            Navigator.of(context).pop();
          },
          child: Text('Retry', style: TextStyle(color: Colors.white)),
        ) : null,
      ).show(context);
    }
  }

  static void showSuccess({
    required BuildContext context,
    required String title,
    required String message,
    bool playSound = false,
  }) async {
    await _vibrate(NotificationType.success);
    if (playSound) await _playSuccessSound();

    ElegantNotification.success(
      title: Text(title),
      description: Text(message),
      position: Alignment.bottomCenter,
      animation: AnimationType.fromBottom,
      showProgressIndicator: false,
      width: MediaQuery.of(context).size.width * 0.9,
      height: 80,
      toastDuration: Duration(seconds: 2),
    ).show(context);
  }

  static void showWarning({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    await _vibrate(NotificationType.warning);

    ElegantNotification(
      icon: Icon(Icons.warning_amber_rounded, color: Colors.orange[900]),
      title: Text(title),
      description: Text(message),
      position: Alignment.bottomCenter,
      animation: AnimationType.fromBottom,
      showProgressIndicator: false,
      width: MediaQuery.of(context).size.width * 0.9,
      height: 80,
      toastDuration: Duration(seconds: 3),
      background: Colors.orange[900]!.withOpacity(0.2),
    ).show(context);
  }

  static void showInfo({
    required BuildContext context,
    required String title,
    required String message,
    bool showPopup = false,
    bool playSound = false,
  }) {
    // Only show info notifications if explicitly requested
    if (!showPopup) return;
    
    _showNotification(
      context: context,
      title: title,
      message: message,
      type: NotificationType.info,
      showPopup: showPopup,
      playSound: playSound,
    );
  }

  static void showNoInternet({
    required BuildContext context,
    VoidCallback? onRetry,
  }) async {
    await _vibrate(NotificationType.error);

    showDialog(
      context: context,
      builder: (context) => CustomErrorPopup(
        errorType: ErrorType.networkError,
        message: 'No internet connection. Please check your connection and try again.',
        onRetry: onRetry,
      ),
    );
  }

  static void showInsufficientBalance({
    required BuildContext context,
    required int required,
    required int current,
    required String serviceType,
    VoidCallback? onPurchase,
  }) async {
    await _vibrate(NotificationType.error);

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => InsufficientBalancePopup(
          requiredTokens: required,
          currentBalance: current,
          serviceType: serviceType,
          onPurchaseTokens: () {
            Navigator.pop(dialogContext);
            if (onPurchase != null) onPurchase();
          },
        ),
      );
    }
  }

  static void dispose() {
    _audioPlayer.dispose();
  }

  static ErrorType _getErrorType(NotificationType type) {
    switch (type) {
      case NotificationType.error:
        return ErrorType.serviceError;
      case NotificationType.warning:
        return ErrorType.otherError;
      case NotificationType.info:
        return ErrorType.otherError;
      case NotificationType.success:
        return ErrorType.otherError;
    }
  }

  static Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.error:
        return Colors.red;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.info:
        return Colors.blue;
      case NotificationType.success:
        return Colors.green;
    }
  }

  static IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.error:
        return Icons.error_outline;
      case NotificationType.warning:
        return Icons.warning_amber_rounded;
      case NotificationType.info:
        return Icons.info_outline;
      case NotificationType.success:
        return Icons.check_circle_outline;
    }
  }

  static void _playNotificationSound(NotificationType type) {
    // Implementation depends on your sound requirements
    // For now, we'll use system sounds
    SystemSound.play(SystemSoundType.alert);
  }
} 