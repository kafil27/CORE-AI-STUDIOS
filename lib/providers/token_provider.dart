import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/token_service.dart';

final tokenServiceProvider = Provider((ref) => TokenService());

final tokenBalanceProvider = StreamProvider<int>((ref) {
  return ref.watch(tokenServiceProvider).tokenBalance;
});

final recentUsageProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(tokenServiceProvider).getRecentUsage();
}); 