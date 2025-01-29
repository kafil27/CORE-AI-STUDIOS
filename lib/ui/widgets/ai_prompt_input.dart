import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/token_service.dart';
import '../../services/notification_service.dart';
import '../../providers/token_provider.dart';
import '../../models/generation_type.dart';

class AIPromptInput extends ConsumerStatefulWidget {
  final GenerationType type;
  final Function(String) onSubmit;
  final bool isLoading;
  final String? initialValue;
  final String? hintText;
  final IconData? submitIcon;
  final String? submitLabel;
  final Color? accentColor;
  final FocusNode? focusNode;

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
    this.focusNode,
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
      case GenerationType.image:
        _tokenCost = 50;
        _maxLength = 1000;
        break;
      case GenerationType.video:
        _tokenCost = 100;
        _maxLength = 500;
        break;
      case GenerationType.audio:
        _tokenCost = 30;
        _maxLength = 2000;
        break;
    }
  }

  void _validatePrompt() {
    final text = _promptController.text;
    setState(() {
      _hasEmoji = RegExp(r'[^\x00-\x7F]+').hasMatch(text);
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
    final hasEnoughTokens = tokenBalance >= _tokenCost;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[800]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _promptController,
            maxLines: null,
            enabled: !widget.isLoading,
            focusNode: widget.focusNode,
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hasEnoughTokens ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasEnoughTokens ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tokenCost.toString(),
                      style: TextStyle(
                        color: hasEnoughTokens ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.token,
                      size: 16,
                      color: hasEnoughTokens ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton.icon(
                  onPressed: widget.isLoading || !_isValid || !hasEnoughTokens
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
                    disabledBackgroundColor: Colors.grey[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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