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
