import 'package:flutter_test/flutter_test.dart';
import 'package:upispender/analytics.dart';
import 'package:upispender/data.dart';

SpendEntry entry(int paise, DateTime at, {int? id, String category = 'Food'}) =>
    SpendEntry(id: id, paise: paise, at: at, category: category);

void main() {
  test('weeks begin on Monday and previous day offsets are correct', () {
    expect(SpendAnalytics.startOfWeek(DateTime(2026, 10, 23)), DateTime(2026, 10, 19));
    expect(SpendAnalytics.startOfMonth(DateTime(2026, 10, 23)), DateTime(2026, 10));
    expect(SpendAnalytics.nextMonth(DateTime(2026, 12, 28)), DateTime(2027, 1));
  });

  test('weekly totals group by local date without including next week', () {
    final start = DateTime(2026, 10, 19);
    final result = SpendAnalytics.summarize([
      entry(9900, DateTime(2026, 10, 19, 11)),
      entry(10000, DateTime(2026, 10, 20, 10)),
      entry(25000, DateTime(2026, 10, 25, 19), category: 'Travel'),
      entry(9000, DateTime(2026, 10, 26)),
      entry(7000, DateTime(2026, 10, 18)),
    ], start, start.add(const Duration(days: 7)));
    expect(result.total, 44900);
    expect(result.count, 3);
    expect(result.smallCount, 1); // ₹99 qualifies; exactly ₹100 does not.
    expect(result.smallTotal, 9900);
    expect(result.categoryTotals['Food'], 19900);
    expect(result.categoryTotals['Travel'], 25000);
    expect(result.dayTotals.length, 7);
    expect(result.dayTotals.first.paise, 9900);
    expect(result.dayTotals.last.paise, 25000);
  });

  test('monthly report handles leap-day February correctly', () {
    final month = DateTime(2028, 2);
    final result = SpendAnalytics.summarize([
      entry(6000, DateTime(2028, 2, 29, 23, 59)),
      entry(3000, DateTime(2028, 3, 1, 0)),
    ], month, SpendAnalytics.nextMonth(month));
    expect(result.dayTotals.length, 29);
    expect(result.total, 6000);
    expect(result.count, 1);
  });

  test('unusual spending requires historical sample and 3 times mean', () {
    final date = DateTime(2026, 10, 23, 18);
    final past = List.generate(6, (i) =>
        entry(10000, date.subtract(Duration(days: i + 1)), id: i + 1));
    expect(SpendAnalytics.isUnusual(entry(60000, date, id: 99), past), true);
    expect(SpendAnalytics.isUnusual(entry(20000, date, id: 98), past), false);
    expect(SpendAnalytics.isUnusual(entry(60000, date, id: 99), past.take(4).toList()), false);
  });

  test('zero baseline comparison avoids dividing by zero', () {
    expect(SpendAnalytics.comparison(10000, 0), contains('No spending'));
    expect(SpendAnalytics.comparison(0, 0), contains('No expenses'));
    expect(SpendAnalytics.comparison(5000, 10000), contains('50% less'));
  });
}
