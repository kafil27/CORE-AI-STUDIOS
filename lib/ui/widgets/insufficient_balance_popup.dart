import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class InsufficientBalancePopup extends StatelessWidget {
  final int requiredTokens;
  final int currentBalance;
  final String serviceType;
  final VoidCallback onPurchaseTokens;

  const InsufficientBalancePopup({
    Key? key,
    required this.requiredTokens,
    required this.currentBalance,
    required this.serviceType,
    required this.onPurchaseTokens,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        child: Container(
          width: screenSize.width * 0.85,
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: screenSize.height * 0.8,
          ),
          padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.amber.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                  splashRadius: 20,
                ),
              ),
              
              // Sad Emoji and Token Icon
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.sentiment_dissatisfied_rounded,
                    size: isSmallScreen ? 60 : 80,
                    color: Colors.amber,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.token_rounded,
                        color: Colors.amber,
                        size: isSmallScreen ? 20 : 24,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isSmallScreen ? 16 : 24),
              
              // Title
              Text(
                'Insufficient Balance',
                style: TextStyle(
                  fontSize: isSmallScreen ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              
              // Token Info
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    _buildTokenRow('Current Balance', currentBalance),
                    Divider(color: Colors.amber.withOpacity(0.2), height: 24),
                    _buildTokenRow('Required Tokens', requiredTokens),
                    Divider(color: Colors.amber.withOpacity(0.2), height: 24),
                    _buildTokenRow(
                      'Tokens Needed',
                      (requiredTokens - currentBalance),
                      isHighlighted: true,
                    ),
                  ],
                ),
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              
              // Service Info
              Text(
                '$serviceType requires at least $requiredTokens tokens per generation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: isSmallScreen ? 12 : 14,
                ),
              ),
              SizedBox(height: isSmallScreen ? 20 : 24),
              
              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onPurchaseTokens();
                  },
                  icon: Icon(Icons.add_circle_outline_rounded),
                  label: Text('Add More Tokens'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withOpacity(0.2),
                    foregroundColor: Colors.amber,
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: isSmallScreen ? 12 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenRow(String label, int amount, {bool isHighlighted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
          ),
        ),
        Row(
          children: [
            Icon(
              Icons.token_rounded,
              size: 16,
              color: isHighlighted ? Colors.amber : Colors.grey[400],
            ),
            SizedBox(width: 4),
            Text(
              amount.toString(),
              style: TextStyle(
                color: isHighlighted ? Colors.amber : Colors.white,
                fontSize: 16,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ],
    );
  }
} 