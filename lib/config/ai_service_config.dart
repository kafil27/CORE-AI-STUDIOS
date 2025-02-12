import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract class AIServiceConfig {
  String get apiKey;
  String get baseUrl;
  Map<String, String> get headers;
  Map<String, dynamic> get defaultParams;
}

class PredisAIConfig extends AIServiceConfig {
  @override
  String get apiKey => dotenv.env['PREDIS_API_KEY'] ?? '';

  @override
  String get baseUrl => 'https://brain.predis.ai/predis_api/v1';

  @override
  Map<String, String> get headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  @override
  Map<String, dynamic> get defaultParams => {
    'brand_id': dotenv.env['PREDIS_BRAND_ID'] ?? '',
    'input_language': 'english',
    'output_language': 'english',
    'color_palette_type': 'ai_suggested',
    'video_type': 'short_form',
    'video_duration': 'short',
    'duration': '15',
    'quality': 'standard',
    'optimize_credits': 'true',
  };
}

class StabilityAIConfig extends AIServiceConfig {
  @override
  String get apiKey => dotenv.env['STABILITY_API_KEY'] ?? '';

  @override
  String get baseUrl => 'https://api.stability.ai/v1';

  @override
  Map<String, String> get headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  @override
  Map<String, dynamic> get defaultParams => {
    'cfg_scale': 7.0,
    'steps': 30,
    'samples': 1,
  };
}

enum AIServiceType {
  predisAI,
  stabilityAI,
}

class AIServiceFactory {
  static AIServiceConfig getConfig(AIServiceType type) {
    switch (type) {
      case AIServiceType.predisAI:
        return PredisAIConfig();
      case AIServiceType.stabilityAI:
        return StabilityAIConfig();
    }
  }
} 