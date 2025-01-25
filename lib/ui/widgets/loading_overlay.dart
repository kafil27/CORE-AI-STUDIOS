import 'package:flutter/material.dart';
import 'galaxy_animation.dart';

class LoadingOverlay extends StatelessWidget {
  final String message;
  final String? subMessage;
  final bool isLoading;
  final Widget child;
  final bool useGalaxyAnimation;

  const LoadingOverlay({
    Key? key,
    required this.message,
    this.subMessage,
    required this.isLoading,
    required this.child,
    this.useGalaxyAnimation = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Stack(
              children: [
                if (useGalaxyAnimation)
                  const GalaxyAnimation(
                    isVibrant: false,
                    duration: Duration(seconds: 20),
                  ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.grey[850]!,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (subMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subMessage!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
} 