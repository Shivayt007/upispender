import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'analytics.dart';
import 'data.dart';

class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.child, this.padding = const EdgeInsets.all(17)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1D2A31) : Colors.white,
      borderRadius: BorderRadius.circular(21),
    ),
    child: child,
  );
}

class BudgetWarningsPanel extends StatelessWidget {
  const BudgetWarningsPanel({super.key, required this.store});
  final SpendStore store;
  @override
  Widget build(BuildContext context) {
    final warnings = SpendAnalytics.todayInsights(store);
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.tips_and_updates_outlined, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          const Text('Smart spending warnings', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 9),
        for (final insight in warnings.take(3))
          Padding(padding: const EdgeInsets.only(top: 9), child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(insight.urgent ? Icons.warning_amber_rounded : Icons.info_outline,
                color: insight.urgent ? const Color(0xFFE86A65) : const Color(0xFFF0A34B), size: 20),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(insight.description, style: Theme.of(context).textTheme.bodySmall),
              ])),
            ],
          )),
      ])),
    );
  }
}

class CategoryBudgetsCard extends StatefulWidget {
  const CategoryBudgetsCard({super.key, required this.store});
  final SpendStore store;
  @override
  State<CategoryBudgetsCard> createState() => _CategoryBudgetsCardState();
}

class _CategoryBudgetsCardState extends State<CategoryBudgetsCard> {
  Future<void> editLimit(SpendCategory cat) async {
    final old = widget.store.limitForCategory(cat.name);
    final controller = TextEditingController(
      text: old == null ? '' : (old / 100).toStringAsFixed(old % 100 == 0 ? 0 : 2),
    );
    String? error;
    final choice = await showDialog<int?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: Text(cat.name + ' daily limit'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(prefixText: '₹ ', labelText: 'Per-day maximum', errorText: error),
          ),
          const SizedBox(height: 10),
          const Text('Resets every calendar day. The overall daily target remains separate.'),
        ]),
        actions: [
          if (old != null) TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Remove limit')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final value = parsePaise(controller.text);
            if (value == null) {
              update(() => error = 'Enter a positive amount');
              return;
            }
            Navigator.pop(ctx, value);
          }, child: const Text('Save')),
        ],
      )),
    );
    // Cancel is null, remove is -1.
    controller.dispose();
    if (choice == null) return;
    await widget.store.setCategoryLimit(cat.name, choice == -1 ? null : choice);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(choice == -1 ? cat.name + ' limit removed' : cat.name + ' limit saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = widget.store.flag('privacyMode');
    return InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Category budgets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text('Optional daily spending limits for each category',
        style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 15),
      for (final cat in widget.store.categories) ...[
        Builder(builder: (context) {
          final cap = widget.store.limitForCategory(cat.name);
          final used = widget.store.spentInCategoryOn(cat.name, DateTime.now());
          final ratio = cap == null ? 0.0 : (used / cap);
          final color = cap == null ? Theme.of(context).colorScheme.primary
              : ratio > 1 ? const Color(0xFFE76262)
              : ratio >= .8 ? const Color(0xFFF0AA4A) : const Color(0xFF20B994);
          return Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: InkWell(
              onTap: () => editLimit(cat),
              borderRadius: BorderRadius.circular(12),
              child: Column(children: [
                Row(children: [
                  CircleAvatar(radius: 15, backgroundColor: Color(cat.colorCode).withValues(alpha: .15),
                    child: Icon(Icons.category_outlined, size: 17, color: Color(cat.colorCode))),
                  const SizedBox(width: 9),
                  Expanded(child: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(cap == null ? 'Set limit' : rupees(used, hidden: hidden) + ' / ' + rupees(cap, hidden: hidden),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color)),
                  const SizedBox(width: 5),
                  Icon(Icons.edit_outlined, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ]),
                if (cap != null) ...[
                  const SizedBox(height: 7),
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0.0, 1.0), minHeight: 7, color: color,
                      backgroundColor: color.withValues(alpha: .12),
                    )),
                ],
              ]),
            ),
          );
        }),
      ],
    ]));
  }
}

class SmallSpendsShortcut extends StatelessWidget {
  const SmallSpendsShortcut({super.key, required this.store});
  final SpendStore store;
  @override
  Widget build(BuildContext context) {
    final stats = SpendAnalytics.summarize(store.entries,
      dayStart(DateTime.now()), dayStart(DateTime.now()).add(const Duration(days: 1)));
    return Padding(padding: const EdgeInsets.only(top: 14), child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => SmallSpendsScreen(store: store))),
      child: InsightCard(child: Row(children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFFFEBD6),
          child: Icon(Icons.toll_outlined, color: Color(0xFFE48B33))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Small spends under ₹100', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(stats.smallCount.toString() + ' purchases today',
            style: Theme.of(context).textTheme.bodySmall),
        ])),
        Text(rupees(stats.smallTotal, hidden: store.flag('privacyMode')),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const Icon(Icons.chevron_right),
      ])),
    ));
  }
}

class SmallSpendsScreen extends StatefulWidget {
  const SmallSpendsScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<SmallSpendsScreen> createState() => _SmallSpendsScreenState();
}

class _SmallSpendsScreenState extends State<SmallSpendsScreen> {
  int mode = 0;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = mode == 0 ? dayStart(now)
      : mode == 1 ? SpendAnalytics.startOfWeek(now) : SpendAnalytics.startOfMonth(now);
    final end = mode == 0 ? DateTime(start.year, start.month, start.day + 1)
      : mode == 1 ? start.add(const Duration(days: 7)) : SpendAnalytics.nextMonth(start);
    final stats = SpendAnalytics.summarize(widget.store.entries, start, end);
    final small = widget.store.entries.where((e) =>
      !e.at.isBefore(start) && e.at.isBefore(end) && e.paise < SpendAnalytics.smallThresholdPaise).toList();
    final hidden = widget.store.flag('privacyMode');
    return Scaffold(
      appBar: AppBar(title: const Text('Small-spends tracker')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SegmentedButton<int>(
          selected: {mode}, showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Today')),
            ButtonSegment(value: 1, label: Text('Week')),
            ButtonSegment(value: 2, label: Text('Month')),
          ],
          onSelectionChanged: (v) => setState(() => mode = v.first),
        ),
        const SizedBox(height: 16),
        InsightCard(child: Column(children: [
          const Text('TOTAL FROM PAYMENTS BELOW ₹100'),
          const SizedBox(height: 10),
          Text(rupees(stats.smallTotal, hidden: hidden),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(small.length.toString() + ' small payments'),
          const SizedBox(height: 8),
          Text(stats.total == 0 ? 'No expenses recorded'
            : (stats.smallTotal / stats.total * 100).toStringAsFixed(1) + '% of all spending this period'),
        ])),
        const SizedBox(height: 20),
        const Text('Transactions under ₹100', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (small.isEmpty) const Text('No small payments recorded for this period.')
        else for (final item in small)
          Card(child: ListTile(
            title: Text(item.payee.isEmpty ? item.category : item.payee),
            subtitle: Text(item.category + ' • ' + DateFormat('d MMM, h:mm a').format(item.at)),
            trailing: Text(rupees(item.paise, hidden: hidden),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
      ]),
    );
  }
}


/// Reports tab content for full Monday-Sunday weeks and calendar months.
class PeriodDashboard extends StatefulWidget {
  const PeriodDashboard({
    super.key, required this.store, required this.mode, required this.onModeChanged,
  });
  final SpendStore store;
  final int mode; // 1 week, 2 month
  final ValueChanged<int> onModeChanged;
  @override
  State<PeriodDashboard> createState() => _PeriodDashboardState();
}

class _PeriodDashboardState extends State<PeriodDashboard> {
  DateTime anchor = DateTime.now();
  @override
  void didUpdateWidget(covariant PeriodDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) anchor = DateTime.now();
  }

  void move(int direction) {
    setState(() {
      anchor = widget.mode == 1
        ? DateTime(anchor.year, anchor.month, anchor.day + direction * 7)
        : DateTime(anchor.year, anchor.month + direction);
    });
  }

  @override
  Widget build(BuildContext context) {
    final week = widget.mode == 1;
    final start = week ? SpendAnalytics.startOfWeek(anchor)
      : SpendAnalytics.startOfMonth(anchor);
    final end = week ? start.add(const Duration(days: 7))
      : SpendAnalytics.nextMonth(start);
    final prevStart = week ? start.subtract(const Duration(days: 7))
      : SpendAnalytics.previousMonth(start);
    final prevEnd = start;
    final current = SpendAnalytics.summarize(widget.store.entries, start, end);
    final previous = SpendAnalytics.summarize(widget.store.entries, prevStart, prevEnd);
    final hidden = widget.store.flag('privacyMode');
    final days = SpendAnalytics.completedDayCounts(widget.store, current, DateTime.now());
    final title = week
      ? DateFormat('d MMM').format(start) + ' – ' + DateFormat('d MMM yyyy').format(end.subtract(const Duration(days: 1)))
      : DateFormat('MMMM yyyy').format(start);
    final canNext = week
      ? SpendAnalytics.startOfWeek(anchor).isBefore(SpendAnalytics.startOfWeek(DateTime.now()))
      : SpendAnalytics.startOfMonth(anchor).isBefore(SpendAnalytics.startOfMonth(DateTime.now()));
    final categoryRanks = SpendAnalytics.categoryRanking(current);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('Spending reports', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Your money patterns, only on this device', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        SegmentedButton<int>(
          selected: {widget.mode},
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Daily')),
            ButtonSegment(value: 1, label: Text('Weekly')),
            ButtonSegment(value: 2, label: Text('Monthly')),
          ],
          onSelectionChanged: (values) => widget.onModeChanged(values.first),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Open spending calendar'),
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => SpendingCalendarScreen(store: widget.store))),
        ),
        const SizedBox(height: 14),
        Row(children: [
          IconButton(tooltip: 'Previous period', onPressed: () => move(-1),
            icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'Next period',
            onPressed: canNext ? () => move(1) : null,
            icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 10),
        InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(week ? 'THIS WEEK' : 'THIS MONTH',
            style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(rupees(current.total, hidden: hidden),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(SpendAnalytics.comparison(current.total, previous.total)),
          const SizedBox(height: 8),
          Text(current.count.toString() + ' recorded payments',
            style: Theme.of(context).textTheme.bodySmall),
        ])),
        const SizedBox(height: 12),
        InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(week ? 'Daily spending • 7 days' : 'Daily spending • calendar month',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          _SpendingBars(days: current.dayTotals, weekly: week, hidden: hidden),
          const SizedBox(height: 10),
          Text('Each bar represents the amount recorded that day.',
            style: Theme.of(context).textTheme.bodySmall),
        ])),
        const SizedBox(height: 12),
        InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Spending by category',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (categoryRanks.isEmpty) const Text('No transactions recorded for this period.')
          else for (final item in categoryRanks) ...[
            Row(children: [
              Expanded(child: Text(item.key)),
              Text(rupees(item.value, hidden: hidden), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: current.total == 0 ? 0 : item.value / current.total,
                color: Color(widget.store.category(item.key).colorCode),
                minHeight: 9,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              )),
            const SizedBox(height: 12),
          ],
        ])),
        const SizedBox(height: 12),
        InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Budget habits', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('Recorded days within target: ' + days.under.toString()),
          const SizedBox(height: 4),
          Text('Recorded days over target: ' + days.over.toString()),
          const SizedBox(height: 4),
          Text('Days without records: ' + days.untracked.toString()),
          const SizedBox(height: 8),
          Text('Days without entries are not counted as successful budgeting days.',
            style: Theme.of(context).textTheme.bodySmall),
        ])),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => SmallSpendsScreen(store: widget.store))),
          child: InsightCard(child: Row(children: [
            const Icon(Icons.toll_outlined, color: Color(0xFFE3A04C)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Under ₹100 tracker', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(current.smallCount.toString() + ' small purchases',
                style: Theme.of(context).textTheme.bodySmall),
            ])),
            Text(rupees(current.smallTotal, hidden: hidden),
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(Icons.chevron_right),
          ])),
        ),
      ],
    );
  }
}

class _SpendingBars extends StatelessWidget {
  const _SpendingBars({required this.days, required this.weekly, required this.hidden});
  final List<DayTotal> days;
  final bool weekly, hidden;

  @override
  Widget build(BuildContext context) {
    final maxValue = math.max(1, days.fold<int>(0, (top, d) => math.max(top, d.paise)));
    const chartHeight = 115.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        height: 174,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final day in days)
            SizedBox(
              width: weekly ? 43 : 28,
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (weekly)
                  SizedBox(height: 16, child: Text(
                    hidden || day.paise == 0 ? '' : NumberFormat.compact(locale: 'en_IN').format(day.paise / 100),
                    style: const TextStyle(fontSize: 9), maxLines: 1)),
                SizedBox(
                  height: chartHeight,
                  child: Align(alignment: Alignment.bottomCenter, child: Tooltip(
                    message: DateFormat('d MMM yyyy').format(day.date) + ' • ' +
                      rupees(day.paise, hidden: hidden),
                    child: Container(
                      width: weekly ? 23 : 15,
                      height: day.paise == 0 ? 3 : math.max(5, chartHeight * day.paise / maxValue),
                      decoration: BoxDecoration(
                        color: day.paise == 0
                          ? Theme.of(context).colorScheme.outlineVariant
                          : const Color(0xFF20B994),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ),
                  )),
                ),
                const SizedBox(height: 8),
                Text(weekly ? DateFormat('E').format(day.date).substring(0, 2)
                  : day.date.day % 5 == 0 || day.date.day == 1 ? day.date.day.toString() : '',
                  style: const TextStyle(fontSize: 10)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class SpendingCalendarScreen extends StatefulWidget {
  const SpendingCalendarScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<SpendingCalendarScreen> createState() => _SpendingCalendarScreenState();
}

class _SpendingCalendarScreenState extends State<SpendingCalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selected = dayStart(DateTime.now());

  void changeMonth(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
      selected = month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = month.weekday - DateTime.monday;
    final numberOfDays = DateUtils.getDaysInMonth(month.year, month.month);
    final today = dayStart(DateTime.now());
    final canNext = month.isBefore(DateTime(today.year, today.month));
    final hidden = widget.store.flag('privacyMode');
    final entries = widget.store.on(selected);
    final spent = widget.store.spentOn(selected);
    final target = widget.store.targetFor(selected);

    return Scaffold(
      appBar: AppBar(title: const Text('Spending calendar')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        InsightCard(child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: () => changeMonth(-1), icon: const Icon(Icons.chevron_left)),
            Text(DateFormat('MMMM yyyy').format(month),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            IconButton(onPressed: canNext ? () => changeMonth(1) : null,
              icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 10),
          const Row(children: [
            for (final label in ['M','T','W','T','F','S','S'])
              Expanded(child: Text(label, textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 9),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, childAspectRatio: .85, crossAxisSpacing: 3, mainAxisSpacing: 5),
            itemCount: ((firstWeekday + numberOfDays + 6) ~/ 7) * 7,
            itemBuilder: (context, index) {
              final dayNumber = index - firstWeekday + 1;
              if (dayNumber <= 0 || dayNumber > numberOfDays) return const SizedBox.shrink();
              final date = DateTime(month.year, month.month, dayNumber);
              final future = date.isAfter(today);
              final logged = widget.store.on(date).isNotEmpty;
              final actual = widget.store.spentOn(date);
              final cap = widget.store.targetFor(date);
              final isOver = actual > cap;
              final color = future || !logged
                ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .25)
                : isOver ? const Color(0xFFE96363) : const Color(0xFF20B994);
              final isSelected = sameDay(date, selected);
              return Material(
                color: color.withValues(alpha: future || !logged ? .04 : .15),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: future ? null : () => setState(() => selected = date),
                  child: Container(
                    decoration: BoxDecoration(
                      border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.6) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(dayNumber.toString(), style: TextStyle(fontWeight: FontWeight.w800,
                        color: future ? Theme.of(context).disabledColor : null)),
                      const SizedBox(height: 4),
                      Container(width: 6, height: 6,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ]),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 13, runSpacing: 6, children: const [
            _Legend(Color(0xFF20B994), 'Within limit'),
            _Legend(Color(0xFFE96363), 'Over limit'),
            _Legend(Color(0xFFACB2B8), 'No record'),
          ]),
        ])),
        const SizedBox(height: 14),
        InsightCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE, d MMM yyyy').format(selected),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          Text(rupees(spent, hidden: hidden) + ' spent / ' +
            rupees(target, hidden: hidden) + ' target',
            style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (entries.isEmpty) const Text('No payments recorded on this day.')
          else for (final item in entries) ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(item.payee.isEmpty ? item.category : item.payee),
            subtitle: Text(item.category),
            trailing: Text(rupees(item.paise, hidden: hidden)),
          ),
        ])),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.title);
  final Color color;
  final String title;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    CircleAvatar(backgroundColor: color, radius: 4),
    const SizedBox(width: 5),
    Text(title, style: Theme.of(context).textTheme.labelSmall),
  ]);
}
