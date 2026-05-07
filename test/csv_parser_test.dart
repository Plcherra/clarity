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

  test('parseBankCsv handles large files without dropping older months', () {
    final rows = StringBuffer('Date,Description,Amount,Balance\n');
    final start = DateTime(2025);
    for (var i = 0; i < 1562; i += 1) {
      final date = start.add(Duration(days: i % 471));
      final yyyy = date.year.toString().padLeft(4, '0');
      final mm = date.month.toString().padLeft(2, '0');
      final dd = date.day.toString().padLeft(2, '0');
      rows.writeln(
        '$yyyy-$mm-$dd,Merchant $i,-${(i % 90) + 1}.25,${5000 - i}.00',
      );
    }

    final result = parseBankCsv(rows.toString());
    final months = {
      for (final transaction in result.transactions)
        '${transaction.date.year}-${transaction.date.month.toString().padLeft(2, '0')}',
    };

    expect(result.transactions, hasLength(1562));
    expect(months, contains('2025-01'));
    expect(months, contains('2025-05'));
    expect(months, contains('2026-04'));
  });
}
