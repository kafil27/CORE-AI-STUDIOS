import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';

class GalaxyAnimation extends StatefulWidget {
  final List<Color>? colors;
  final Duration duration;
  final bool isVibrant;

  const GalaxyAnimation({
    Key? key,
    this.colors,
    this.duration = const Duration(seconds: 10),
    this.isVibrant = true,
  }) : super(key: key);

  @override
  _GalaxyAnimationState createState() => _GalaxyAnimationState();
}

class _GalaxyAnimationState extends State<GalaxyAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late List<ParticleStar> _stars;
  final int _numberOfStars = 100;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();

    _animation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _stars = List.generate(_numberOfStars, (index) => ParticleStar());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> get _defaultColors => widget.isVibrant ? [
    Colors.deepPurple[900]!,
    Colors.blue[900]!,
    Colors.teal[900]!,
    Colors.indigo[900]!,
  ] : [
    Colors.black,
    Color(0xFF1a1a1a),
    Colors.blueGrey[900]!,
    Colors.black87,
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(
                    math.cos(_animation.value),
                    math.sin(_animation.value),
                  ),
                  end: Alignment(
                    math.cos(_animation.value + math.pi),
                    math.sin(_animation.value + math.pi),
                  ),
                  colors: widget.colors ?? _defaultColors,
                  stops: [0.0, 0.33, 0.67, 1.0],
                ),
              ),
            );
          },
        ),
        CustomPaint(
          painter: StarFieldPainter(_stars, _controller.value),
          size: Size.infinite,
        ),
        BackdropFilter(
          filter: widget.isVibrant 
            ? ImageFilter.blur(sigmaX: 30, sigmaY: 30)
            : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withOpacity(0.1),
          ),
        ),
      ],
    );
  }
}

class ParticleStar {
  late double x;
  late double y;
  late double size;
  late double brightness;
  late double speed;

  ParticleStar() {
    reset();
  }

  void reset() {
    x = math.Random().nextDouble();
    y = math.Random().nextDouble();
    size = math.Random().nextDouble() * 2 + 0.5;
    brightness = math.Random().nextDouble();
    speed = math.Random().nextDouble() * 0.02 + 0.01;
  }

  void update(double delta) {
    y += speed * delta;
    if (y > 1) {
      reset();
      y = 0;
    }
  }
}

class StarFieldPainter extends CustomPainter {
  final List<ParticleStar> stars;
  final double animationValue;

  StarFieldPainter(this.stars, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (var star in stars) {
      star.update(animationValue);
      final opacity = (star.brightness * 0.5 + 0.5).clamp(0.0, 1.0);
      paint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StarFieldPainter oldDelegate) => true;
} 