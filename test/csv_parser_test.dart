import 'dart:io';

import 'package:clarity/app_state.dart';
import 'package:clarity/balance_resolve.dart';
import 'package:clarity/category_rule.dart';
import 'package:clarity/csv_parser.dart';
import 'package:clarity/models.dart';
import 'package:clarity/spend_categories.dart';
import 'package:flutter_test/flutter_test.dart';

const _kTestAccountId = 'test-acct';

AppState _appStateForCsvImport() {
  final s = AppState();
  s.accounts = [
    Account(id: _kTestAccountId, name: 'Test', type: AccountType.checking),
  ];
  return s;
}

void main() {
  test('parseBankCsv reads balance from last row', () async {
    final csv = await File('test/fixtures/sample.csv').readAsString();
    final r = parseBankCsv(csv);
    expect(r.totalBalance, closeTo(1791.76, 0.01));
    expect(r.transactions.length, 12);
  });

  test('AppState aggregates April 2024 spend and categories', () async {
    final csv = await File('test/fixtures/sample.csv').readAsString();
    final state = _appStateForCsvImport();
    state.loadFromCsv(
      csv,
      accountId: _kTestAccountId,
      reference: DateTime(2024, 4, 15),
    );

    expect(
      state.spentThisMonth,
      closeTo(
        42.10 +
            4.50 +
            1200 +
            88.20 +
            200 +
            61.30 +
            36.75 +
            12 +
            18.40 +
            15.99 +
            29,
        0.01,
      ),
    );

    expect(state.topCategories.first.name, 'Housing');
    expect(state.topCategories.first.amount, closeTo(1200, 0.01));

    final april = state.monthlyGroups.singleWhere(
      (g) => g.yearMonth == '2024-04',
    );
    expect(april.transactions.length, 12);
    expect(april.transactions.last.transaction.date.day, 12);
  });

  test('resolveTotalBalance uses sum when statement has no balance column', () {
    const csv =
        'Date,Description,Amount\n2024-04-01,A,-10.00\n2024-04-02,B,25.00';
    final r = parseBankCsv(csv);
    expect(r.totalBalance, isNull);
    final txs = r.transactions;
    expect(resolveTotalBalance(txs, r.totalBalance), closeTo(15, 0.01));
  });

  test('spendGroupLabel infers categories from description', () {
    final uber = Transaction(
      date: DateTime(2024, 4, 1),
      description: 'Uber ride',
      amount: -5,
      accountId: 'a1',
    );
    expect(spendGroupLabel(uber), 'Transportation');
    final rent = Transaction(
      date: DateTime(2024, 4, 1),
      description: 'Monthly rent',
      amount: -800,
      accountId: 'a1',
    );
    expect(spendGroupLabel(rent), 'Housing');
  });

  test('reversal and NSF map to Ignored; transfer does not false-positive', () {
    expect(
      spendGroupLabel(
        Transaction(
          date: DateTime(2024, 4, 1),
          description: 'ACH NSF fee for payment',
          amount: -35,
          accountId: 'a1',
        ),
      ),
      kIgnoredCategoryLabel,
    );
    expect(
      spendGroupLabel(
        Transaction(
          date: DateTime(2024, 4, 1),
          description: 'Payment RETURNED',
          amount: -20,
          accountId: 'a1',
        ),
      ),
      kIgnoredCategoryLabel,
    );
    expect(
      spendGroupLabel(
        Transaction(
          date: DateTime(2024, 4, 1),
          description: 'Transfer to savings',
          amount: -200,
          accountId: 'a1',
        ),
      ),
      isNot(kIgnoredCategoryLabel),
    );
  });

  test('manual override wins over reversal detection', () {
    final t = Transaction(
      date: DateTime(2024, 4, 1),
      description: 'NSF fee',
      amount: -10,
      accountId: 'a1',
    );
    final key = transactionCategoryKey(t);
    expect(
      spendGroupLabel(
        t,
        categoryOverrides: {key: 'Shopping'},
      ),
      'Shopping',
    );
  });

  test('categoryId on transaction wins over category rules', () {
    final t = Transaction(
      date: DateTime(2024, 4, 1),
      description: 'Capital One payment thank you',
      amount: -25,
      accountId: 'a1',
      categoryId: 'Grocery / Supermarket',
    );
    final rules = [
      CategoryRule(
        id: '1',
        pattern: 'capital one',
        matchType: CategoryRule.matchTypeContains,
        categoryCanonical: 'Credit Card Payment',
        createdAt: DateTime.utc(2020),
      ),
    ];
    expect(
      spendGroupLabel(t, categoryRules: rules),
      'Grocery / Supermarket',
    );
  });

  test('Ignored excluded from spentThisMonth income and topCategories', () async {
    const csv = '''
Date,Description,Amount
2024-04-01,Normal shop,-50.00
2024-04-02,ACH NSF RETURN,-25.00
2024-04-03,Merchant refund REVERSAL,40.00''';
    final state = _appStateForCsvImport();
    state.loadFromCsv(
      csv,
      accountId: _kTestAccountId,
      reference: DateTime(2024, 4, 15),
    );
    expect(state.spentThisMonth, closeTo(50, 0.01));
    expect(state.incomeThisMonth, closeTo(0, 0.01));
    expect(
      state.topCategories.map((c) => c.name),
      isNot(contains(kIgnoredCategoryLabel)),
    );
  });

  test('spendGroupLabel user rules match outflow descriptions only', () {
    final nero = Transaction(
      date: DateTime(2024, 4, 1),
      description: 'NERO CAMBRIDGE MA',
      amount: -12,
      accountId: 'a1',
    );
    final rules = [
      CategoryRule(
        id: '1',
        pattern: 'nero',
        matchType: CategoryRule.matchTypeContains,
        categoryCanonical: 'Coffee / Quick Food',
        createdAt: DateTime.utc(2020),
      ),
    ];
    expect(
      spendGroupLabel(nero, categoryRules: rules),
      'Coffee / Quick Food',
    );
    final zelleIn = Transaction(
      date: DateTime(2024, 4, 1),
      description: 'Zelle payment from Alice',
      amount: 50,
      accountId: 'a1',
    );
    expect(
      spendGroupLabel(zelleIn, categoryRules: rules),
      'Income / Zelle Received',
    );
  });

  test('suggestCategoryFromDescription catches payroll and Zelle received', () {
    expect(
      suggestCategoryFromDescription(
        'Bom Dough LLC DES:payroll ID:1047 INDN:Martins Pedro CO ID:XXXXX PPD',
      ),
      'Income / Payroll',
    );
    expect(
      suggestCategoryFromDescription(
        'Bom Dough LLC DES:PAYROLL ID:1047 INDN:Martins Pedro CO ID:XXXXX30473 PPD',
      ),
      'Income / Payroll',
    );
    expect(
      suggestCategoryFromDescription(
        'TST* BOM DOUGH 04/02 MOBILE PURCHASE CAMBRIDGE MA',
      ),
      'Income / Payroll',
    );
    expect(
      suggestCategoryFromDescription('Zelle payment from JOHN DOE'),
      'Income / Zelle Received',
    );
    expect(
      suggestCategoryFromDescription('Zelle payment to Deusdete Conf# x'),
      'Transfer Out',
    );
    expect(
      suggestCategoryFromDescription(
        'Online Banking payment to CRD 5324 Confirmation# 1mizx3y4h',
      ),
      'Credit Card Payment',
    );
    expect(
      suggestCategoryFromDescription(
        'QUICK FOOD MART 04/02 MOBILE PURCHASE CAMBRIDGE MA',
      ),
      'Coffee / Quick Food',
    );
    expect(
      suggestCategoryFromDescription('APPLE COM BILL 04/15 PURCHASE CUPERTINO CA'),
      'Subscriptions',
    );
    expect(
      suggestCategoryFromDescription('APPLE.COM/BILL 04/03 PURCHASE 866-712-7753 CA'),
      'Subscriptions',
    );
  });

  test('spendGroupLabel rewrites CSV Uncategorized using keywords', () {
    final payroll = Transaction(
      date: DateTime(2025, 4, 9),
      description: 'Bom Dough LLC DES:payroll INDN:Martins Pedro PPD',
      amount: 544.63,
      accountId: 'a1',
      category: 'Uncategorized',
    );
    expect(spendGroupLabel(payroll), 'Income / Payroll');
  });

  test('spendGroupLabel overrides bank CSV category when description is payroll', () {
    final payroll = Transaction(
      date: DateTime(2026, 4, 2),
      description: 'Bom Dough LLC DES:PAYROLL ID:1047 INDN:Martins Pedro CO ID:XXXXX30473 PPD',
      amount: 544.63,
      accountId: 'a1',
      category: 'Deposit',
    );
    expect(spendGroupLabel(payroll), 'Income / Payroll');
  });

  test('keyword rules categorize common bank lines (no Uncategorized in top)', () {
    const csv = '''
Date,Description,Amount
2026-04-03,Online Banking payment to CRD 5324 Confirmation# 1mizx3y4h,-486.18
2026-04-06,QUICK FOOD MART 04/02 MOBILE PURCHASE CAMBRIDGE MA,-4.57
2026-04-14,Zelle payment to Patrick Ferreira Conf# c3jm9dxct,-50.00
2026-04-15,APPLE COM BILL 04/15 PURCHASE CUPERTINO CA,-64.78
''';
    final state = _appStateForCsvImport();
    state.loadFromCsv(
      csv,
      accountId: _kTestAccountId,
      reference: DateTime(2026, 4, 15),
    );
    expect(
      state.topCategories.any((c) => c.name == 'Uncategorized'),
      false,
    );
  });

  test('topCategories excludes Income labels (expenses only)', () {
    const csv = '''
Date,Description,Amount
2026-04-01,Bom Dough LLC payroll,-500.00
2026-04-01,Uber ride,-100.00
''';
    final state = _appStateForCsvImport();
    state.loadFromCsv(
      csv,
      accountId: _kTestAccountId,
      reference: DateTime(2026, 4, 15),
    );
    expect(
      state.topCategories.any(
        (c) => c.name.trimLeft().toLowerCase().startsWith('income'),
      ),
      false,
    );
    expect(state.topCategories.first.name, 'Transportation');
    expect(state.topCategories.first.amount, closeTo(100, 0.01));
  });

  test(
    'AppState ignores other months for spend; monthly groups newest first',
    () {
      const csv = '''
Date,Description,Amount
2026-04-30,April last,-10.00
2026-04-01,April first,-5.00
2025-12-01,December old,-999.00
''';
      final state = _appStateForCsvImport();
      state.loadFromCsv(
        csv,
        accountId: _kTestAccountId,
        reference: DateTime(2026, 4, 16),
      );
      expect(state.monthlyGroups.length, 2);
      expect(state.monthlyGroups.first.yearMonth, '2026-04');
      expect(state.monthlyGroups.first.transactions.length, 2);
      expect(
        state.monthlyGroups.first.transactions.any(
          (l) => l.transaction.description.contains('December'),
        ),
        false,
      );
      expect(state.spentThisMonth, closeTo(15, 0.01));
    },
  );

  test('parseMoney handles parentheses and symbols', () {
    expect(parseMoney('(12.50)'), -12.5);
    expect(parseMoney('\$1,234.56'), 1234.56);
  });

  test('parseBankCsv handles UTF-8 BOM on first header', () {
    const csv = '\ufeffDate,Description,Amount\n2024-04-01,Test,-10.00';
    final r = parseBankCsv(csv);
    expect(r.transactions.length, 1);
    expect(r.transactions.single.amount, -10);
  });

  test('parseBankCsv skips preamble row when second row is header', () {
    const csv =
        'Some bank export\nDate,Amount,Description\n2024-04-01,-5.00,Shop';
    final r = parseBankCsv(csv);
    expect(r.transactions.length, 1);
    expect(r.transactions.single.description, 'Shop');
  });

  test('parseBankCsv supports Paid out / Paid in columns', () async {
    final csv = await File('test/fixtures/uk_paid_out_in.csv').readAsString();
    final r = parseBankCsv(csv);
    expect(r.transactions.length, 2);
    expect(r.transactions.first.amount, closeTo(-25, 0.01));
    expect(r.transactions[1].amount, closeTo(100, 0.01));
  });

  test('parseBankCsv recognizes Data and Valor (PT) with DD.MM.YYYY', () {
    const csv = 'Data\tDescrição\tValor\n16.04.2026\tShop\t-12,50';
    final r = parseBankCsv(csv);
    expect(r.transactions.length, 1);
    expect(r.transactions.single.amount, closeTo(-12.5, 0.01));
    expect(r.transactions.single.date.month, 4);
    expect(r.transactions.single.date.day, 16);
  });

  test('parseBankCsv infers columns when headers are opaque', () {
    const csv = 'a,b,c\nmisc,-10.00,01/04/2024';
    final r = parseBankCsv(csv);
    expect(r.transactions.length, 1);
    expect(r.transactions.single.amount, closeTo(-10, 0.01));
  });

  test('parseBankCsv treats slash dates as US MM/DD/YYYY when ambiguous', () {
    const csv = 'Date,Description,Amount\n01/02/2025,Shop,-5.00';
    final r = parseBankCsv(csv);
    expect(r.transactions.single.date.year, 2025);
    expect(r.transactions.single.date.month, 1);
    expect(r.transactions.single.date.day, 2);
  });
}
