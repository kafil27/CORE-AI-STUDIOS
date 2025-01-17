import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final darkModeProvider = StateProvider<bool>((ref) => true);
final soundProvider = StateProvider<bool>((ref) => true);
final notificationsProvider = StateProvider<bool>((ref) => true);

class SettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(darkModeProvider);
    final isSoundOn = ref.watch(soundProvider);
    final areNotificationsOn = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildToggleOption(
              context,
              ref,
              'Dark Mode',
              Icons.dark_mode,
              isDarkMode,
              darkModeProvider,
            ),
            _buildToggleOption(
              context,
              ref,
              'Sound',
              Icons.volume_up,
              isSoundOn,
              soundProvider,
            ),
            _buildToggleOption(
              context,
              ref,
              'Notifications',
              Icons.notifications,
              areNotificationsOn,
              notificationsProvider,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleOption(
    BuildContext context,
    WidgetRef ref,
    String title,
    IconData icon,
    bool value,
    StateProvider<bool> provider,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Switch(
        value: value,
        onChanged: (newValue) {
          ref.read(provider.notifier).state = newValue;
        },
      ),
    );
  }
} 