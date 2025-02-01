import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/token_service.dart';
import '../../services/notification_service.dart';
import '../../providers/token_provider.dart';
import '../../models/generation_type.dart';

class AIPromptInput extends StatefulWidget {
  final GenerationType type;
  final Function(String) onSubmit;
  final Function(String)? onChanged;
  final bool isLoading;
  final String? initialValue;
  final String hintText;
  final IconData submitIcon;
  final String submitLabel;
  final Color? accentColor;
  final FocusNode? focusNode;
  final bool isEnabled;

  const AIPromptInput({
    Key? key,
    required this.type,
    required this.onSubmit,
    this.onChanged,
    this.isLoading = false,
    this.initialValue,
    required this.hintText,
    required this.submitIcon,
    required this.submitLabel,
    this.accentColor,
    this.focusNode,
    this.isEnabled = true,
  }) : super(key: key);

  @override
  State<AIPromptInput> createState() => _AIPromptInputState();
}

class _AIPromptInputState extends State<AIPromptInput> {
  late final TextEditingController _promptController;
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
    
    // Call onChanged if provided
    if (widget.onChanged != null) {
      widget.onChanged!(_promptController.text);
    }
  }

  bool get _isValid {
    final text = _promptController.text.trim();
    return !_hasEmoji && 
           !_hasSpecialChars && 
           text.isNotEmpty &&
           text.length >= 10 &&
           text.length <= _maxLength;
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

      if (_promptController.text.trim().length < 10) {
        NotificationService.showError(
          title: 'Invalid Input',
          message: 'Your prompt is too short. Minimum length is 10 characters.',
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
    final color = widget.accentColor ?? Theme.of(context).primaryColor;
    
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
              hintText: widget.hintText,
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              counterText: '${_promptController.text.length}/$_maxLength',
              counterStyle: TextStyle(
                color: _promptController.text.length > _maxLength 
                  ? Colors.red 
                  : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isValid ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isValid ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tokenCost.toString(),
                      style: TextStyle(
                        color: _isValid ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.token,
                      size: 16,
                      color: _isValid ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton.icon(
                  onPressed: widget.isLoading || !_isValid ? null : _handleSubmit,
                  icon: widget.isLoading
                    ? ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            Colors.grey.shade600,
                            Colors.grey.shade800,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          tileMode: TileMode.mirror,
                        ).createShader(bounds),
                        child: Text(
                          'Generating...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Icon(
                        widget.submitIcon,
                        color: Colors.white,
                      ),
                  label: widget.isLoading
                    ? const SizedBox.shrink()
                    : Text(
                        widget.submitLabel,
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