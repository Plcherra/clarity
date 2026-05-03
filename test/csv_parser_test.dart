import 'package:clarity/features/transactions/data/csv_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseBankCsv parses signed amount CSV rows', () {
    const csv = '''
Date,Description,Amount,Balance
2026-01-02,Coffee Shop,-4.50,995.50
2026-01-03,Paycheck,1200.00,2195.50
''';

    final result = parseBankCsv(csv);

    expect(result.transactions, hasLength(2));
    expect(result.transactions[0].description, 'Coffee Shop');
    expect(result.transactions[0].amount, -4.50);
    expect(result.transactions[1].description, 'Paycheck');
    expect(result.transactions[1].amount, 1200.00);
    expect(result.totalBalance, 2195.50);
    expect(result.diagnostics?.dateColumnHeader, 'Date');
  });

  test('parseBankCsv rejects empty files', () {
    expect(() => parseBankCsv('   '), throwsFormatException);
  });
}
