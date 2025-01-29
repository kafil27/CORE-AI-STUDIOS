import 'package:flutter/material.dart';

class TipsSection extends StatelessWidget {
  final List<String> tips;
  final String title;
  final IconData icon;
  final Color? accentColor;
  final VoidCallback? onClose;

  const TipsSection({
    super.key,
    required this.tips,
    this.title = 'Tips',
    this.icon = Icons.lightbulb_outline,
    this.accentColor,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).primaryColor;
    
    return Material(
      color: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        color: Colors.grey[900],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with drag handle
            Container(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title row
                  Row(
                    children: [
                      Icon(icon, color: color, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        color: Colors.grey[400],
                        onPressed: () {
                          if (onClose != null) {
                            onClose!();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Tips list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: tips.length,
                itemBuilder: (context, index) {
                  return TipItem(
                    tip: tips[index],
                    color: color,
                    isLast: index == tips.length - 1,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TipItem extends StatelessWidget {
  final String tip;
  final Color color;
  final bool isLast;

  const TipItem({
    super.key,
    required this.tip,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.check_circle_outline,
              color: color.withAlpha(179),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 