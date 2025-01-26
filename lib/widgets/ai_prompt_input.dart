import 'package:flutter/material.dart';
import '../models/generation_type.dart';

class AIPromptInput extends StatefulWidget {
  final GenerationType type;
  final String hintText;
  final IconData submitIcon;
  final String submitLabel;
  final Color accentColor;
  final bool isLoading;
  final Function(String) onSubmit;

  const AIPromptInput({
    super.key,
    required this.type,
    required this.hintText,
    required this.submitIcon,
    required this.submitLabel,
    required this.accentColor,
    required this.onSubmit,
    this.isLoading = false,
  });

  @override
  State<AIPromptInput> createState() => _AIPromptInputState();
}

class _AIPromptInputState extends State<AIPromptInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasError = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) {
      setState(() => _hasError = true);
      return;
    }
    if (prompt.length > 500) {
      setState(() => _hasError = true);
      return;
    }
    setState(() => _hasError = false);
    widget.onSubmit(prompt);
    _controller.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hasError ? Colors.red : Colors.grey[800]!,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton.icon(
                  onPressed: widget.isLoading ? null : _handleSubmit,
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(widget.submitIcon),
                  label: Text(widget.submitLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_hasError) ...[
          const SizedBox(height: 8),
          Text(
            _controller.text.isEmpty
                ? 'Please enter a prompt'
                : 'Prompt must be less than 500 characters',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
} 