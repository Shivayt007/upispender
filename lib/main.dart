import 'package:flutter/material.dart';
import 'data.dart';
import 'notifications.dart';
import 'screens.dart';
import 'add_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UpiSpendApp());
}

class UpiSpendApp extends StatefulWidget {
  const UpiSpendApp({super.key});
  @override
  State<UpiSpendApp> createState() => _UpiSpendAppState();
}

class _UpiSpendAppState extends State<UpiSpendApp> {
  final SpendStore store = SpendStore();
  bool loaded = false;
  String? failed;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await store.init();
      await SpendNotifications.instance.init();
      await SpendNotifications.instance.scheduleReport(store);
      await SpendNotifications.instance.scheduleEveningReminder(store);
      if (mounted) setState(() => loaded = true);
    } catch (e) {
      if (mounted) setState(() => failed = e.toString());
    }
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final dark = store.flag('darkMode');
        return MaterialApp(
          title: 'UPI Spend Tracker',
          debugShowCheckedModeBanner: false,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: makeTheme(Brightness.light),
          darkTheme: makeTheme(Brightness.dark),
          home: !loaded
              ? Scaffold(
                  body: Center(
                    child: failed == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Unable to open local database: $failed'),
                          ),
                  ),
                )
              : AppShell(store: store),
        );
      },
    );
  }
}

ThemeData makeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const accent = Color(0xFF20B994);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    surface: dark ? const Color(0xFF111A20) : const Color(0xFFF6F8FA),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF213038) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF182329) : Colors.white,
      indicatorColor: const Color(0xFF20B994).withValues(alpha: .16),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      height: 76,
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});
  final SpendStore store;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  Future<void> openAdd() async {
    final before = widget.store.todaySpent;
    final saved = await showQuickAdd(context, widget.store);
    if (!mounted || !saved) return;
    await SpendNotifications.instance.spendingChanged(widget.store, before);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Expense saved on your device'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => widget.store.undo(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      HomeScreen(store: widget.store, onAdd: openAdd),
      ReportsScreen(store: widget.store),
      const SizedBox.shrink(),
      BudgetScreen(store: widget.store),
      SettingsScreen(store: widget.store),
    ];
    return Scaffold(
      body: SafeArea(child: content[index]),
      floatingActionButton: index == 0
          ? FloatingActionButton(
              onPressed: openAdd,
              backgroundColor: const Color(0xFF20B994),
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded, size: 32),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          if (value == 2) {
            openAdd();
          } else {
            setState(() => index = value);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline_rounded), selectedIcon: Icon(Icons.add_circle_rounded), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
