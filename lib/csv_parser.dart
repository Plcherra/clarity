import 'dart:math' show min;

import 'package:csv/csv.dart';

import 'models.dart';

/// Result of parsing a bank-export style CSV.
class ParseResult {
  const ParseResult({
    required this.transactions,
    this.totalBalance,
    this.diagnostics,
  });

  final List<Transaction> transactions;

  /// From balance column (last row file order) or running sum when inferable.
  final double? totalBalance;

  /// Column detection and raw date cells (for debugging imports).
  final CsvParseDiagnostics? diagnostics;
}

/// Column picks and how date strings are interpreted (see [dateCellParsingRule]).
class CsvParseDiagnostics {
  const CsvParseDiagnostics({
    required this.layoutInferred,
    required this.headerRowIndex,
    this.dateColumnIndex,
    this.dateColumnHeader,
    this.amountColumnIndex,
    this.amountColumnHeader,
    this.balanceColumnIndex,
    this.balanceColumnHeader,
    required this.ambiguousSlashPolicy,
    this.firstParsedDateRawCell,
    this.lastParsedDateRawCell,
    this.firstCellParsingRule,
    this.lastCellParsingRule,
  });

  /// True when headers did not match and [_inferTableLayout] chose columns.
  final bool layoutInferred;

  /// 0-based row index of the header row used for column indices.
  final int headerRowIndex;

  final int? dateColumnIndex;
  final String? dateColumnHeader;
  final int? amountColumnIndex;
  final String? amountColumnHeader;
  final int? balanceColumnIndex;
  final String? balanceColumnHeader;

  /// How ambiguous `MM/DD` numeric dates are resolved (US bank exports).
  final String ambiguousSlashPolicy;

  final String? firstParsedDateRawCell;
  final String? lastParsedDateRawCell;
  final String? firstCellParsingRule;
  final String? lastCellParsingRule;
}

/// Human-readable rule for how [raw] is turned into a calendar date (if at all).
String dateCellParsingRule(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return 'empty';

  if (DateTime.tryParse(s) != null) {
    return 'DateTime.tryParse (ISO-style full string)';
  }

  final slash = RegExp(
    r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$',
  ).firstMatch(s);
  if (slash != null) {
    final a = int.parse(slash.group(1)!);
    final b = int.parse(slash.group(2)!);
    if (a > 12) {
      return 'slash/dot/dash: first>12 => day=$a month=$b (leading part is day)';
    }
    if (b > 12) {
      return 'slash/dot/dash: second>12 => month=$a day=$b (US month/day)';
    }
    return 'slash/dot/dash: both<=12 => month=$a day=$b (US MM/DD/YYYY)';
  }

  final ymd = RegExp(r'^(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})$').firstMatch(s);
  if (ymd != null) {
    return 'yyyy-mm-dd order';
  }
  return 'no matching date pattern';
}

/// Parses CSV text into [Transaction] rows using flexible header matching.
///
/// Column detection is case-insensitive substring match on headers.
/// Supports a single signed [amount] column, or paired [debit]/[credit]
/// (positive magnitudes); signed amount = credit − debit.
ParseResult parseBankCsv(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('File is empty');
  }

  final rows = _parseRows(trimmed);
  if (rows.isEmpty || rows.first.isEmpty) {
    throw const FormatException('No rows found');
  }

  final layout = _detectTableLayout(rows);
  if (layout == null) {
    throw const FormatException(
      'Could not find required columns (need date and either amount or debit/credit). '
      'Tip: include a row with headers such as Date + Amount, or Data + Valor, or Debit/Credit.',
    );
  }

  final headerRowIndex = layout.headerRowIndex;
  final headers = layout.headers;
  final col = layout.columns;

  final txs = <Transaction>[];
  String? firstParsedDateRaw;
  String? lastParsedDateRaw;
  for (var r = headerRowIndex + 1; r < rows.length; r++) {
    final row = rows[r];
    if (_isBlankRow(row)) continue;

    final cells = _padRow(row, headers.length);
    final dateStr = col.date != null ? cells[col.date!].toString().trim() : '';
    if (dateStr.isEmpty) continue;

    final date = _parseDate(dateStr);
    if (date == null) {
      // Skip lines that look like repeated headers or junk.
      if (_looksLikeHeader(cells)) continue;
      continue;
    }

    final desc = col.description != null
        ? cells[col.description!].toString().trim()
        : '';
    final category = col.category != null
        ? cells[col.category!].toString().trim()
        : null;
    final categoryOrNull = (category == null || category.isEmpty)
        ? null
        : category;

    double? amount;
    if (col.amount != null) {
      amount = parseMoney(cells[col.amount!].toString());
    } else if (col.debit != null || col.credit != null) {
      final d = col.debit != null
          ? parseMoney(cells[col.debit!].toString())
          : 0.0;
      final c = col.credit != null
          ? parseMoney(cells[col.credit!].toString())
          : 0.0;
      final debit = d ?? 0.0;
      final credit = c ?? 0.0;
      amount = credit - debit;
    }

    if (amount == null || amount.isNaN) continue;

    final balStr = col.balance != null ? cells[col.balance!].toString() : '';
    final balanceAfter = parseMoney(balStr);

    firstParsedDateRaw ??= dateStr;
    lastParsedDateRaw = dateStr;

    txs.add(
      Transaction(
        date: date,
        description: desc.isEmpty ? 'Transaction' : desc,
        amount: amount,
        accountId: '',
        category: categoryOrNull,
        balanceAfter: balanceAfter,
        categoryId: null,
      ),
    );
  }

  if (txs.isEmpty) {
    throw const FormatException('No valid transactions found');
  }

  double? totalBalance;
  if (col.balance != null) {
    for (var i = txs.length - 1; i >= 0; i--) {
      final b = txs[i].balanceAfter;
      if (b != null && !b.isNaN) {
        totalBalance = b;
        break;
      }
    }
  }

  final dateIdx = col.date;
  final amtIdx = col.amount;
  final balIdx = col.balance;
  final diagnostics = CsvParseDiagnostics(
    layoutInferred: layout.layoutInferred,
    headerRowIndex: headerRowIndex,
    dateColumnIndex: dateIdx,
    dateColumnHeader:
        dateIdx != null && dateIdx < headers.length ? headers[dateIdx] : null,
    amountColumnIndex: amtIdx,
    amountColumnHeader:
        amtIdx != null && amtIdx < headers.length ? headers[amtIdx] : null,
    balanceColumnIndex: balIdx,
    balanceColumnHeader:
        balIdx != null && balIdx < headers.length ? headers[balIdx] : null,
    ambiguousSlashPolicy:
        'US-style dates: when month and day are ambiguous (both ≤12), '
        '_parseDate uses MM/DD/YYYY (month first). If first part >12 it is '
        'the day; if second part >12 the first is the month.',
    firstParsedDateRawCell: firstParsedDateRaw,
    lastParsedDateRawCell: lastParsedDateRaw,
    firstCellParsingRule: firstParsedDateRaw != null
        ? dateCellParsingRule(firstParsedDateRaw)
        : null,
    lastCellParsingRule: lastParsedDateRaw != null
        ? dateCellParsingRule(lastParsedDateRaw)
        : null,
  );

  return ParseResult(
    transactions: txs,
    totalBalance: totalBalance,
    diagnostics: diagnostics,
  );
}

bool _looksLikeHeader(List<dynamic> cells) {
  final joined = _foldHeader(cells.map((c) => c.toString()).join(' '));
  final hasDateLike =
      joined.contains('date') ||
      joined.contains('data') ||
      joined.contains('fecha');
  final hasMoneyLike =
      joined.contains('amount') ||
      joined.contains('balance') ||
      joined.contains('valor') ||
      joined.contains('montante') ||
      joined.contains('importe') ||
      joined.contains('debit') ||
      joined.contains('credit');
  return hasDateLike && hasMoneyLike;
}

bool _isBlankRow(List<dynamic> row) {
  return row.every((c) => c == null || c.toString().trim().isEmpty);
}

List<dynamic> _padRow(List<dynamic> row, int len) {
  if (row.length >= len) return row;
  return [...row, ...List.filled(len - row.length, '')];
}

List<String> _normalizeHeaderRow(List<dynamic> raw) {
  return raw
      .map((c) => c.toString().trim().replaceFirst(RegExp(r'^\ufeff'), ''))
      .toList();
}

/// Lowercase + strip common Latin accents so "Débito" matches needle "debito".
String _foldHeader(String raw) {
  var s = raw.toLowerCase().trim();
  const folding = <List<String>>[
    ['á', 'a'],
    ['à', 'a'],
    ['â', 'a'],
    ['ã', 'a'],
    ['ä', 'a'],
    ['å', 'a'],
    ['é', 'e'],
    ['è', 'e'],
    ['ê', 'e'],
    ['ë', 'e'],
    ['í', 'i'],
    ['ì', 'i'],
    ['î', 'i'],
    ['ï', 'i'],
    ['ó', 'o'],
    ['ò', 'o'],
    ['ô', 'o'],
    ['õ', 'o'],
    ['ö', 'o'],
    ['ú', 'u'],
    ['ù', 'u'],
    ['û', 'u'],
    ['ü', 'u'],
    ['ý', 'y'],
    ['ÿ', 'y'],
    ['ñ', 'n'],
    ['ç', 'c'],
    ['ł', 'l'],
    ['ń', 'n'],
    ['ś', 's'],
    ['ź', 'z'],
    ['ż', 'z'],
    ['ą', 'a'],
    ['ę', 'e'],
    ['ć', 'c'],
  ];
  for (final p in folding) {
    s = s.replaceAll(p[0], p[1]);
  }
  return s;
}

int? _findExactHeaderIndex(List<String> headers, Set<String> foldedLabels) {
  for (var i = 0; i < headers.length; i++) {
    if (foldedLabels.contains(_foldHeader(headers[i]))) return i;
  }
  return null;
}

class _TableLayout {
  const _TableLayout({
    required this.headerRowIndex,
    required this.headers,
    required this.columns,
    this.layoutInferred = false,
  });

  final int headerRowIndex;
  final List<String> headers;
  final _ColumnMap columns;

  /// True when [_inferTableLayout] produced this layout (no header match).
  final bool layoutInferred;
}

_TableLayout? _detectTableLayout(List<List<dynamic>> rows) {
  final maxHeaderScan = rows.length.clamp(0, 14);
  for (var hi = 0; hi < maxHeaderScan; hi++) {
    final headers = _normalizeHeaderRow(rows[hi]);
    if (headers.isEmpty || headers.every((e) => e.isEmpty)) continue;
    final col = _ColumnMap.fromHeaders(headers);
    if (col.canBuildTransactions) {
      return _TableLayout(
        headerRowIndex: hi,
        headers: headers,
        columns: col,
        layoutInferred: false,
      );
    }
  }
  return _inferTableLayout(rows);
}

/// Guesses date + amount columns from cell contents when headers are unknown.
_TableLayout? _inferTableLayout(List<List<dynamic>> rows) {
  _TableLayout? best;
  var bestScore = -1.0;

  for (var hi = 0; hi < min(10, rows.length - 1); hi++) {
    final headers = _normalizeHeaderRow(rows[hi]);
    final nCols = headers.length;
    if (nCols < 2) continue;

    final samples = <List<String>>[];
    for (var r = hi + 1; r < rows.length && samples.length < 24; r++) {
      if (_isBlankRow(rows[r])) continue;
      samples.add(
        _padRow(rows[r], nCols).map((e) => e.toString().trim()).toList(),
      );
    }
    if (samples.isEmpty) continue;

    for (var dc = 0; dc < nCols; dc++) {
      final dHits = samples
          .where((s) => dc < s.length && _parseDate(s[dc]) != null)
          .length;
      final dScore = dHits / samples.length;
      if (dScore < 0.42) continue;

      for (var mc = 0; mc < nCols; mc++) {
        if (mc == dc) continue;
        final mHits = samples.where((s) {
          if (mc >= s.length) return false;
          return parseMoney(s[mc]) != null;
        }).length;
        final mScore = mHits / samples.length;
        if (mScore < 0.32) continue;

        var neg = 0;
        var pos = 0;
        for (final s in samples) {
          if (mc >= s.length) continue;
          final v = parseMoney(s[mc]);
          if (v == null) continue;
          if (v < 0) neg++;
          if (v > 0) pos++;
        }
        final signedBonus = (neg > 0 && pos > 0) ? 0.15 : 0.0;
        final score = dScore * mScore + signedBonus;
        if (score <= bestScore) continue;
        bestScore = score;

        int? descCol;
        var bestLen = 0.0;
        for (var t = 0; t < nCols; t++) {
          if (t == dc || t == mc) continue;
          var len = 0.0;
          for (final s in samples) {
            if (t < s.length) len += s[t].length;
          }
          len /= samples.length;
          if (len > bestLen && len > 4) {
            bestLen = len;
            descCol = t;
          }
        }

        best = _TableLayout(
          headerRowIndex: hi,
          headers: headers,
          columns: _ColumnMap(date: dc, amount: mc, description: descCol),
          layoutInferred: true,
        );
      }
    }
  }
  return best;
}

List<List<dynamic>> _parseRows(String input) {
  final firstLine = input
      .split(RegExp(r'\r?\n'))
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final comma = RegExp(',').allMatches(firstLine).length;
  final semi = RegExp(';').allMatches(firstLine).length;
  final tab = RegExp(r'\t').allMatches(firstLine).length;
  String delim = ',';
  if (semi > comma && semi >= tab) delim = ';';
  if (tab > comma && tab > semi) delim = '\t';

  final converter = CsvToListConverter(
    fieldDelimiter: delim,
    eol: '\n',
    shouldParseNumbers: false,
  );
  return converter.convert(
    input.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  );
}

class _ColumnMap {
  _ColumnMap({
    this.date,
    this.amount,
    this.debit,
    this.credit,
    this.description,
    this.category,
    this.balance,
  });

  factory _ColumnMap.fromHeaders(List<String> headers) {
    int? find(List<String> needles, {bool Function(String h)? extra}) {
      for (var i = 0; i < headers.length; i++) {
        final h = _foldHeader(headers[i]);
        if (extra != null && !extra(h)) continue;
        for (final n in needles) {
          if (h == n || h.contains(n)) return i;
        }
      }
      return null;
    }

    // More specific patterns first; [h] is accent-folded lowercase.
    var dateIdx = find([
      'transaction date',
      'posting date',
      'posted date',
      'date posted',
      'post date',
      'trans date',
      'tran date',
      'settlement date',
      'activity date',
      'value date',
      'effective date',
      'eff. date',
      'ledger date',
      'booking date',
      'purchase date',
      'buchungstag',
      'valutadatum',
      'valuta',
      'data valor',
      'data movimento',
      'data movimentacao',
      'data operacao',
      'data operación',
      'data transaccion',
      'data transação',
      'booked on',
      'booked',
      'posted',
      'fecha',
      'datum',
      'when',
      'timestamp',
      'date',
    ]);

    dateIdx ??= _findExactHeaderIndex(headers, {
      'data',
      'fecha',
      'datum',
      'day',
    });

    final balanceIdx = find(
      [
        'running balance',
        'closing balance',
        'ending balance',
        'saldo',
        'balance',
      ],
      extra: (h) {
        return !h.contains('available');
      },
    );

    final debitIdx = find([
      'paid out',
      'money out',
      'withdrawals',
      'withdrawal',
      'debits',
      'debito',
      'debit',
      'dr',
      'soll',
      'lastschrift',
      'abbuchung',
    ]);

    final creditIdx = find(
      [
        'paid in',
        'money in',
        'deposits',
        'deposit',
        'credito',
        'credits',
        'credit',
        'cr',
        'haben',
        'gutschrift',
      ],
      extra: (h) {
        if (h.contains('card') &&
            !h.contains('paid in') &&
            !h.contains('money in')) {
          return false;
        }
        return true;
      },
    );

    int? amountIdx;
    for (final candidate in [
      'transaction amount',
      'net amount',
      'montante',
      'importe',
      'importo',
      'betrag',
      'montant',
      'kwota',
      'amount',
      'value',
      'valor',
      'amt',
      'payment',
      'payments',
    ]) {
      final idx = find(
        [candidate],
        extra: (h) {
          if (h.contains('balance')) return false;
          if (h.contains('date')) return false;
          if (h.contains('subtotal')) return false;
          if (candidate == 'valor' &&
              h.contains('data') &&
              h.contains('valor')) {
            return false;
          }
          return true;
        },
      );
      if (idx != null && idx != balanceIdx) {
        amountIdx = idx;
        break;
      }
    }

    amountIdx ??= _findExactHeaderIndex(headers, {
      'valor',
      'montante',
      'importe',
      'importo',
      'betrag',
      'montant',
      'kwota',
      'amount',
    });

    final descIdx = find([
      'description',
      'details',
      'narrative',
      'memo',
      'payee',
      'merchant',
      'counter party',
      'counterparty',
      'name',
      'libelle',
      'descricao',
      'descripcion',
      'concepto',
      'motivo',
      'verwendungszweck',
      'buchungstext',
    ]);

    final catIdx = find(['category', 'type', 'classification']);

    return _ColumnMap(
      date: dateIdx,
      amount: amountIdx,
      debit: debitIdx,
      credit: creditIdx,
      description: descIdx,
      category: catIdx,
      balance: balanceIdx,
    );
  }

  final int? date;
  final int? amount;
  final int? debit;
  final int? credit;
  final int? description;
  final int? category;
  final int? balance;

  bool get canBuildTransactions {
    if (date == null) return false;
    if (amount != null) return true;
    return debit != null || credit != null;
  }
}

/// Parses money strings with common currency symbols and decimal separators.
double? parseMoney(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  var neg = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    neg = true;
    s = s.substring(1, s.length - 1).trim();
  }
  if (s.endsWith('-')) {
    neg = true;
    s = s.substring(0, s.length - 1).trim();
  }
  if (s.startsWith('+')) {
    s = s.substring(1).trim();
  }

  s = s.replaceAll(RegExp(r'[\s$€£¥₹]'), '');

  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (lastComma >= 0 && lastDot < 0) {
    final parts = s.split(',');
    if (parts.length == 2 &&
        parts[1].length <= 2 &&
        RegExp(r'^\d+$').hasMatch(parts[1])) {
      s = '${parts[0]}.${parts[1]}';
    } else {
      s = s.replaceAll(',', '');
    }
  }

  final v = double.tryParse(s);
  if (v == null) return null;
  return neg ? -v : v;
}

/// Returns date at local noon to reduce DST issues when comparing calendar months.
DateTime? _parseDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final iso = DateTime.tryParse(s);
  if (iso != null) {
    return DateTime(iso.year, iso.month, iso.day, 12);
  }

  // Slash, hyphen, or dot separators (e.g. 01/02/2025, 16.04.2026, 04-15-2026).
  // American exports: ambiguous pairs use MM/DD/YYYY (month first).
  final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(s);
  if (m != null) {
    var a = int.parse(m.group(1)!);
    var b = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    int day;
    int month;
    if (a > 12) {
      // Cannot be a US month (e.g. 25/12/2025, 16.04.2026).
      day = a;
      month = b;
    } else if (b > 12) {
      // Second part is the day (e.g. 03/25/2025).
      month = a;
      day = b;
    } else {
      // Ambiguous: US MM/DD/YYYY.
      month = a;
      day = b;
    }
    return DateTime(y, month, day, 12);
  }

  final mIso = RegExp(r'^(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})$').firstMatch(s);
  if (mIso != null) {
    final y = int.parse(mIso.group(1)!);
    final mo = int.parse(mIso.group(2)!);
    final d = int.parse(mIso.group(3)!);
    return DateTime(y, mo, d, 12);
  }

  return null;
}
