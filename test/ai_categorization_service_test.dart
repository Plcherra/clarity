import 'package:clarity/core/models/models.dart';
import 'package:clarity/features/transactions/data/ai_categorization_service.dart';
import 'package:clarity/features/transactions/domain/spend_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'suggestCategories sends chat completion payload through proxy',
    () async {
      final transaction = Transaction(
        date: DateTime(2026, 1, 2),
        description: 'Neighborhood Market',
        amount: -24.30,
        accountId: 'account-1',
      );
      final key = transactionCategoryKey(transaction);
      final fake = _FakeOpenAiProxyClient(
        response: {
          'choices': [
            {
              'message': {
                'content':
                    '{"suggestions":[{"key":"$key","categoryId":"Groceries"}]}',
              },
            },
          ],
        },
      );
      final service = AICategorizationService(openAiClient: fake);

      final result = await service.suggestCategories(
        transactions: [transaction],
        allowedCategoryIds: const ['Groceries', 'Dining'],
      );

      expect(result, {key: 'Groceries'});
      expect(fake.lastBody?['model'], openAiModel);
      expect(fake.lastBody?['response_format'], {'type': 'json_object'});
      expect(fake.lastBody?['messages'], isA<List>());
    },
  );

  test('suggestCategories requires configured proxy client', () async {
    final service = AICategorizationService(
      openAiClient: _FakeOpenAiProxyClient(isConfigured: false),
    );

    expect(
      () => service.suggestCategories(
        transactions: [
          Transaction(
            date: DateTime(2026, 1, 2),
            description: 'Coffee',
            amount: -4.50,
            accountId: 'account-1',
          ),
        ],
        allowedCategoryIds: const ['Dining'],
      ),
      throwsA(isA<OpenAiProxyUnavailableException>()),
    );
  });
}

final class _FakeOpenAiProxyClient implements OpenAiProxyClient {
  _FakeOpenAiProxyClient({
    this.isConfigured = true,
    this.response = const <String, dynamic>{},
  });

  @override
  final bool isConfigured;

  final Map<String, dynamic> response;
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> createChatCompletion(
    Map<String, dynamic> body,
  ) async {
    lastBody = body;
    return response;
  }

  @override
  void close() {}
}
