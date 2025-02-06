import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/generation_type.dart';
import 'ai_model_selector.dart';

class AIModelOption {
  final String name;
  final String iconPath;
  final String description;
  final Color accentColor;

  const AIModelOption({
    required this.name,
    required this.iconPath,
    required this.description,
    required this.accentColor,
  });
}

final aiModels = [
  AIModelOption(
    name: 'Predis AI',
    iconPath: 'assets/images/predis_logo.png',
    description: 'Professional video generation',
    accentColor: Colors.blue,
  ),
  // Add more models here
];

class AIAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final GenerationType type;
  final VoidCallback onTipsPressed;
  final VoidCallback? onBackPressed;
  final String title;

  const AIAppBar({
    Key? key,
    required this.type,
    required this.onTipsPressed,
    this.onBackPressed,
    required this.title,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Color get _accentColor {
    switch (type) {
      case GenerationType.video:
        return Colors.red.shade400;
      case GenerationType.image:
        return Colors.blue.shade400;
      case GenerationType.audio:
        return Colors.purple.shade400;
      case GenerationType.text:
        return Colors.green.shade400;
    }
  }

  IconData get _typeIcon {
    switch (type) {
      case GenerationType.video:
        return Icons.movie_creation;
      case GenerationType.image:
        return Icons.image;
      case GenerationType.audio:
        return Icons.music_note;
      case GenerationType.text:
        return Icons.text_fields;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      backgroundColor: Colors.black,
      leading: onBackPressed != null
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: _accentColor),
              onPressed: onBackPressed,
            )
          : null,
      leadingWidth: onBackPressed != null ? 40 : 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_typeIcon, color: _accentColor, size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        AIModelSelector(
          accentColor: _accentColor,
        ),
        IconButton(
          icon: const Icon(Icons.lightbulb_outline),
          color: Colors.amber[400],
          onPressed: onTipsPressed,
        ),
        const SizedBox(width: 8),
      ],
      elevation: 0,
    );
  }
} 