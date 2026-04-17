import 'models.dart';

/// Last row balance from export when present; otherwise sum of signed amounts.
double resolveTotalBalance(List<Transaction> txs, double? balanceFromColumn) {
  if (balanceFromColumn != null && !balanceFromColumn.isNaN) {
    return balanceFromColumn;
  }
  var sum = 0.0;
  for (final t in txs) {
    sum += t.amount;
  }
  return sum;
}
