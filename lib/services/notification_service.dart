import 'package:flutter/material.dart';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:elegant_notification/resources/arrays.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import '../ui/widgets/custom_error_popup.dart';
import '../ui/widgets/insufficient_balance_popup.dart';
import 'package:permission_handler/permission_handler.dart';

enum NotificationType {
  success,
  error,
  warning,
  info
}

class NotificationService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _hasVibrator = false;
  static bool _hasCustomVibrationsSupport = false;
  static bool _hasVibrationPermission = false;

  static Future<void> initialize() async {
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

  static void showError({
    required BuildContext context,
    required String title,
    required String message,
    ErrorType errorType = ErrorType.otherError,
    VoidCallback? onRetry,
    String? technicalDetails,
    bool showPopup = true,
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
  }) async {
    await _vibrate(NotificationType.info);

    ElegantNotification.info(
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
} 