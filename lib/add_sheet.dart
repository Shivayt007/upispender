import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data.dart';

Future<bool> showQuickAdd(
  BuildContext context,
  SpendStore store, {
  SpendEntry? editing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => QuickAddSheet(store: store, editing: editing),
  );
  return result ?? false;
}

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key, required this.store, this.editing});
  final SpendStore store;
  final SpendEntry? editing;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  late final TextEditingController payee;
  late final TextEditingController note;
  String amount = '';
  String category = 'Food';
  String tag = 'Needed';
  late DateTime when;
  bool detailsOpen = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.editing;
    payee = TextEditingController(text: entry?.payee ?? '');
    note = TextEditingController(text: entry?.note ?? '');
    amount = entry == null
        ? '' : (entry.paise / 100).toStringAsFixed(entry.paise % 100 == 0 ? 0 : 2);
    category = entry?.category ?? 'Food';
    tag = entry?.tag ?? 'Needed';
    when = entry?.at ?? DateTime.now();
    detailsOpen = entry != null;
  }

  @override
  void dispose() {
    payee.dispose();
    note.dispose();
    super.dispose();
  }

  void press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == '⌫') {
        if (amount.isNotEmpty) amount = amount.substring(0, amount.length - 1);
      } else if (key == '.') {
        if (!amount.contains('.')) amount = amount.isEmpty ? '0.' : '$amount.';
      } else if (amount.length < 9 && (!(amount.contains('.') && amount.split('.').last.length >= 2))) {
        amount = amount == '0' ? key : '$amount$key';
      }
    });
  }

  Future<void> chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: when,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (!mounted || selected == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when));
    if (time == null || !mounted) return;
    setState(() => when = DateTime(selected.year, selected.month, selected.day, time.hour, time.minute));
  }

  Future<void> save() async {
    final value = parsePaise(amount);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount greater than ₹0')),
      );
      return;
    }
    if (saving) return;
    setState(() => saving = true);
    try {
      final entry = SpendEntry(
        id: widget.editing?.id,
        paise: value,
        category: category,
        payee: payee.text.trim(),
        note: note.text.trim(),
        tag: tag,
        at: when,
      );
      if (widget.editing == null) {
        await widget.store.add(entry);
      } else {
        await widget.store.update(entry);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, insets + 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .87),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(widget.editing == null ? 'Add payment' : 'Edit payment',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: 4),
                Text('Offline', style: theme.textTheme.labelMedium),
              ]),
              const SizedBox(height: 8),
              Center(child: Text(
                amount.isEmpty ? '₹0' : '₹$amount',
                style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800),
              )),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                mainAxisSpacing: 2,
                crossAxisSpacing: 5,
                children: [
                  for (final key in const ['1','2','3','4','5','6','7','8','9','.','0','⌫'])
                    TextButton(
                      onPressed: () => press(key),
                      child: Text(key, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text('CATEGORY', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.6)),
              const SizedBox(height: 8),
              SizedBox(
                height: 43,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.store.categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final item = widget.store.categories[index];
                    return ChoiceChip(
                      label: Text(item.name),
                      selected: item.name == category,
                      onSelected: (_) => setState(() => category = item.name),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => detailsOpen = !detailsOpen),
                  icon: Icon(detailsOpen ? Icons.expand_less : Icons.tune),
                  label: Text(detailsOpen ? 'Hide optional details' : 'Payee, note, tag & date (optional)'),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                alignment: Alignment.topCenter,
                child: !detailsOpen ? const SizedBox(width: double.infinity) :
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: payee,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Payee (e.g. Swiggy)'),
                      onChanged: (text) {
                        if (widget.editing == null && text.trim().isNotEmpty) {
                          final suggestion = widget.store.suggestCategory(text);
                          if (suggestion != category) setState(() => category = suggestion);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      selected: {tag},
                      segments: const [
                        ButtonSegment(value: 'Needed', label: Text('Needed'), icon: Icon(Icons.check_circle_outline)),
                        ButtonSegment(value: 'Impulse', label: Text('Impulse'), icon: Icon(Icons.bolt_outlined)),
                      ],
                      onSelectionChanged: (tags) => setState(() => tag = tags.first),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: chooseDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text('x'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: Icon(saving ? Icons.hourglass_empty : Icons.check_circle_outline),
                label: Text(saving ? 'Saving…' : widget.editing == null ? 'Save payment' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
