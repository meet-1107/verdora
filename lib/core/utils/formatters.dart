import 'package:intl/intl.dart';

/// Shared display formatters for currency, numbers and dates.
class Formatters {
  Formatters._();

  // Money is shown without the ₹ symbol and without decimals — whole rupees
  // only (the fractional part is dropped, e.g. 10254.72 → "10,254"), with Indian
  // digit grouping.
  static final _int = NumberFormat('#,##0', 'en_IN');
  static final _compact =
      NumberFormat.compact(locale: 'en_IN');
  static final _date = DateFormat('dd MMM yyyy');
  static final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final _monthYear = DateFormat('MMMM yyyy');

  static String money(num? value) =>
      _int.format((value ?? 0).truncateToDouble());
  static String moneyCompact(num? value) =>
      _compact.format((value ?? 0).truncateToDouble());
  static String date(DateTime? d) => d == null ? '-' : _date.format(d);
  static String monthYear(DateTime? d) =>
      d == null ? 'Undated' : _monthYear.format(d);
  static String dateTime(DateTime? d) => d == null ? '-' : _dateTime.format(d);
  static String qty(num? value) =>
      NumberFormat.decimalPattern('en_IN').format(value ?? 0);
}
