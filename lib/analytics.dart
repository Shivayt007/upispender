import 'dart:math' as math;
import 'data.dart';

/// Offline analytics over local spending records. Date end is exclusive.
class PeriodSummary {
  const PeriodSummary({
    required this.start, required this.end,
    required this.total, required this.count,
    required this.smallTotal, required this.smallCount,
    required this.categoryTotals, required this.dayTotals,
  });
  final DateTime start, end;
  final int total, count, smallTotal, smallCount;
  final Map<String, int> categoryTotals;
  final List<DayTotal> dayTotals;
}
class DayTotal {
  const DayTotal(this.date, this.paise);
  final DateTime date;
  final int paise;
}
class BudgetInsight {
  const BudgetInsight(this.title, this.description, {this.urgent = false});
  final String title, description;
  final bool urgent;
}

class SpendAnalytics {
  static const int smallThresholdPaise = 10000; // strictly under ₹100

  static DateTime startOfWeek(DateTime date) {
    final local = dayStart(date);
    return local.subtract(Duration(days: local.weekday - DateTime.monday));
  }
  static DateTime startOfMonth(DateTime date) => DateTime(date.year, date.month);
  static DateTime nextMonth(DateTime date) => DateTime(date.year, date.month + 1);
  static DateTime previousMonth(DateTime date) => DateTime(date.year, date.month - 1);

  static PeriodSummary summarize(List<SpendEntry> entries, DateTime start, DateTime end) {
    final byCategory = <String, int>{};
    final byDay = <DateTime, int>{};
    var amount = 0, count = 0, smallTotal = 0, smallCount = 0;
    for (final item in entries) {
      if (item.at.isBefore(start) || !item.at.isBefore(end)) continue;
      count++;
      amount += item.paise;
      byCategory.update(item.category, (v) => v + item.paise, ifAbsent: () => item.paise);
      final date = dayStart(item.at);
      byDay.update(date, (v) => v + item.paise, ifAbsent: () => item.paise);
      if (item.paise < smallThresholdPaise) {
        smallCount++;
        smallTotal += item.paise;
      }
    }
    final days = <DayTotal>[];
    for (var d = start; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(DayTotal(d, byDay[d] ?? 0));
    }
    return PeriodSummary(
      start: start, end: end, total: amount, count: count,
      smallTotal: smallTotal, smallCount: smallCount,
      categoryTotals: byCategory, dayTotals: days,
    );
  }

  static ({int over, int under, int untracked}) completedDayCounts(
      SpendStore store, PeriodSummary summary, DateTime now) {
    var over = 0, under = 0, untracked = 0;
    for (final day in summary.dayTotals) {
      if (!day.date.isBefore(dayStart(now))) continue;
      if (store.on(day.date).isEmpty) {
        untracked++;
      } else if (day.paise > store.targetFor(day.date)) {
        over++;
      } else {
        under++;
      }
    }
    return (over: over, under: under, untracked: untracked);
  }

  static String comparison(int current, int previous) {
    if (previous == 0) {
      return current == 0 ? 'No expenses in either period' : 'No spending recorded in the previous period';
    }
    final change = ((current - previous) / previous * 100).abs();
    if (change < .5) return 'About the same as the previous period';
    return change.toStringAsFixed(0) + '% ' +
        (current > previous ? 'more' : 'less') + ' than the previous period';
  }

  static List<MapEntry<String, int>> categoryRanking(PeriodSummary period) {
    final result = period.categoryTotals.entries.toList();
    result.sort((a, b) => b.value.compareTo(a.value));
    return result;
  }

  /// Single debit >= ₹500 and >= 3x mean of at least 5 preceding payments in 30 days.
  static bool isUnusual(SpendEntry entry, List<SpendEntry> all) {
    final before = entry.at.subtract(const Duration(days: 30));
    final history = all.where((item) =>
      item.id != entry.id && item.at.isBefore(entry.at) && !item.at.isBefore(before)
    ).toList();
    if (history.length < 5 || entry.paise < 50000) return false;
    final previousTotal = history.fold<int>(0, (a, b) => a + b.paise);
    return entry.paise * history.length >= previousTotal * 3;
  }

  static List<BudgetInsight> todayInsights(SpendStore store, {DateTime? at}) {
    final today = at ?? DateTime.now();
    final target = store.targetFor(today);
    final spent = store.spentOn(today);
    final insights = <BudgetInsight>[];
    if (target > 0 && spent > target) {
      insights.add(BudgetInsight('Daily target exceeded',
        'Today’s expenses are ' + rupees(spent - target) + ' over your target.', urgent: true));
    } else if (target > 0 && spent >= target * .8) {
      insights.add(BudgetInsight('Near your daily target',
        'You’ve used 80% or more of today’s budget. ' +
        rupees(math.max(0, target - spent)) + ' left.'));
    }
    for (final category in store.categories) {
      final limit = store.limitForCategory(category.name);
      if (limit == null) continue;
      final used = store.spentInCategoryOn(category.name, today);
      if (used > limit) {
        insights.add(BudgetInsight(category.name + ' budget exceeded',
          rupees(used - limit) + ' above today’s ' + category.name + ' limit.', urgent: true));
      } else if (used >= limit * .8) {
        insights.add(BudgetInsight(category.name + ' budget nearly used',
          rupees(math.max(0, limit - used)) + ' remaining today for ' + category.name + '.'));
      }
    }
    final small = store.on(today).where((e) => e.paise < smallThresholdPaise).toList();
    final smallTotal = small.fold<int>(0, (sum, e) => sum + e.paise);
    if (small.length >= 3 && target > 0 && smallTotal >= target * .2) {
      insights.add(BudgetInsight('Small purchases are adding up',
        small.length.toString() + ' purchases under ₹100 total ' + rupees(smallTotal) + ' today.'));
    }
    return insights;
  }
}
