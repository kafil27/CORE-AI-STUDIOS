import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/token_service.dart';
import '../../services/notification_service.dart';
import '../../providers/token_provider.dart';

enum AIGenerationType {
  image,
  video,
  audio,
}

class AIPromptInput extends ConsumerStatefulWidget {
  final AIGenerationType type;
  final Function(String) onSubmit;
  final bool isLoading;
  final String? initialValue;
  final String? hintText;
  final IconData? submitIcon;
  final String? submitLabel;
  final Color? accentColor;

  const AIPromptInput({
    Key? key,
    required this.type,
    required this.onSubmit,
    this.isLoading = false,
    this.initialValue,
    this.hintText,
    this.submitIcon,
    this.submitLabel,
    this.accentColor,
  }) : super(key: key);

  @override
  ConsumerState<AIPromptInput> createState() => _AIPromptInputState();
}

class _AIPromptInputState extends ConsumerState<AIPromptInput> {
  late TextEditingController _promptController;
  bool _hasEmoji = false;
  bool _hasSpecialChars = false;
  int _tokenCost = 0;
  int _maxLength = 0;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.initialValue);
    _initializeConfig();
    _promptController.addListener(_validatePrompt);
  }

  void _initializeConfig() {
    switch (widget.type) {
      case AIGenerationType.image:
        _tokenCost = 50;
        _maxLength = 1000;
        break;
      case AIGenerationType.video:
        _tokenCost = 100;
        _maxLength = 500;
        break;
      case AIGenerationType.audio:
        _tokenCost = 30;
        _maxLength = 2000;
        break;
    }
  }

  void _validatePrompt() {
    final text = _promptController.text;
    
    // Check for emojis
    setState(() {
      _hasEmoji = RegExp(r'[^\x00-\x7F]+').hasMatch(text);
    });

    // Check for special characters (except basic punctuation)
    setState(() {
      _hasSpecialChars = RegExp(r'[^\w\s.,!?-]').hasMatch(text);
    });
  }

  bool get _isValid {
    return !_hasEmoji && 
           !_hasSpecialChars && 
           _promptController.text.trim().isNotEmpty &&
           _promptController.text.length <= _maxLength;
  }

  void _handleSubmit() async {
    if (!_isValid) {
      if (_hasEmoji) {
        NotificationService.showError(
          title: 'Invalid Input',
          message: 'Please remove emojis from your prompt.',
          context: context,
        );
        return;
      }
      
      if (_hasSpecialChars) {
        NotificationService.showError(
          title: 'Invalid Input',
          message: 'Please remove special characters from your prompt.',
          context: context,
        );
        return;
      }
      
      if (_promptController.text.length > _maxLength) {
        NotificationService.showError(
          title: 'Invalid Input',
          message: 'Your prompt is too long. Maximum length is $_maxLength characters.',
          context: context,
        );
        return;
      }
      
      return;
    }

    final prompt = _promptController.text.trim();
    widget.onSubmit(prompt);
  }

  @override
  Widget build(BuildContext context) {
    final tokenBalance = ref.watch(tokenBalanceProvider).value ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _promptController,
            maxLines: null,
            enabled: !widget.isLoading,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: widget.hintText ?? 'Enter your prompt...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: InputBorder.none,
              counterText: '${_promptController.text.length}/$_maxLength',
              counterStyle: TextStyle(
                color: _promptController.text.length > _maxLength 
                  ? Colors.red 
                  : Colors.grey[400],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cost: $_tokenCost tokens',
                style: TextStyle(
                  color: tokenBalance >= _tokenCost 
                    ? Colors.green 
                    : Colors.red,
                ),
              ),
              ElevatedButton.icon(
                onPressed: widget.isLoading || !_isValid 
                  ? null 
                  : _handleSubmit,
                icon: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      widget.submitIcon ?? Icons.send_rounded,
                      color: Colors.white,
                    ),
                label: Text(
                  widget.submitLabel ?? 'Generate',
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor ?? Colors.blue,
                  disabledBackgroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
} 