import 'dart:math';
import 'package:flutter/material.dart';

class LoadingOverlay extends StatefulWidget {
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
    this.useGalaxyAnimation = false,
  }) : super(key: key);

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _starAnimationController;
  late AnimationController _pulseAnimationController;

  @override
  void initState() {
    super.initState();
    _starAnimationController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    _pulseAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _starAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.useGalaxyAnimation)
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _buildRotatingStars(
                              count: 8,
                              radius: 80,
                              duration: const Duration(seconds: 8),
                              starSize: 10,
                              color: Colors.blue.shade300,
                              glowIntensity: 1.2,
                            ),
                            _buildRotatingStars(
                              count: 6,
                              radius: 60,
                              duration: const Duration(seconds: 6),
                              starSize: 8,
                              color: Colors.purple.shade300,
                              reverse: true,
                              glowIntensity: 1.0,
                            ),
                            _buildRotatingStars(
                              count: 4,
                              radius: 40,
                              duration: const Duration(seconds: 4),
                              starSize: 6,
                              color: Colors.teal.shade200,
                              glowIntensity: 0.8,
                            ),
                            _buildPulsingStar(),
                          ],
                        ),
                      )
                    else
                      const CircularProgressIndicator(),
                    const SizedBox(height: 32),
                    Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.subMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.subMessage!,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRotatingStars({
    required int count,
    required double radius,
    required Duration duration,
    required double starSize,
    required Color color,
    bool reverse = false,
    double glowIntensity = 1.0,
  }) {
    return AnimatedBuilder(
      animation: _starAnimationController,
      builder: (context, child) {
        final value = _starAnimationController.value * 2 * pi;
        return Transform.rotate(
          angle: reverse ? -value : value,
          child: Stack(
            alignment: Alignment.center,
            children: List.generate(count, (index) {
              final angle = (index * 2 * pi) / count;
              return Transform.translate(
                offset: Offset(
                  radius * cos(angle),
                  radius * sin(angle),
                ),
                child: _buildStar(color, starSize, glowIntensity),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildStar(Color color, double size, double glowIntensity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.6),
            color.withOpacity(0.2),
          ],
          stops: const [0.1, 1.0],
        ),
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: size * glowIntensity,
            spreadRadius: size * glowIntensity / 3,
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingStar() {
    return AnimatedBuilder(
      animation: _pulseAnimationController,
      builder: (context, child) {
        final scale = 0.5 + (_pulseAnimationController.value * 0.8);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                colors: [
                  Colors.white70,
                  Colors.white24,
                ],
                stops: [0.1, 1.0],
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: const [
                BoxShadow(
                  color: Colors.white30,
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: Colors.white24,
                  blurRadius: 24,
                  spreadRadius: 6,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 