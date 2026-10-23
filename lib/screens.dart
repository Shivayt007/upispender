import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'data.dart';
import 'notifications.dart';
import 'sms_capture.dart';
import 'insights_screens.dart';
import 'add_sheet.dart';

IconData categoryIcon(String name) => switch (name) {
  'Food' => Icons.restaurant_outlined,
  'Travel' => Icons.directions_bus_outlined,
  'Bills' => Icons.receipt_long_outlined,
  'Shopping' => Icons.shopping_bag_outlined,
  'Groceries' => Icons.shopping_basket_outlined,
  'Health' => Icons.health_and_safety_outlined,
  'Entertainment' => Icons.movie_outlined,
  _ => Icons.category_outlined,
};

Color spendingColor(double ratio) => ratio > 1
    ? const Color(0xFFE95A5A)
    : ratio >= .8 ? const Color(0xFFF4A640) : const Color(0xFF20B994);

Widget sectionTitle(String title, {Widget? trailing}) => Row(
  children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
    if (trailing != null) trailing,
  ],
);

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.brightness == Brightness.dark
          ? const Color(0xFF1D2A31) : Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: Theme.of(context).brightness == Brightness.light
          ? const [BoxShadow(color: Color(0x0B172C38), blurRadius: 20, offset: Offset(0, 6))]
          : null,
    ),
    child: child,
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.onAdd});
  final SpendStore store;
  final VoidCallback onAdd;

  void affordability(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final amount = parsePaise(controller.text) ?? 0;
          final projection = store.todaySpent + amount;
          final left = store.todayTarget - projection;
          final hidden = store.flag('privacyMode');
          return AlertDialog(
            title: const Text('Can I afford this?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Planned purchase'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                Text('New total: ' + rupees(projection, hidden: hidden)),
                const SizedBox(height: 6),
                Text('Left afterward: ' + rupees(left, hidden: hidden),
                    style: TextStyle(fontWeight: FontWeight.bold, color: left < 0 ? Colors.redAccent : const Color(0xFF18AA84))),
                const SizedBox(height: 10),
                Text(amount == 0
                    ? 'Enter a price to preview your budget.'
                    : left >= 0
                        ? 'Within target. You can plan this purchase.'
                        : 'This would exceed your daily target.'),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
          );
        },
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final report = store.snapshot(today);
    final hidden = store.flag('privacyMode');
    final left = report.left;
    final hours = math.max(1, 24 - today.hour);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 105),
      children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('UPI SPEND TRACKER', style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('Your money, in control.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: -.6)),
          ])),
          const CircleAvatar(
            radius: 24, backgroundColor: Color(0xFFDBF6EE),
            child: Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF13A982)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(DateFormat('EEEE, d MMMM yyyy').format(today),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        SmsReviewBanner(store: store),
        BudgetWarningsPanel(store: store),
        const SizedBox(height: 20),
        SurfaceCard(child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('TODAY’S SPENDING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
            DecoratedBox(
              decoration: BoxDecoration(
                color: spendingColor(report.ratio).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(report.ratio > 1 ? 'Over budget' : report.ratio >= .8 ? 'Almost there' : 'On track',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: spendingColor(report.ratio))),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: report.ratio.clamp(0, 1)),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (ctx, value, _) => SizedBox(
              width: 230, height: 230,
              child: CustomPaint(
                painter: RingPainter(value, spendingColor(report.ratio),
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: .07)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Spent today', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(rupees(report.spent, hidden: hidden), style: const TextStyle(
                      fontSize: 35, fontWeight: FontWeight.w900, letterSpacing: -1.3)),
                  ),
                  Text('of ' + rupees(report.target, hidden: hidden),
                      style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: Theme.of(context).dividerColor.withValues(alpha: .4)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Stat(
              caption: left >= 0 ? 'Left today' : 'Over by',
              value: rupees(left.abs(), hidden: hidden),
              icon: left >= 0 ? Icons.savings_outlined : Icons.warning_amber_rounded,
            )),
            Container(height: 45, width: 1, color: Theme.of(context).dividerColor),
            const SizedBox(width: 16),
            Expanded(child: _Stat(
              caption: 'Safe per hour',
              value: rupees(math.max(0, left) ~/ hours, hidden: hidden),
              icon: Icons.schedule_rounded,
            )),
          ]),
        ])),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _ActionCard(
            icon: Icons.calculate_outlined, title: 'Can I afford this?',
            subtitle: 'Preview before paying',
            onTap: () => affordability(context),
          )),
          const SizedBox(width: 10),
          Expanded(child: _ActionCard(
            icon: Icons.local_fire_department_outlined,
            title: store.streak.toString() + ' day streak',
            subtitle: 'Days under budget',
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Keep your streak going 🔥'),
                content: Text('You have ' + store.streak.toString() +
                    ' consecutive completed days within budget. No-spend days count too.'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice!'))],
              ),
            ),
          )),
        ]),
        SmallSpendsShortcut(store: store),
        const SizedBox(height: 24),
        sectionTitle('Today’s activity', trailing: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (ctx) => HistoryScreen(store: store),
          )),
          child: const Text('See all  →'),
        )),
        const SizedBox(height: 8),
        if (report.entries.isEmpty)
          SurfaceCard(child: Column(children: [
            const SizedBox(height: 12),
            Icon(Icons.receipt_long_outlined, size: 46, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('Nothing spent yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('Tap + to record your first payment.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add payment')),
          ]))
        else
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(children: [
              for (final item in report.entries.take(7))
                ExpenseTile(entry: item, store: store),
            ]),
          ),
        const SizedBox(height: 18),
        SurfaceCard(child: Row(children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF20B994)),
          const SizedBox(width: 12),
          Expanded(child: Text('Your spending stays on this device. No bank connection needed.',
            style: Theme.of(context).textTheme.bodySmall)),
        ])),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.caption, required this.value, required this.icon});
  final String caption, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6), Flexible(child: Text(caption, style: Theme.of(context).textTheme.labelMedium))]),
    const SizedBox(height: 6),
    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
      child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
  ]);
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(15), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 11),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    ),
  );
}

class RingPainter extends CustomPainter {
  const RingPainter(this.value, this.progressColor, this.trackColor);
  final double value;
  final Color progressColor, trackColor;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(15, 15, size.width - 30, size.height - 30);
    final base = Paint()..color = trackColor..style = PaintingStyle.stroke
      ..strokeWidth = 17..strokeCap = StrokeCap.round;
    canvas.drawArc(bounds, 0, 2 * math.pi, false, base);
    final progress = Paint()..color = progressColor..style = PaintingStyle.stroke
      ..strokeWidth = 17..strokeCap = StrokeCap.round;
    canvas.drawArc(bounds, -math.pi / 2, (2 * math.pi * value), false, progress);
  }
  @override
  bool shouldRepaint(covariant RingPainter old) =>
      old.value != value || old.progressColor != progressColor || old.trackColor != trackColor;
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.entry, required this.store});
  final SpendEntry entry;
  final SpendStore store;

  Future<void> delete(BuildContext context) async {
    await store.remove(entry);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Payment deleted'),
      action: SnackBarAction(label: 'UNDO', onPressed: store.undo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cat = store.category(entry.category);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 1),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Color(cat.colorCode).withValues(alpha: .15),
        child: Icon(categoryIcon(entry.category), color: Color(cat.colorCode), size: 21),
      ),
      title: Text(entry.payee.isEmpty ? entry.category : entry.payee,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(entry.category + ' · ' + DateFormat('h:mm a').format(entry.at)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('−' + rupees(entry.paise, hidden: store.flag('privacyMode')),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        PopupMenuButton<String>(
          tooltip: 'Transaction options',
          icon: const Icon(Icons.more_vert, size: 19),
          onSelected: (action) {
            if (action == 'edit') {
              showQuickAdd(context, store, editing: entry);
            } else {
              delete(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  String query = '';
  String category = 'All';
  String tag = 'All';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment history')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final filtered = widget.store.entries.where((e) {
            final q = query.toLowerCase();
            return (e.payee.toLowerCase().contains(q) || e.note.toLowerCase().contains(q)) &&
                (category == 'All' || category == e.category) &&
                (tag == 'All' || tag == e.tag);
          }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                  hintText: 'Search payee or note'),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            SizedBox(height: 45, child: ListView(scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                DropdownButton<String>(
                  value: category,
                  items: ['All', ...widget.store.categories.map((e) => e.name)]
                      .map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                  onChanged: (v) => setState(() => category = v ?? 'All'),
                ),
                const SizedBox(width: 20),
                DropdownButton<String>(
                  value: tag,
                  items: ['All', 'Needed', 'Impulse'].map((name) =>
                      DropdownMenuItem(value: name, child: Text(name))).toList(),
                  onChanged: (v) => setState(() => tag = v ?? 'All'),
                ),
              ],
            )),
            Expanded(child: filtered.isEmpty
                ? const Center(child: Text('No matching payments'))
                : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 4),
                  itemBuilder: (context, i) => ExpenseTile(
                    entry: filtered[i], store: widget.store),
                )),
          ]);
        },
      ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime day = DateTime.now();
  int reportMode = 0;
  Future<void> pickDate() async {
    final choice = await showDatePicker(
      context: context, initialDate: day,
      firstDate: DateTime(2020), lastDate: DateTime.now(),
    );
    if (choice != null) setState(() => day = choice);
  }

  @override
  Widget build(BuildContext context) {
    if (reportMode != 0) {
      return PeriodDashboard(
        store: widget.store, mode: reportMode,
        onModeChanged: (mode) => setState(() => reportMode = mode),
      );
    }
    final snapshot = widget.store.snapshot(day);
    final hidden = widget.store.flag('privacyMode');
    final positive = snapshot.left >= 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 35),
      children: [
        Text('Daily report', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text('Small steps. Stronger habits.'),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          selected: {reportMode}, showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Daily')),
            ButtonSegment(value: 1, label: Text('Weekly')),
            ButtonSegment(value: 2, label: Text('Monthly')),
          ],
          onSelectionChanged: (values) => setState(() => reportMode = values.first),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => SpendingCalendarScreen(store: widget.store))),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Spending calendar'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => SmallSpendsScreen(store: widget.store))),
          icon: const Icon(Icons.toll_outlined),
          label: const Text('Small-spending tracker'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(DateFormat('EEEE, d MMM yyyy').format(day)),
        ),
        const SizedBox(height: 16),
        SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TOTAL SPENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Text(rupees(snapshot.spent, hidden: hidden),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(positive
              ? rupees(snapshot.left, hidden: hidden) + ' under target'
              : rupees(-snapshot.left, hidden: hidden) + ' over target',
              style: TextStyle(fontWeight: FontWeight.bold, color: positive ? const Color(0xFF1EAC86) : Colors.redAccent)),
          const SizedBox(height: 15),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
            value: snapshot.ratio.clamp(0, 1),
            minHeight: 11, color: spendingColor(snapshot.ratio),
            backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: .09),
          )),
        ])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: SurfaceCard(child: _ReportMetric('Transactions',
            snapshot.entries.length.toString(), Icons.receipt_outlined))),
          const SizedBox(width: 12),
          Expanded(child: SurfaceCard(child: _ReportMetric('Daily target',
            rupees(snapshot.target, hidden: hidden), Icons.flag_outlined))),
        ]),
        const SizedBox(height: 12),
        SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle('Where it went'),
          const SizedBox(height: 14),
          _ReportRow(icon: Icons.category_outlined, label: 'Top category', value: snapshot.topCategory),
          const Divider(),
          _ReportRow(icon: Icons.storefront_outlined, label: 'Top payee', value: snapshot.topPayee),
          const Divider(),
          _ReportRow(icon: Icons.check_circle_outline, label: 'Needed',
              value: rupees(snapshot.needed, hidden: hidden)),
          const Divider(),
          _ReportRow(icon: Icons.bolt_outlined, label: 'Impulse',
              value: rupees(snapshot.impulse, hidden: hidden)),
          if (snapshot.spent > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(children: [
                Expanded(flex: math.max(1, snapshot.needed), child: Container(height: 12, color: const Color(0xFF22B68E))),
                Expanded(flex: math.max(1, snapshot.impulse), child: Container(height: 12, color: const Color(0xFFF1AA50))),
              ]),
            ),
          ],
        ])),
        const SizedBox(height: 12),
        SurfaceCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline, color: Color(0xFFF1AA50)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your daily insight', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(snapshot.insight),
          ])),
        ])),
        const SizedBox(height: 18),
        Text('Sharing as an image/PDF and full exports are planned for a future release.',
            style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 12),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
    const SizedBox(height: 4),
    Text(label, style: Theme.of(context).textTheme.labelMedium),
  ]);
}
class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Icon(icon, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
      Flexible(child: Text(value, textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w800))),
    ]),
  );
}

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}
class _BudgetScreenState extends State<BudgetScreen> {
  late TextEditingController daily;
  late TextEditingController weekdays;
  late TextEditingController weekends;
  @override
  void initState() {
    super.initState();
    daily = TextEditingController(text: (widget.store.number('dailyLimit') / 100).toStringAsFixed(0));
    weekdays = TextEditingController(text: (widget.store.number('weekdayLimit') / 100).toStringAsFixed(0));
    weekends = TextEditingController(text: (widget.store.number('weekendLimit') / 100).toStringAsFixed(0));
  }
  @override
  void dispose() {
    daily.dispose(); weekdays.dispose(); weekends.dispose();
    super.dispose();
  }
  Future<void> save() async {
    final a = parsePaise(daily.text);
    final b = parsePaise(weekdays.text);
    final c = parsePaise(weekends.text);
    if (a == null || b == null || c == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter positive budget amounts')));
      return;
    }
    await widget.store.setting('dailyLimit', a);
    await widget.store.setting('weekdayLimit', b);
    await widget.store.setting('weekendLimit', c);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Daily budget saved')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 32), children: [
      Text('Your budget', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Build a target you can actually follow.'),
      const SizedBox(height: 18),
      SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Default daily target', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        TextField(controller: daily,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Daily spending limit')),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Different weekday / weekend targets'),
          value: widget.store.flag('differentLimits'),
          onChanged: (v) => widget.store.setting('differentLimits', v),
        ),
        if (widget.store.flag('differentLimits')) ...[
          const SizedBox(height: 12),
          TextField(controller: weekdays,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Weekdays (Mon–Fri)')),
          const SizedBox(height: 10),
          TextField(controller: weekends,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Weekends (Sat–Sun)')),
        ],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: save, icon: const Icon(Icons.save_outlined), label: const Text('Save target'))),
      ])),
      const SizedBox(height: 14),
      CategoryBudgetsCard(store: widget.store),
      const SizedBox(height: 14),
      SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle('Motivation'),
        const SizedBox(height: 14),
        _ReportRow(icon: Icons.local_fire_department_outlined,
            label: 'Under-budget streak', value: widget.store.streak.toString() + ' days'),
        const Divider(),
        _ReportRow(icon: Icons.savings_outlined,
            label: 'Saved vs targets this month',
            value: rupees(widget.store.currentMonthSaved, hidden: widget.store.flag('privacyMode'))),
        const Divider(),
        _ReportRow(icon: Icons.stars_outlined, label: '7-day streak badge',
            value: widget.store.streak >= 7 ? 'Unlocked 🏅' : 'Keep going'),
        const Divider(),
        _ReportRow(icon: Icons.nightlight_outlined, label: 'No-spend day challenge',
            value: widget.store.todaySpent == 0 ? 'On track today' : 'Try tomorrow'),
      ])),
      const SizedBox(height: 14),
      SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle('Coming in future versions'),
        const SizedBox(height: 8),
        const Text('Rollover, weekly bonus budget, salary-cycle budgeting, target suggestions and recurring bills.'),
      ])),
    ]);
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final SpendStore store;

  Future<void> chooseReportTime(BuildContext context) async {
    final selection = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: store.number('reportHour'), minute: store.number('reportMinute')),
    );
    if (selection == null) return;
    await store.setting('reportHour', selection.hour);
    await store.setting('reportMinute', selection.minute);
    await SpendNotifications.instance.scheduleReport(store);
  }

  Future<void> createCategory(BuildContext context) async {
    final controller = TextEditingController();
    var selected = 0;
    const palette = [0xFF20B994, 0xFF729DF3, 0xFFED8069, 0xFFBA87E9, 0xFFE6B558];
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: const Text('New category'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: controller, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Category name')),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < palette.length; i++)
              InkWell(
                onTap: () => update(() => selected = i),
                child: CircleAvatar(
                  radius: i == selected ? 20 : 16,
                  backgroundColor: Color(palette[i]),
                  child: i == selected ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            final added = await store.addCategory(controller.text, palette[selected], 'custom');
            if (ctx.mounted) {
              Navigator.pop(ctx);
              if (!added) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Choose a unique category name')));
            }
          }, child: const Text('Add')),
        ],
      ),
    ));
    // The field is no longer mounted after the dialog closes.
    controller.dispose();
  }

  Future<void> confirmDelete(BuildContext context) async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('Delete all payments?'),
        content: const Text('This permanently erases every recorded payment from this device. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete everything', style: TextStyle(color: Colors.redAccent))),
        ],
      ));
    if (accepted == true) {
      await store.clearAll();
      await SmsDetection.instance.clear();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All payments deleted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportTime = TimeOfDay(hour: store.number('reportHour'),
        minute: store.number('reportMinute')).format(context);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 36), children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Simple controls. Your data stays yours.'),
      const SizedBox(height: 18),
      SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Column(children: [
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('Dark mode'), value: store.flag('darkMode'),
          onChanged: (v) => store.setting('darkMode', v)),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Hide amounts'), subtitle: const Text('Privacy mode'),
          value: store.flag('privacyMode'),
          onChanged: (v) => store.setting('privacyMode', v)),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Budget & daily report notifications'),
          value: store.flag('notifications'),
          onChanged: (v) async {
            if (v) await SpendNotifications.instance.requestPermission();
            await store.setting('notifications', v);
            await SpendNotifications.instance.scheduleReport(store);
            await SpendNotifications.instance.scheduleEveningReminder(store);
          }),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.nights_stay_outlined),
          title: const Text('Evening check-in reminder'),
          subtitle: const Text('7:30 PM reminder (not conditional on logged payments)'),
          value: store.flag('reminder'),
          onChanged: (v) async {
            await store.setting('reminder', v);
            await SpendNotifications.instance.scheduleEveningReminder(store);
          }),
        ListTile(
          leading: const Icon(Icons.access_time_outlined),
          title: const Text('Daily report time'),
          subtitle: Text(reportTime),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => chooseReportTime(context),
        ),
      ])),
      const SizedBox(height: 14),
      SurfaceCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Column(children: [
        ListTile(
          leading: const Icon(Icons.sms_outlined),
          title: const Text('Automatic UPI SMS detection'),
          subtitle: const Text('Opt in to recognize incoming bank debit alerts'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (ctx) => SmsSettingsScreen(store: store))),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Custom categories'),
          subtitle: Text(store.categories.length.toString() + ' categories available'),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: () => createCategory(context),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Payment history'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (ctx) => HistoryScreen(store: store))),
        ),
      ])),
      const SizedBox(height: 14),
      SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle('Privacy & storage'),
        const SizedBox(height: 8),
        const Text('SQLite data is stored in Android’s app-private storage. No sign-in, cloud sync or server.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => confirmDelete(context),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete all payments'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
        ),
      ])),
      const SizedBox(height: 14),
      Text('UPI Spend Tracker • v1.2\nIncoming UPI SMS detection is optional. Statement imports, PIN/biometrics, widgets, backup and exports are still planned.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
