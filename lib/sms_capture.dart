import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'data.dart';
import 'notifications.dart';

class SmsDetection {
  SmsDetection._();
  static final SmsDetection instance = SmsDetection._();
  static const _channel = MethodChannel('com.upispender.upispender/sms');

  Future<SmsStatus> status() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('status');
      return SmsStatus(
        permission: result?['permission'] == true,
        enabled: result?['enabled'] == true,
        pending: (result?['pending'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return const SmsStatus(permission: false, enabled: false, pending: 0);
    }
  }

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<bool> enable(bool value) async =>
      await _channel.invokeMethod<bool>('enable', {'value': value}) ?? false;

  Future<List<DetectedDebit>> pending() async {
    final raw = await _channel.invokeListMethod<dynamic>('pending') ?? [];
    return raw.map((row) => DetectedDebit.fromMap(Map<String, dynamic>.from(row as Map))).toList();
  }

  Future<void> dismiss(String id) async {
    final removed = await _channel.invokeMethod<bool>('dismiss', {'id': id});
    if (removed != true) throw StateError('Unable to clear reviewed SMS entry');
  }

  Future<void> clear() async => _channel.invokeMethod<void>('clear');
}

class SmsStatus {
  const SmsStatus({required this.permission, required this.enabled, required this.pending});
  final bool permission;
  final bool enabled;
  final int pending;
  bool get active => permission && enabled;
}

class DetectedDebit {
  const DetectedDebit({
    required this.id, required this.paise, required this.payee,
    required this.at, required this.sender,
  });
  final String id, payee, sender;
  final int paise;
  final DateTime at;

  factory DetectedDebit.fromMap(Map<String, dynamic> map) => DetectedDebit(
    id: map['id'] as String,
    paise: (map['paise'] as num).toInt(),
    payee: (map['payee'] as String?) ?? '',
    at: DateTime.fromMillisecondsSinceEpoch((map['at'] as num).toInt()),
    sender: (map['sender'] as String?) ?? '',
  );
}

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> with WidgetsBindingObserver {
  SmsStatus? status;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final next = await SmsDetection.instance.status();
      if (mounted) setState(() { status = next; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> toggle(bool enabled) async {
    if (busy) return;
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow incoming bank SMS detection?'),
          content: const Text(
            'UPI Spend Tracker will access new incoming SMS messages to identify UPI debit amounts '
            'and possible payees. It rejects OTPs, credit and failed-payment messages. '
            'Detected payments remain on this device for your review and are not added '
            'to your budget until you approve them. No SMS content is sent to a server. '
            'You may disable detection at any time in Settings. '
            'Only future incoming SMS are examined; existing messages are not scanned.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      if (enabled) {
        final granted = await SmsDetection.instance.requestPermission();
        if (!granted) throw StateError('SMS permission was not granted in Android settings.');
        await SpendNotifications.instance.requestPermission();
      }
      final success = await SmsDetection.instance.enable(enabled);
      if (!success) throw StateError('Cannot activate without RECEIVE_SMS permission.');
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = status?.active ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic SMS detection')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.sms_outlined, size: 34),
            const SizedBox(height: 12),
            const Text('Detect new UPI debit messages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 7),
            const Text('Bank SMS → local detection → review and choose category → save to daily spending.'),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(active ? 'Detection enabled' : 'Detection disabled'),
              subtitle: Text(status?.permission == true ? 'Android SMS permission granted' : 'SMS access not granted'),
              value: active, onChanged: busy ? null : toggle,
            ),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ]),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.inbox_outlined),
          title: const Text('Review detected payments'),
          subtitle: Text((status?.pending ?? 0).toString() + ' awaiting confirmation'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => SmsInboxScreen(store: widget.store),
            ));
            await refresh();
          },
        )),
        const SizedBox(height: 18),
        const Text('Privacy & accuracy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        const Text(
          '• Only incoming SMS after you enable this feature are processed.\n'
          '• Raw SMS and OTPs are not saved. Only a debit candidate, sender label, timestamp, amount, and deduplication hash are stored locally.\n'
          '• Only messages with recognizable UPI and debit markers are considered.\n'
          '• A UPI message may arrive late, omit the merchant, or never arrive. Check results before approving.\n'
          '• When disabled, no new messages are captured. Existing pending detections remain reviewable.\n'
          '• No READ_SMS access to your full inbox, no bank login, and no cloud upload.\n'
          '• Background reception may not work if Android force-stops the app or SMS permission is revoked.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: refresh,
          icon: const Icon(Icons.refresh), label: const Text('Refresh detection status')),
      ]),
    );
  }
}

class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({super.key, required this.store});
  final SpendStore store;
  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> with WidgetsBindingObserver {
  List<DetectedDebit> pending = [];
  final Map<String, String> chosen = {};
  String? busyId;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final records = await SmsDetection.instance.pending();
      if (mounted) setState(() { pending = records; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> process(DetectedDebit item, {required bool approve}) async {
    if (busyId != null) return;
    setState(() => busyId = item.id);
    try {
      if (approve) {
        final before = widget.store.todaySpent;
        await widget.store.importSms(
          fingerprint: item.id,
          paise: item.paise,
          payee: item.payee,
          category: chosen[item.id] ?? widget.store.suggestCategory(item.payee),
          at: item.at,
        );
        await SpendNotifications.instance.spendingChanged(widget.store, before);
      }
      await SmsDetection.instance.dismiss(item.id);
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Payment saved locally' : 'Detection dismissed')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not process payment: $e');
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = widget.store.flag('privacyMode');
    return Scaffold(
      appBar: AppBar(title: const Text('Detected UPI payments'),
        actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))]),
      body: pending.isEmpty ? Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(error ?? 'No pending UPI payments.\nNew incoming bank debit SMS will appear here for approval.',
          textAlign: TextAlign.center),
      )) : ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 7, vertical: 10),
            child: Text('Review every payment to avoid incorrect or duplicate spending.')),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
          for (final item in pending)
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rupees(item.paise, hidden: hidden),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(item.payee.isEmpty ? 'Unknown payee — check your bank message' : item.payee,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('From ' + item.sender + ' • ' + DateFormat('dd MMM, h:mm a').format(item.at),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: chosen[item.id] ??
                      (widget.store.categories.any((e) => e.name == widget.store.suggestCategory(item.payee))
                      ? widget.store.suggestCategory(item.payee) : 'Other'),
                  items: [
                    for (final cat in widget.store.categories)
                      DropdownMenuItem(value: cat.name, child: Text(cat.name)),
                  ],
                  onChanged: (value) => setState(() => chosen[item.id] = value ?? 'Other'),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: busyId != null ? null : () => process(item, approve: false),
                    child: const Text('Ignore'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(
                    onPressed: busyId != null ? null : () => process(item, approve: true),
                    child: const Text('Save payment'),
                  )),
                ]),
              ]),
            )),
        ],
      ),
    );
  }
}
