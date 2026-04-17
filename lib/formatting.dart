String formatMoney(double? value) {
  if (value == null || value.isNaN) return '—';
  final neg = value < 0;
  final a = value.abs();
  final parts = a.toStringAsFixed(2).split('.');
  final intDigits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intDigits.length; i++) {
    final fromEnd = intDigits.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write(',');
    buf.write(intDigits[i]);
  }
  return '${neg ? '−' : ''}\$$buf.${parts[1]}';
}

/// Turns `YYYY-MM` into e.g. `April 2026`.
String formatYearMonthLabel(String yearMonth) {
  final parts = yearMonth.split('-');
  if (parts.length != 2) return yearMonth;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return yearMonth;
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${names[m - 1]} $y';
}

String formatShortDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}
