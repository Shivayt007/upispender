import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

String rupees(int paise, {bool hidden = false}) {
  if (hidden) return '₹••••';
  return NumberFormat.currency(
    locale: 'en_IN', symbol: '₹',
    decimalDigits: paise % 100 == 0 ? 0 : 2,
  ).format(paise / 100);
}

int? parsePaise(String raw) {
  final number = double.tryParse(raw.replaceAll(',', '').trim());
  if (number == null || !number.isFinite || number <= 0 || number > 100000000) {
    return null;
  }
  return (number * 100).round();
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);

class SpendCategory {
  const SpendCategory(this.name, this.colorCode, this.iconName);
  final String name;
  final int colorCode;
  final String iconName;
}

const defaultCategories = <SpendCategory>[
  SpendCategory('Food', 0xFFEE8656, 'restaurant'),
  SpendCategory('Travel', 0xFF5F9AEF, 'commute'),
  SpendCategory('Bills', 0xFFB59AF5, 'receipt'),
  SpendCategory('Shopping', 0xFFE970A9, 'bag'),
  SpendCategory('Groceries', 0xFF68B89F, 'grocery'),
  SpendCategory('Health', 0xFFEB7474, 'health'),
  SpendCategory('Entertainment', 0xFFE4B45C, 'movie'),
  SpendCategory('Other', 0xFF7F91A7, 'other'),
];

class SpendEntry {
  const SpendEntry({
    this.id, required this.paise, required this.category,
    required this.at, this.payee = '', this.note = '', this.tag = 'Needed',
  });
  final int? id;
  final int paise;
  final String payee;
  final String category;
  final String note;
  final String tag;
  final DateTime at;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'amount_paise': paise,
    'payee': payee,
    'category': category,
    'note': note,
    'tag': tag,
    'occurred_at': at.millisecondsSinceEpoch,
  };

  static SpendEntry fromMap(Map<String, Object?> m) => SpendEntry(
    id: m['id'] as int?,
    paise: m['amount_paise'] as int,
    payee: (m['payee'] as String?) ?? '',
    category: (m['category'] as String?) ?? 'Other',
    note: (m['note'] as String?) ?? '',
    tag: (m['tag'] as String?) ?? 'Needed',
    at: DateTime.fromMillisecondsSinceEpoch(m['occurred_at'] as int),
  );
}

class DailySnapshot {
  const DailySnapshot({
    required this.day, required this.spent, required this.target,
    required this.entries, required this.topPayee, required this.topCategory,
    required this.needed, required this.impulse, required this.insight,
  });
  final DateTime day;
  final int spent;
  final int target;
  final List<SpendEntry> entries;
  final String topPayee;
  final String topCategory;
  final int needed;
  final int impulse;
  final String insight;
  int get left => target - spent;
  double get ratio => target <= 0 ? 0 : spent / target;
}

class SpendStore extends ChangeNotifier {
  Database? _db;
  final List<SpendEntry> entries = [];
  final List<SpendCategory> categories = [];
  final Map<String, String> _prefs = {};
  SpendEntry? _undoEntry;
  bool _undoWasDelete = false;
  bool ready = false;

  static const defaultPrefs = <String, String>{
    'dailyLimit': '100000',
    'weekdayLimit': '100000',
    'weekendLimit': '120000',
    'differentLimits': 'false',
    'darkMode': 'false',
    'privacyMode': 'false',
    'notifications': 'true',
    'reminder': 'false',
    'reportHour': '21',
    'reportMinute': '0',
    'quietStart': '22',
    'quietEnd': '8',
  };

  String getPref(String name) => _prefs[name] ?? defaultPrefs[name] ?? '';
  bool flag(String name) => getPref(name) == 'true';
  int number(String name) => int.tryParse(getPref(name)) ?? 0;
  int get todayTarget => targetFor(DateTime.now());

  int targetFor(DateTime date) {
    if (!flag('differentLimits')) return number('dailyLimit');
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday
        ? number('weekendLimit') : number('weekdayLimit');
  }

  Future<void> init() async {
    final dbPath = p.join(await getDatabasesPath(), 'upispender_v1.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, amount_paise INTEGER NOT NULL, payee TEXT NOT NULL, category TEXT NOT NULL, note TEXT NOT NULL, tag TEXT NOT NULL, occurred_at INTEGER NOT NULL)');
      await db.execute('CREATE INDEX idx_transactions_date ON transactions (occurred_at DESC)');
      await db.execute('CREATE TABLE categories (name TEXT PRIMARY KEY, color_code INTEGER NOT NULL, icon_name TEXT NOT NULL)');
      await db.execute('CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      final batch = db.batch();
      for (final category in defaultCategories) {
        batch.insert('categories', {'name': category.name, 'color_code': category.colorCode, 'icon_name': category.iconName});
      }
      for (final setting in defaultPrefs.entries) {
        batch.insert('preferences', {'key': setting.key, 'value': setting.value});
      }
      await batch.commit(noResult: true);
    });
    await reload();
    ready = true;
    notifyListeners();
  }

  Future<void> reload() async {
    final txRows = await _db!.query('transactions', orderBy: 'occurred_at DESC, id DESC');
    entries..clear()..addAll(txRows.map(SpendEntry.fromMap));
    final catRows = await _db!.query('categories', orderBy: 'rowid ASC');
    categories
      ..clear()
      ..addAll(catRows.map((c) => SpendCategory(c['name'] as String, c['color_code'] as int, c['icon_name'] as String)));
    final prefRows = await _db!.query('preferences');
    _prefs
      ..clear()
      ..addAll({for (final x in prefRows) x['key'] as String: x['value'] as String});
    notifyListeners();
  }

  Future<void> setting(String key, Object value) async {
    final str = value.toString();
    await _db!.insert('preferences', {'key': key, 'value': str}, conflictAlgorithm: ConflictAlgorithm.replace);
    _prefs[key] = str;
    notifyListeners();
  }

  Future<SpendEntry> add(SpendEntry entry) async {
    final id = await _db!.insert('transactions', entry.toMap());
    final inserted = SpendEntry(id: id, paise: entry.paise,
      payee: entry.payee, category: entry.category, note: entry.note,
      tag: entry.tag, at: entry.at);
    _undoEntry = inserted;
    _undoWasDelete = false;
    await reload();
    return inserted;
  }

  Future<void> update(SpendEntry entry) async {
    if (entry.id == null) return;
    await _db!.update('transactions', entry.toMap(), where: 'id = ?', whereArgs: [entry.id]);
    await reload();
  }

  Future<void> remove(SpendEntry entry) async {
    if (entry.id == null) return;
    _undoEntry = entry;
    _undoWasDelete = true;
    await _db!.delete('transactions', where: 'id = ?', whereArgs: [entry.id]);
    await reload();
  }

  bool get hasUndo => _undoEntry != null;
  Future<void> undo() async {
    final entry = _undoEntry;
    if (entry == null || entry.id == null) return;
    _undoEntry = null;
    if (_undoWasDelete) {
      await _db!.insert('transactions', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await _db!.delete('transactions', where: 'id = ?', whereArgs: [entry.id]);
    }
    await reload();
  }

  Future<bool> addCategory(String name, int colorCode, String iconName) async {
    final label = name.trim();
    if (label.isEmpty || categories.any((c) => c.name.toLowerCase() == label.toLowerCase())) return false;
    await _db!.insert('categories', {'name': label, 'color_code': colorCode, 'icon_name': iconName});
    await reload();
    return true;
  }

  SpendCategory category(String name) {
    for (final cat in categories) {
      if (cat.name == name) return cat;
    }
    return defaultCategories.last;
  }

  String suggestCategory(String payee) {
    if (payee.trim().isEmpty) return 'Food';
    final key = payee.trim().toLowerCase();
    for (final e in entries) {
      if (e.payee.trim().toLowerCase() == key &&
          categories.any((c) => c.name == e.category)) return e.category;
    }
    return 'Food';
  }

  List<SpendEntry> on(DateTime date) => entries.where((e) => sameDay(e.at, date)).toList();
  int spentOn(DateTime date) => on(date).fold(0, (sum, e) => sum + e.paise);
  int get todaySpent => spentOn(DateTime.now());

  DailySnapshot snapshot(DateTime date) {
    final dayEntries = on(date);
    final spent = dayEntries.fold<int>(0, (v, e) => v + e.paise);
    final byCategory = <String, int>{};
    final byPayee = <String, int>{};
    var needed = 0;
    var impulse = 0;
    for (final e in dayEntries) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.paise;
      final payee = e.payee.isEmpty ? 'Unknown' : e.payee;
      byPayee[payee] = (byPayee[payee] ?? 0) + e.paise;
      if (e.tag == 'Impulse') { impulse += e.paise; } else { needed += e.paise; }
    }
    String highest(Map<String,int> m) {
      if (m.isEmpty) return '—';
      final sorted = m.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
      return sorted.first.key;
    }
    String insight;
    if (dayEntries.isEmpty) {
      insight = 'No expenses logged. Make it a mindful spending day.';
    } else if (spent > targetFor(date)) {
      insight = 'You went over target. Your biggest category was ' + highest(byCategory) + '.';
    } else if (impulse > spent ~/ 3) {
      insight = 'Impulse purchases made up more than a third of spending.';
    } else {
      insight = 'Within target! ' + highest(byCategory) + ' was your top category.';
    }
    return DailySnapshot(
      day: date, spent: spent, target: targetFor(date),
      entries: dayEntries, needed: needed, impulse: impulse,
      topPayee: highest(byPayee), topCategory: highest(byCategory),
      insight: insight,
    );
  }

  int get streak {
    if (entries.isEmpty) return 0;
    // Only completed days count. A day with no payment is a valid no-spend day.
    var total = 0;
    final earliest = dayStart(entries.last.at);
    var current = dayStart(DateTime.now()).subtract(const Duration(days: 1));
    while (!current.isBefore(earliest) && total < 365) {
      if (spentOn(current) > targetFor(current)) break;
      total++;
      current = current.subtract(const Duration(days: 1));
    }
    return total;
  }

  int get currentMonthSaved {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month);
    var total = 0;
    for (var day = first; !day.isAfter(dayStart(now)); day = day.add(const Duration(days: 1))) {
      total += targetFor(day) - spentOn(day);
    }
    return total;
  }

  Future<void> clearAll() async {
    await _db!.delete('transactions');
    _undoEntry = null;
    await reload();
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }
}
