import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:core_ai_studios/ui/screens/profile_screen.dart';
import 'ai_features/chat_ai_screen.dart';
import 'ai_features/image_ai_screen.dart';
import 'ai_features/video_ai_screen.dart';
import 'ai_features/voice_ai_screen.dart';

class HomeScreen extends ConsumerWidget {
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.chat,
      'title': 'Chat with AI',
      'color': Colors.purple,
      'screen': ChatAIScreen(),
    },
    {
      'icon': Icons.image,
      'title': 'Image Gen',
      'color': Colors.blue,
      'screen': ImageAIScreen(),
    },
    {
      'icon': Icons.videocam,
      'title': 'Video Gen',
      'color': Colors.red,
      'screen': VideoAIScreen(),
    },
    {
      'icon': Icons.mic,
      'title': 'Voice AI',
      'color': Colors.green,
      'screen': VoiceAIScreen(),
    },
  ];

  Widget _buildFeatureItem(
      BuildContext context, IconData icon, String title, Color color, Widget screen) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15.0),
        border: Border.all(
          width: 2,
          color: color.withOpacity(0.5),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black,
            color.withOpacity(0.2),
          ],
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => screen),
          );
        },
        borderRadius: BorderRadius.circular(15.0),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [color.withOpacity(0.8), color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Icon(icon, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: AnimatedShine(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Welcome back',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.grey[400],
          ),
        ),
        actions: [
          if (user != null)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfileScreen()),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(right: 16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: user.photoURL != null
                          ? NetworkImage(user.photoURL!)
                          : null,
                      child: user.photoURL == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: AnimatedBotImage(),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'How can I help you?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Explore AI',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.0,
                  mainAxisSpacing: 16.0,
                  crossAxisSpacing: 16.0,
                ),
                itemCount: _features.length,
                itemBuilder: (context, index) {
                  final feature = _features[index];
                  return _buildFeatureItem(
                    context,
                    feature['icon'],
                    feature['title'],
                    feature['color'],
                    feature['screen'],
                  );
                },
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Icon(Icons.history, size: 20, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text(
                    'Recent',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildRecentSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSection() {
    final recentItems = [
      {'type': 'Chat', 'tokens': 2},
      {'type': 'Image', 'tokens': 8},
      {'type': 'Video', 'tokens': 10},
      {'type': 'Voice', 'tokens': 10},
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15.0),
        color: Colors.grey[900],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: recentItems.length,
        itemBuilder: (context, index) {
          final item = recentItems[index];
          final icon = item['type'] == 'Chat'
              ? Icons.chat
              : item['type'] == 'Image'
                  ? Icons.image
                  : item['type'] == 'Video'
                      ? Icons.videocam
                      : Icons.mic;
          return ListTile(
            leading: Icon(icon, color: Colors.white),
            title: Text('${item['type']} Generation', style: TextStyle(color: Colors.white)),
            subtitle: Text('Tokens used: ${item['tokens']}', style: TextStyle(color: Colors.white70)),
          );
        },
      ),
    );
  }
}

class AnimatedBotImage extends StatefulWidget {
  @override
  _AnimatedBotImageState createState() => _AnimatedBotImageState();
}

class _AnimatedBotImageState extends State<AnimatedBotImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: Image.asset('assets/bot_image.png', height: 100),
        );
      },
    );
  }
}

class AnimatedShine extends StatefulWidget {
  @override
  _AnimatedShineState createState() => _AnimatedShineState();
}

class _AnimatedShineState extends State<AnimatedShine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [Colors.white.withOpacity(0.0), Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.0)],
              stops: [0.1, 0.5, 0.9],
              begin: Alignment(-1.0 + 2.0 * _controller.value, -1.0),
              end: Alignment(1.0 + 2.0 * _controller.value, 1.0),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15.0),
              color: Colors.transparent,
            ),
          ),
        );
      },
    );
  }
} 