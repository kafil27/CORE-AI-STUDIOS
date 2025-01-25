import 'package:flutter/material.dart';

class TipsSection extends StatelessWidget {
  final List<String> tips;
  final String title;
  final IconData icon;
  final Color? accentColor;
  final bool isCollapsible;

  const TipsSection({
    Key? key,
    required this.tips,
    this.title = 'Tips',
    this.icon = Icons.lightbulb_outline,
    this.accentColor,
    this.isCollapsible = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).primaryColor;
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: isCollapsible
          ? ExpansionTile(
              leading: Icon(icon, color: color),
              title: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              children: _buildTipsList(color),
              childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(icon, color: color),
                      SizedBox(width: 12),
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._buildTipsList(color),
              ],
            ),
      ),
    );
  }

  List<Widget> _buildTipsList(Color color) {
    return tips.map((tip) => Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: color.withOpacity(0.7),
            size: 16,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    )).toList();
  }
} 