import 'package:clarity/bank_statement_monthly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups by month, skips summary rows, suggests categories', () {
    const csv = '''
Date,Description,Amount
2024-03-01,Grocery,-20.00
2024-04-01,Uber to airport,-15.00
2024-04-02,Total Credits,5000.00
2024-04-03,Total Debits,0.00
2024-04-04,Ending Balance check,0.00
2024-04-05,Amazon purchase,-40.00
2024-05-01,Rent payment,-900.00
''';
    final groups = parseBankStatementGroupedByMonth(csv);

    expect(groups.length, 3);
    expect(groups[0].yearMonth, '2024-03');
    expect(groups[0].transactions.length, 1);
    expect(groups[0].totalAmount, closeTo(-20, 0.01));

    expect(groups[1].yearMonth, '2024-04');
    expect(groups[1].transactions.length, 2);
    expect(groups[1].transactions[0].suggestedCategory, 'Transportation');
    expect(groups[1].transactions[1].suggestedCategory, 'Shopping');
    expect(groups[1].totalAmount, closeTo(-55, 0.01));

    expect(groups[2].yearMonth, '2024-05');
    expect(groups[2].transactions.single.suggestedCategory, 'Housing');
  });
}
