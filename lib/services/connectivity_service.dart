import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'notification_service.dart';

final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

final isConnectedProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (result) => result != ConnectivityResult.none,
    loading: () => true,
    error: (_, __) => false,
  );
});

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      print('Error checking connectivity: $e');
      return false;
    }
  }

  Stream<ConnectivityResult> get onConnectivityChanged => 
    _connectivity.onConnectivityChanged;

  Future<bool> hasStableConnection(BuildContext context, {VoidCallback? onRetry}) async {
    try {
      // First check basic connectivity
      final hasConnection = await checkConnectivity();
      if (!hasConnection) {
        NotificationService.showNoInternet(
          context: context,
          onRetry: onRetry,
        );
        return false;
      }

      // Then try to actually reach the internet
      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(Duration(seconds: 5));
        return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } on SocketException catch (_) {
        NotificationService.showNoInternet(
          context: context,
          onRetry: onRetry,
        );
        return false;
      } on TimeoutException catch (_) {
        NotificationService.showError(
          context: context,
          title: 'Connection Timeout',
          message: 'The connection is too slow. Please check your internet speed.',
          showPopup: true,
          onRetry: onRetry,
        );
        return false;
      }
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Connection Error',
        message: 'Failed to check internet connection.',
        technicalDetails: e.toString(),
        showPopup: true,
        onRetry: onRetry,
      );
      return false;
    }
  }

  void startListening(BuildContext context) {
    onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.none) {
        NotificationService.showNoInternet(context: context);
      } else {
        NotificationService.showSuccess(
          context: context,
          title: 'Connected',
          message: 'Internet connection restored',
        );
      }
    });
  }
} 