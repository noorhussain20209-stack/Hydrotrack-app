import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const HydroTrackApp());
}

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(initSettings);
}

/// Global notifier so the whole app can react to dark mode toggling
/// without needing a full state-management package.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

class HydroTrackApp extends StatelessWidget {
  const HydroTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'HydroTrack',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int dailyGoalMl = 2000;
  int consumedMl = 0;
  int reminderIntervalMin = 60;
  bool remindersOn = false;
  final int glassSizeMl = 250;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final savedDate = prefs.getString('date') ?? '';
    final isDark = prefs.getBool('dark_mode') ?? false;
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    setState(() {
      dailyGoalMl = prefs.getInt('goal') ?? 2000;
      reminderIntervalMin = prefs.getInt('interval') ?? 60;
      remindersOn = prefs.getBool('reminders_on') ?? false;
      consumedMl = (savedDate == today) ? (prefs.getInt('consumed') ?? 0) : 0;
    });

    if (savedDate != today) {
      await prefs.setString('date', today);
      await prefs.setInt('consumed', 0);
      // Archive yesterday's total into history before resetting.
      if (savedDate.isNotEmpty) {
        final prevConsumed = prefs.getInt('consumed_prev') ?? 0;
        await prefs.setString('history_$savedDate', prevConsumed.toString());
      }
    }

    // Re-schedule reminders on load if they were left on.
    if (remindersOn) {
      await _scheduleReminder(silent: true);
    }
  }

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    await prefs.setString('date', today);
    await prefs.setInt('consumed', consumedMl);
    await prefs.setInt('consumed_prev', consumedMl);
    await prefs.setInt('goal', dailyGoalMl);
    await prefs.setInt('interval', reminderIntervalMin);
    await prefs.setBool('reminders_on', remindersOn);
    // Keep today's history entry updated live so stats reflect current progress.
    await prefs.setString('history_$today', consumedMl.toString());
  }

  void _addWater(int amount) {
    setState(() {
      consumedMl += amount;
      if (consumedMl < 0) consumedMl = 0;
    });
    _saveState();

    if (consumedMl >= dailyGoalMl && consumedMl - amount < dailyGoalMl) {
      _showGoalReachedSnackbar();
    }
  }

  void _showGoalReachedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Daily goal reached! Great job staying hydrated.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _scheduleReminder({bool silent = false}) async {
    final androidDetails = AndroidNotificationDetails(
      'water_channel',
      'Water Reminders',
      channelDescription: 'Reminds you to drink water',
      importance: Importance.high,
      priority: Priority.high,
    );
    final notificationDetails = NotificationDetails(android: androidDetails);

    await notificationsPlugin.cancelAll();
    await notificationsPlugin.periodicallyShowWithDuration(
      0,
      'Time to hydrate! 💧',
      'Drink a glass of water to stay on track today.',
      Duration(minutes: reminderIntervalMin),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );

    setState(() => remindersOn = true);
    _saveState();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reminders on — every $reminderIntervalMin min ✅')),
      );
    }
  }

  Future<void> _cancelReminders() async {
    await notificationsPlugin.cancelAll();
    setState(() => remindersOn = false);
    _saveState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminders turned off')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (consumedMl / dailyGoalMl).clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('HydroTrack'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Weekly stats',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 220,
                    width: 220,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 14,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$percent%',
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold)),
                      Text('$consumedMl / $dailyGoalMl ml'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _quickAddButton('+250ml', 250),
                  _quickAddButton('+500ml', 500),
                  _quickAddButton('+100ml', 100),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _addWater(-glassSizeMl),
                child: const Text('Undo last drink'),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: remindersOn ? null : () => _scheduleReminder(),
                    icon: const Icon(Icons.notifications_active),
                    label: Text(remindersOn
                        ? 'Reminders every ${reminderIntervalMin}m'
                        : 'Enable Reminders'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: remindersOn ? _cancelReminders : null,
                    icon: const Icon(Icons.notifications_off),
                    label: const Text('Off'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAddButton(String label, int amount) {
    return ElevatedButton(
      onPressed: () => _addWater(amount),
      style: ElevatedButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(20),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        int tempGoal = dailyGoalMl;
        int tempInterval = reminderIntervalMin;
        bool tempDark = themeModeNotifier.value == ThemeMode.dark;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Daily Goal (ml)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: tempGoal.toDouble(),
                    min: 1000,
                    max: 4000,
                    divisions: 30,
                    label: '$tempGoal ml',
                    onChanged: (val) {
                      setModalState(() => tempGoal = val.round());
                    },
                  ),
                  Text('$tempGoal ml'),
                  const SizedBox(height: 16),
                  const Text('Reminder interval',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: tempInterval.toDouble(),
                    min: 15,
                    max: 180,
                    divisions: 33,
                    label: '$tempInterval min',
                    onChanged: (val) {
                      setModalState(() => tempInterval = val.round());
                    },
                  ),
                  Text('Every $tempInterval minutes'),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dark mode'),
                    value: tempDark,
                    onChanged: (val) {
                      setModalState(() => tempDark = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        setState(() {
                          dailyGoalMl = tempGoal;
                          reminderIntervalMin = tempInterval;
                        });
                        themeModeNotifier.value =
                            tempDark ? ThemeMode.dark : ThemeMode.light;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('dark_mode', tempDark);
                        await _saveState();
                        // If reminders are already on, reschedule with new interval.
                        if (remindersOn) {
                          await _scheduleReminder(silent: true);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Simple bar-chart view of the last 7 days of water intake,
/// read straight out of SharedPreferences history entries.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<MapEntry<String, int>> _last7Days = [];
  int _goal = 2000;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _goal = prefs.getInt('goal') ?? 2000;
    final now = DateTime.now();
    final entries = <MapEntry<String, int>>[];

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      final value = int.tryParse(prefs.getString('history_$key') ?? '') ?? 0;
      final label = _shortWeekday(day.weekday);
      entries.add(MapEntry(label, value));
    }

    setState(() {
      _last7Days = entries;
      _loading = false;
    });
  }

  String _shortWeekday(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = _last7Days.isEmpty
        ? 1
        : _last7Days.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final chartMax = maxVal > _goal ? maxVal : _goal;

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Stats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Goal: $_goal ml/day',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _last7Days.map((entry) {
                        final heightFraction =
                            chartMax == 0 ? 0.0 : entry.value / chartMax;
                        final metGoal = entry.value >= _goal && _goal > 0;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${entry.value}',
                                style: const TextStyle(fontSize: 11)),
                            const SizedBox(height: 4),
                            Container(
                              width: 28,
                              height: 160 * heightFraction.clamp(0.0, 1.0),
                              decoration: BoxDecoration(
                                color: metGoal
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.primary,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(entry.key),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
