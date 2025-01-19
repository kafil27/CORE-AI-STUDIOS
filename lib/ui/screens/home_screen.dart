import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:core_ai_studios/ui/screens/profile_screen.dart';
import '../../../providers/token_provider.dart';
import 'ai_features/chat_ai_screen.dart';
import 'ai_features/image_ai_screen.dart';
import 'ai_features/video_ai_screen.dart';
import 'ai_features/voice_ai_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends ConsumerWidget {
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.chat,
      'title': 'Chat',
      'color': Colors.purple,
      'screen': ChatAIScreen(),
    },
    {
      'icon': Icons.image,
      'title': 'Image',
      'color': Colors.blue,
      'screen': ImageAIScreen(),
    },
    {
      'icon': Icons.videocam,
      'title': 'Video',
      'color': Colors.red,
      'screen': VideoAIScreen(),
    },
    {
      'icon': Icons.mic,
      'title': 'Voice',
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
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [color.withOpacity(0.8), color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Icon(icon, size: 40, color: Colors.white),
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Usage History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.info_outline, size: 20, color: const Color.fromARGB(255, 41, 39, 39)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey[800]!),
                            ),
                            title: Row(
                              children: [
                                Icon(Icons.history, color: Colors.grey[400], size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Usage History',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ],
                            ),
                            content: Text(
                              'This section shows your last 10 generations across all AI features. Each item shows the status, tokens used, and time of generation.',
                              style: TextStyle(color: Colors.grey[400], fontSize: 14),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Got it'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildRecentSection(),
                SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSection() {
    return Consumer(
      builder: (context, ref, child) {
        return ref.watch(recentUsageProvider).when(
          data: (usageList) {
            if (usageList.isEmpty) {
              return Container(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: Duration(seconds: 1),
                        builder: (context, double value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Icon(Icons.history, size: 48, color: Colors.grey[700]),
                          );
                        },
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No usage history yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: usageList.length,
              itemBuilder: (context, index) {
                final item = usageList[index];
                final color = _getServiceColor(item['serviceType']);
                return _buildUsageItem(context, item, color, index);
              },
            );
          },
          loading: () => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
          ),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                SizedBox(height: 16),
                Text(
                  'Failed to load usage history',
                  style: TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
                TextButton(
                  onPressed: () => ref.refresh(recentUsageProvider),
                  child: Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsageItem(BuildContext context, Map<String, dynamic> item, Color color, int index) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isExpanded = false;
        
        return TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (index * 100)),
          builder: (context, double value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black,
                  color.withOpacity(0.05),
                ],
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                onExpansionChanged: (expanded) {
                  setState(() => isExpanded = expanded);
                },
                tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: _buildServiceIcon(item['serviceType'], color),
                title: _buildUsageTitle(item),
                subtitle: _buildUsageSubtitle(item),
                trailing: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: Duration(milliseconds: 300),
                  child: Icon(
                    Icons.expand_more,
                    color: color.withOpacity(0.5),
                  ),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: color.withOpacity(0.05),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item['prompt'] != null) ...[
                          _buildDetailRow(
                            Icons.text_fields,
                            'Prompt',
                            item['prompt'],
                            color,
                          ),
                          SizedBox(height: 12),
                        ],
                        _buildTokenInfo(item, color),
                        SizedBox(height: 12),
                        _buildTimestampRow(item['timestamp'], color),
                        if (item['outputUrl'] != null) ...[
                          SizedBox(height: 12),
                          _buildOutputButton(item['outputUrl'], color),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildServiceIcon(String serviceType, Color color) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Icon(
        _getServiceIcon(serviceType),
        color: color.withOpacity(0.7),
        size: 20,
      ),
    );
  }

  Widget _buildUsageTitle(Map<String, dynamic> item) {
    return SizedBox.shrink();
  }

  Widget _buildUsageSubtitle(Map<String, dynamic> item) {
    final status = item['status']?.toLowerCase() ?? 'completed';
    final statusColor = _getStatusColor(status);
    final timestamp = item['timestamp'] as DateTime;
    final timeAgo = _getTimeAgo(timestamp);
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Status Icon
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _getStatusIcon(status),
                  size: 20,
                  color: statusColor.withOpacity(0.7),
                ),
              ),
              SizedBox(width: 6),
              // Token Count
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.token,
                      size: 16,
                      color: Colors.amber.withOpacity(0.7),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '-${item['tokensUsed']}',
                      style: TextStyle(
                        color: Colors.amber.withOpacity(0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 6),
              // Time Ago
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Colors.grey.withOpacity(0.7),
                    ),
                    SizedBox(width: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        color: Colors.grey.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimestampRow(DateTime timestamp, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 14,
            color: color.withOpacity(0.7),
          ),
          SizedBox(width: 4),
          Text(
            _formatTimestamp(timestamp),
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getServiceIcon(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'chat':
        return Icons.chat;
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'voice':
        return Icons.mic;
      default:
        return Icons.auto_awesome;
    }
  }

  Color _getServiceColor(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'chat':
        return Colors.purple;
      case 'image':
        return Colors.blue;
      case 'video':
        return Colors.red;
      case 'voice':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'processing':
        return Colors.blue;
      case 'cancelled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      case 'processing':
        return Icons.pending_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color.withOpacity(0.7)),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenInfo(Map<String, dynamic> item, Color color) {
    if (item['tokenBalanceSnapshot'] == null) return SizedBox.shrink();
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.amber.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCompactTokenInfo('Before', item['tokenBalanceSnapshot']['before'], Colors.grey[400]!),
          Container(
            height: 24,
            width: 1,
            color: Colors.amber.withOpacity(0.2),
          ),
          _buildCompactTokenInfo('Used', item['tokenBalanceSnapshot']['deducted'], Colors.red[400]!),
          Container(
            height: 24,
            width: 1,
            color: Colors.amber.withOpacity(0.2),
          ),
          _buildCompactTokenInfo('After', item['tokenBalanceSnapshot']['after'], Colors.green[400]!),
        ],
      ),
    );
  }

  Widget _buildCompactTokenInfo(String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.token, size: 10, color: color),
            SizedBox(width: 2),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputButton(String url, Color color) {
    return OutlinedButton.icon(
      onPressed: () => launchUrl(Uri.parse(url)),
      icon: Icon(Icons.visibility, size: 16),
      label: Text('View Output'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return timestamp.toLocal().toString().split('.')[0];
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