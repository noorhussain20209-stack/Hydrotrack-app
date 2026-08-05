import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

/// Plays a soft system click sound plus a light haptic buzz â€” used on
/// every interactive tap in the app for a more premium, responsive feel.
void _tapFeedback() {
  SystemSound.play(SystemSoundType.click);
  HapticFeedback.lightImpact();
}

/// Hydration multiplier for different drink types â€” coffee/tea/alcohol
/// count for less than their raw volume due to mild diuretic effect;
/// water and juice count fully.
const Map<String, double> kDrinkHydrationFactor = {
  'Water': 1.0,
  'Tea': 0.9,
  'Coffee': 0.8,
  'Juice': 0.9,
  'Milk': 1.0,
};

const Map<String, String> kDrinkEmoji = {
  'Water': 'ðŸ’§',
  'Tea': 'ðŸµ',
  'Coffee': 'â˜•',
  'Juice': 'ðŸ§ƒ',
  'Milk': 'ðŸ¥›',
};

/// Metadata for each unlockable achievement badge.
const Map<String, Map<String, String>> kBadgeInfo = {
  'first_drink': {'title': 'First Sip', 'emoji': 'ðŸ’§', 'desc': 'Logged your first drink'},
  'goal_hit': {'title': 'Goal Crusher', 'emoji': 'ðŸŽ¯', 'desc': 'Hit your daily goal'},
  'streak_3': {'title': '3-Day Streak', 'emoji': 'ðŸ”¥', 'desc': '3 days in a row'},
  'streak_7': {'title': 'Week Warrior', 'emoji': 'â­', 'desc': '7 days in a row'},
  'streak_30': {'title': 'Hydration Hero', 'emoji': 'ðŸ‘‘', 'desc': '30 days in a row'},
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  _initTimezone();
  runApp(const HydroTrackApp());
}

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(initSettings);
}

void _initTimezone() {
  tzdata.initializeTimeZones();
  final offset = DateTime.now().timeZoneOffset;
  tz.setLocalLocation(
    tz.Location(
      'device_local',
      [0],
      [offset.inSeconds],
      [offset.inSeconds],
      const [],
    ),
  );
}

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
            colorSchemeSeed: const Color(0xFF2979FF),
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF2979FF),
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          home: const LaunchDecider(),
        );
      },
    );
  }
}

/// Decides whether to show onboarding (first launch) or go straight home.
class LaunchDecider extends StatefulWidget {
  const LaunchDecider({super.key});

  @override
  State<LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<LaunchDecider> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('dark_mode') ?? false;
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    setState(() {
      _onboardingDone = prefs.getBool('onboarding_done') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _onboardingDone! ? const HomeScreen() : const OnboardingScreen();
  }
}

// ============================================================
// ONBOARDING: gender + weight -> personalized daily goal
// ============================================================
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  String? _gender; // 'male', 'female', 'other'
  double _weightKg = 65;
  double _age = 25;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Simple, commonly-used estimate: ~35 ml per kg for men, ~31 ml per kg
  /// for women, ~33 ml per kg as a neutral default. Not medical advice â€”
  /// just a friendlier starting point than a flat 2000 ml for everyone.
  int _calculateGoal() {
    double mlPerKg;
    switch (_gender) {
      case 'male':
        mlPerKg = 35;
        break;
      case 'female':
        mlPerKg = 31;
        break;
      default:
        mlPerKg = 33;
    }
    // Metabolic water needs taper slightly at the age extremes.
    if (_age < 18) {
      mlPerKg -= 2;
    } else if (_age > 55) {
      mlPerKg -= 3;
    }
    final goal = (_weightKg * mlPerKg).round();
    // Round to nearest 50 ml for a cleaner number.
    return (goal / 50).round() * 50;
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final goal = _calculateGoal();
    await prefs.setBool('onboarding_done', true);
    await prefs.setString('gender', _gender ?? 'other');
    await prefs.setDouble('weight_kg', _weightKg);
    await prefs.setDouble('age', _age);
    await prefs.setInt('goal', goal);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _gender != null;
    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _animController,
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const _WaterDropLogo(size: 90),
                const SizedBox(height: 24),
                Text(
                  'Let\'s personalize\nyour goal',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 36),
                Text('I am...', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _GenderCard(
                      label: 'Male',
                      icon: Icons.male_rounded,
                      selected: _gender == 'male',
                      onTap: () => setState(() => _gender = 'male'),
                    ),
                    const SizedBox(width: 12),
                    _GenderCard(
                      label: 'Female',
                      icon: Icons.female_rounded,
                      selected: _gender == 'female',
                      onTap: () => setState(() => _gender = 'female'),
                    ),
                    const SizedBox(width: 12),
                    _GenderCard(
                      label: 'Other',
                      icon: Icons.person_rounded,
                      selected: _gender == 'other',
                      onTap: () => setState(() => _gender = 'other'),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text('Your weight', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '${_weightKg.round()} kg',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: _weightKg,
                  min: 30,
                  max: 150,
                  divisions: 120,
                  label: '${_weightKg.round()} kg',
                  onChanged: (v) => setState(() => _weightKg = v),
                ),
                const SizedBox(height: 20),
                Text('Your age', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '${_age.round()} yrs',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: _age,
                  min: 10,
                  max: 90,
                  divisions: 80,
                  label: '${_age.round()} yrs',
                  onChanged: (v) => setState(() => _age = v),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.water_drop_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          canContinue
                              ? 'Your suggested goal: ${_calculateGoal()} ml/day'
                              : 'Pick an option above to see your goal',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canContinue ? _finishOnboarding : null,
                    child: const Text('Get Started', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GenderCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : null,
            border: Border.all(
              color: selected ? color : Colors.grey.withOpacity(0.3),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? color : Colors.grey, size: 30),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color: selected ? color : Colors.grey,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaterDropLogo extends StatelessWidget {
  final double size;
  const _WaterDropLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DropPainter(Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _DropPainter extends CustomPainter {
  final Color color;
  _DropPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.quadraticBezierTo(0, size.height * 0.55, size.width / 2, size.height);
    path.quadraticBezierTo(size.width, size.height * 0.55, size.width / 2, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
// HOME SCREEN
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int dailyGoalMl = 2000;
  int consumedMl = 0;
  int reminderIntervalMin = 60;
  bool remindersOn = false;
  TimeOfDay quietStart = const TimeOfDay(hour: 22, minute: 0); // 10 PM
  TimeOfDay quietEnd = const TimeOfDay(hour: 7, minute: 0); // 7 AM
  final int glassSizeMl = 250;

  late AnimationController _celebrateController;
  bool _showCelebration = false;
  int _streakDays = 0;
  int _longestStreak = 0;
  String _selectedDrink = 'Water';
  DateTime? _lastLogTime;
  List<String> _unlockedBadges = [];
  String? _justUnlockedBadge;

  @override
  void initState() {
    super.initState();
    _celebrateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _loadState();
  }

  @override
  void dispose() {
    _celebrateController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final savedDate = prefs.getString('date') ?? '';

    setState(() {
      dailyGoalMl = prefs.getInt('goal') ?? 2000;
      reminderIntervalMin = prefs.getInt('interval') ?? 60;
      remindersOn = prefs.getBool('reminders_on') ?? false;
      quietStart = _decodeTime(prefs.getString('quiet_start'), const TimeOfDay(hour: 22, minute: 0));
      quietEnd = _decodeTime(prefs.getString('quiet_end'), const TimeOfDay(hour: 7, minute: 0));
      consumedMl = (savedDate == today) ? (prefs.getInt('consumed') ?? 0) : 0;
      _longestStreak = prefs.getInt('longest_streak') ?? 0;
      _unlockedBadges = prefs.getStringList('badges') ?? [];
    });

    if (savedDate != today) {
      await prefs.setString('date', today);
      await prefs.setInt('consumed', 0);
    }

    if (remindersOn) {
      await _scheduleReminders(silent: true);
    }

    await _computeStreak(prefs);
  }

  /// Counts consecutive days (ending today) where the logged intake met
  /// the daily goal, for a simple motivational streak badge.
  Future<void> _computeStreak(SharedPreferences prefs) async {
    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final day = now.subtract(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      final value = int.tryParse(prefs.getString('history_$key') ?? '') ?? 0;
      final goalForCheck = dailyGoalMl;
      if (i == 0) {
        // Today only counts once the goal has actually been hit so far.
        if (value >= goalForCheck && goalForCheck > 0) {
          streak++;
        } else {
          break;
        }
      } else {
        if (value >= goalForCheck && goalForCheck > 0) {
          streak++;
        } else {
          break;
        }
      }
    }
    if (mounted) setState(() => _streakDays = streak);
    if (streak > _longestStreak) {
      _longestStreak = streak;
      await prefs.setInt('longest_streak', _longestStreak);
    }
  }

  TimeOfDay _decodeTime(String? raw, TimeOfDay fallback) {
    if (raw == null) return fallback;
    final parts = raw.split(':');
    if (parts.length != 2) return fallback;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _encodeTime(TimeOfDay t) => '${t.hour}:${t.minute}';

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    await prefs.setString('date', today);
    await prefs.setInt('consumed', consumedMl);
    await prefs.setInt('goal', dailyGoalMl);
    await prefs.setInt('interval', reminderIntervalMin);
    await prefs.setBool('reminders_on', remindersOn);
    await prefs.setString('quiet_start', _encodeTime(quietStart));
    await prefs.setString('quiet_end', _encodeTime(quietEnd));
    await prefs.setString('history_$today', consumedMl.toString());
  }

  void _addWater(int amount, {String? drinkType}) {
    _tapFeedback();
    final effectiveDrink = drinkType ?? _selectedDrink;
    final factor = kDrinkHydrationFactor[effectiveDrink] ?? 1.0;
    final effectiveAmount = (amount * factor).round();
    final wasBelowGoal = consumedMl < dailyGoalMl;

    setState(() {
      consumedMl += effectiveAmount;
      if (consumedMl < 0) consumedMl = 0;
      _lastLogTime = DateTime.now();
    });
    _saveState();
    _checkBadges();

    // Adaptive reminders: if a reminder is due to fire in the next 10
    // minutes, skip that single occurrence since the user just drank.
    _skipImminentReminder();

    if (wasBelowGoal && consumedMl >= dailyGoalMl) {
      _celebrate();
    }
  }

  /// Cancels only the single next scheduled reminder if it would fire
  /// within 10 minutes of a drink just being logged, then re-schedules
  /// the rest normally. This avoids nagging right after the user drank.
  Future<void> _skipImminentReminder() async {
    if (!remindersOn) return;
    final pending = await notificationsPlugin.pendingNotificationRequests();
    if (pending.isEmpty) return;
    // We can't inspect exact fire time from the plugin's pending list
    // directly, so as a practical approximation we simply push the whole
    // schedule out by rebuilding it â€” new slots start after "now + gap".
    await _scheduleReminders(silent: true, adaptiveSkipMinutes: 10);
  }

  Future<void> _checkBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final newBadges = <String>[];

    if (!_unlockedBadges.contains('first_drink')) {
      newBadges.add('first_drink');
    }
    if (_streakDays >= 3 && !_unlockedBadges.contains('streak_3')) {
      newBadges.add('streak_3');
    }
    if (_streakDays >= 7 && !_unlockedBadges.contains('streak_7')) {
      newBadges.add('streak_7');
    }
    if (_streakDays >= 30 && !_unlockedBadges.contains('streak_30')) {
      newBadges.add('streak_30');
    }
    if (consumedMl >= dailyGoalMl && !_unlockedBadges.contains('goal_hit')) {
      newBadges.add('goal_hit');
    }

    if (newBadges.isNotEmpty) {
      setState(() {
        _unlockedBadges = [..._unlockedBadges, ...newBadges];
        _justUnlockedBadge = newBadges.first;
      });
      await prefs.setStringList('badges', _unlockedBadges);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _justUnlockedBadge = null);
      });
    }
  }

  void _celebrate() async {
    final prefs = await SharedPreferences.getInstance();
    await _computeStreak(prefs);
    setState(() => _showCelebration = true);
    _celebrateController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showCelebration = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ðŸŽ‰ Daily goal reached! Great job staying hydrated.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Builds a list of reminder times for a single day that fall strictly
  /// *outside* the quiet-hours window, spaced by [reminderIntervalMin].
  List<TimeOfDay> _wakingSlotsForDay() {
    final slots = <TimeOfDay>[];
    final startMinutes = quietEnd.hour * 60 + quietEnd.minute;
    var endMinutes = quietStart.hour * 60 + quietStart.minute;
    if (endMinutes <= startMinutes) endMinutes += 24 * 60; // wraps past midnight
    for (int m = startMinutes; m < endMinutes; m += reminderIntervalMin) {
      final normalized = m % (24 * 60);
      slots.add(TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60));
    }
    return slots;
  }

  Future<void> _scheduleReminders({bool silent = false, int adaptiveSkipMinutes = 0}) async {
    await notificationsPlugin.cancelAll();

    final androidDetails = AndroidNotificationDetails(
      'water_channel',
      'Water Reminders',
      channelDescription: 'Reminds you to drink water',
      importance: Importance.high,
      priority: Priority.high,
    );
    final notificationDetails = NotificationDetails(android: androidDetails);

    final slots = _wakingSlotsForDay();
    int notifId = 0;
    final now = tz.TZDateTime.now(tz.local);
    final earliestAllowed = now.add(Duration(minutes: adaptiveSkipMinutes));

    // Schedule across the next 14 days so reminders keep firing even if the
    // app isn't reopened daily.
    for (int dayOffset = 0; dayOffset < 14; dayOffset++) {
      for (final slot in slots) {
        var scheduled = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day + dayOffset,
          slot.hour,
          slot.minute,
        );
        if (scheduled.isBefore(earliestAllowed)) continue;

        await notificationsPlugin.zonedSchedule(
          notifId++,
          'Time to hydrate! ðŸ’§',
          'Drink a glass of water to stay on track today.',
          scheduled,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }

    setState(() => remindersOn = true);
    _saveState();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminders on â€” every ${reminderIntervalMin}m, quiet from '
            '${quietStart.format(context)} to ${quietEnd.format(context)} âœ…',
          ),
        ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('HydroTrack'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_rounded),
            tooltip: 'Achievements',
            onPressed: () {
              _tapFeedback();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BadgesScreen(
                    unlocked: _unlockedBadges,
                    longestStreak: _longestStreak,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'History calendar',
            onPressed: () {
              _tapFeedback();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CalendarHeatmapScreen(goal: dailyGoalMl),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Weekly stats',
            onPressed: () {
              _tapFeedback();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              _tapFeedback();
              _openSettings();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_streakDays > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('ðŸ”¥', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(
                            '$_streakDays day${_streakDays == 1 ? '' : 's'} streak',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Colors.deepOrange),
                          ),
                        ],
                      ),
                    ),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      WaterWaveRing(
                        progress: progress,
                        size: 220,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 4,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(progress * 100).round()}%',
                              style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black26)
                                  ],
                                  color: Colors.white)),
                          Text('$consumedMl / $dailyGoalMl ml',
                              style: const TextStyle(
                                  shadows: [Shadow(blurRadius: 6, color: Colors.black26)],
                                  color: Colors.white)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Drink type selector chips
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: kDrinkHydrationFactor.keys.map((drink) {
                        final selected = _selectedDrink == drink;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${kDrinkEmoji[drink]} $drink'),
                            selected: selected,
                            onSelected: (_) {
                              _tapFeedback();
                              setState(() => _selectedDrink = drink);
                            },
                          ),
                        );
                      }).toList(),
                    ),
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
                    onPressed: () {
                      _tapFeedback();
                      _addWater(-glassSizeMl);
                    },
                    child: const Text('Undo last drink'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: remindersOn
                            ? null
                            : () {
                                _tapFeedback();
                                _scheduleReminders();
                              },
                        icon: const Icon(Icons.notifications_active_rounded),
                        label: Text(remindersOn
                            ? 'Reminders every ${reminderIntervalMin}m'
                            : 'Enable Reminders'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: remindersOn
                            ? () {
                                _tapFeedback();
                                _cancelReminders();
                              }
                            : null,
                        icon: const Icon(Icons.notifications_off_rounded),
                        label: const Text('Off'),
                      ),
                    ],
                  ),
                  if (remindersOn) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Quiet ${quietStart.format(context)} â€“ ${quietEnd.format(context)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_showCelebration)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _celebrateController,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size.infinite,
                    painter: _ConfettiPainter(_celebrateController.value),
                  );
                },
              ),
            ),
          if (_justUnlockedBadge != null)
            Positioned(
              top: 16,
              left: 24,
              right: 24,
              child: AnimatedOpacity(
                opacity: _justUnlockedBadge != null ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.amber.shade600,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    child: Row(
                      children: [
                        const Text('ðŸ†', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Achievement unlocked: ${kBadgeInfo[_justUnlockedBadge]?['title'] ?? ''}',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickAddButton(String label, int amount) {
    return _BouncyButton(
      onTap: () => _addWater(amount),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withOpacity(0.7),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
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
        TimeOfDay tempQuietStart = quietStart;
        TimeOfDay tempQuietEnd = quietEnd;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
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
                      onChanged: (val) => setModalState(() => tempGoal = val.round()),
                    ),
                    Text('$tempGoal ml'),
                    const SizedBox(height: 12),
                    const Text('Reminder interval',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Slider(
                      value: tempInterval.toDouble(),
                      min: 15,
                      max: 180,
                      divisions: 33,
                      label: '$tempInterval min',
                      onChanged: (val) => setModalState(() => tempInterval = val.round()),
                    ),
                    Text('Every $tempInterval minutes'),
                    const SizedBox(height: 12),
                    const Text('Quiet hours (no reminders)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: tempQuietStart);
                              if (picked != null) {
                                setModalState(() => tempQuietStart = picked);
                              }
                            },
                            child: Text('Start: ${tempQuietStart.format(context)}'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: tempQuietEnd);
                              if (picked != null) {
                                setModalState(() => tempQuietEnd = picked);
                              }
                            },
                            child: Text('End: ${tempQuietEnd.format(context)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dark mode'),
                      value: tempDark,
                      onChanged: (val) => setModalState(() => tempDark = val),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            dailyGoalMl = tempGoal;
                            reminderIntervalMin = tempInterval;
                            quietStart = tempQuietStart;
                            quietEnd = tempQuietEnd;
                          });
                          themeModeNotifier.value =
                              tempDark ? ThemeMode.dark : ThemeMode.light;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('dark_mode', tempDark);
                          await _saveState();
                          if (remindersOn) {
                            await _scheduleReminders(silent: true);
                          }
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Small helper that gives buttons a satisfying press-down scale animation.
class _BouncyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BouncyButton({required this.child, required this.onTap});

  @override
  State<_BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<_BouncyButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// Lightweight confetti burst drawn with CustomPainter (no extra package).
class _ConfettiPainter extends CustomPainter {
  final double progress;
  final _rand = Random(7);
  _ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      Colors.blue,
      Colors.lightBlueAccent,
      Colors.cyan,
      Colors.amber,
      Colors.pinkAccent,
    ];
    final center = Offset(size.width / 2, size.height * 0.35);
    for (int i = 0; i < 40; i++) {
      final angle = (i / 40) * 2 * pi;
      final speed = 150 + _rand.nextDouble() * 200;
      final dx = cos(angle) * speed * progress;
      final dy = sin(angle) * speed * progress + (progress * progress * 300);
      final paint = Paint()..color = colors[i % colors.length].withOpacity(1 - progress);
      canvas.drawCircle(center + Offset(dx, dy), 5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

/// Animated circular "liquid fill" indicator â€” draws a wavy water surface
/// that rises to match progress and gently animates side to side.
class WaterWaveRing extends StatefulWidget {
  final double progress; // 0..1
  final double size;
  final Color color;
  const WaterWaveRing({
    super.key,
    required this.progress,
    required this.size,
    required this.color,
  });

  @override
  State<WaterWaveRing> createState() => _WaterWaveRingState();
}

class _WaterWaveRingState extends State<WaterWaveRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, _) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return ClipOval(
              child: Container(
                width: widget.size,
                height: widget.size,
                color: widget.color.withOpacity(0.08),
                child: CustomPaint(
                  painter: _WavePainter(
                    progress: animatedProgress,
                    wavePhase: _controller.value * 2 * pi,
                    color: widget.color,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final double wavePhase;
  final Color color;
  _WavePainter({required this.progress, required this.wavePhase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final waterLevel = size.height * (1 - progress);
    final path = Path();
    const waveHeight = 8.0;
    const waveLength = 60.0;

    path.moveTo(0, waterLevel);
    for (double x = 0; x <= size.width; x++) {
      final y = waterLevel +
          sin((x / waveLength * 2 * pi) + wavePhase) * waveHeight;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    final paint = Paint()..color = color.withOpacity(0.85);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => true;
}


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
      entries.add(MapEntry(_shortWeekday(day.weekday), value));
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
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: heightFraction.clamp(0.0, 1.0)),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedHeight, _) {
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${entry.value}',
                                    style: const TextStyle(fontSize: 11)),
                                const SizedBox(height: 4),
                                Container(
                                  width: 28,
                                  height: 160 * animatedHeight,
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
                          },
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

// ============================================================
// ACHIEVEMENTS / BADGES SCREEN
// ============================================================
class BadgesScreen extends StatelessWidget {
  final List<String> unlocked;
  final int longestStreak;
  const BadgesScreen({super.key, required this.unlocked, required this.longestStreak});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text('ðŸ…', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Text('Longest streak: $longestStreak days',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...kBadgeInfo.entries.map((entry) {
            final isUnlocked = unlocked.contains(entry.key);
            final info = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? Colors.amber.withOpacity(0.15)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: isUnlocked
                    ? Border.all(color: Colors.amber, width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  Opacity(
                    opacity: isUnlocked ? 1 : 0.3,
                    child: Text(info['emoji']!, style: const TextStyle(fontSize: 32)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info['title']!,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isUnlocked ? null : Colors.grey)),
                        Text(info['desc']!,
                            style: TextStyle(
                                fontSize: 12,
                                color: isUnlocked ? Colors.grey.shade700 : Colors.grey)),
                      ],
                    ),
                  ),
                  if (isUnlocked) const Icon(Icons.check_circle, color: Colors.amber),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ============================================================
// CALENDAR HEATMAP SCREEN
// ============================================================
class CalendarHeatmapScreen extends StatefulWidget {
  final int goal;
  const CalendarHeatmapScreen({super.key, required this.goal});

  @override
  State<CalendarHeatmapScreen> createState() => _CalendarHeatmapScreenState();
}

class _CalendarHeatmapScreenState extends State<CalendarHeatmapScreen> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, int> _history = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('history_'));
    final map = <String, int>{};
    for (final k in keys) {
      final dateStr = k.replaceFirst('history_', '');
      final value = int.tryParse(prefs.getString(k) ?? '') ?? 0;
      map[dateStr] = value;
    }
    setState(() {
      _history = map;
      _loading = false;
    });
  }

  Color _colorForRatio(double ratio) {
    if (ratio <= 0) return Colors.grey.withOpacity(0.15);
    if (ratio < 0.5) return Colors.blue.withOpacity(0.3);
    if (ratio < 1.0) return Colors.blue.withOpacity(0.6);
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final leadingEmpty = firstDay.weekday % 7; // 0 = Sunday alignment

    return Scaffold(
      appBar: AppBar(title: const Text('History Calendar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() {
                          _visibleMonth =
                              DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                        }),
                      ),
                      Text(
                        '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() {
                          _visibleMonth =
                              DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: leadingEmpty + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < leadingEmpty) return const SizedBox();
                      final day = index - leadingEmpty + 1;
                      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
                      final key = date.toIso8601String().substring(0, 10);
                      final value = _history[key] ?? 0;
                      final ratio = widget.goal > 0 ? value / widget.goal : 0.0;
                      final isFuture = date.isAfter(DateTime.now());
                      return Container(
                        decoration: BoxDecoration(
                          color: isFuture
                              ? Colors.transparent
                              : _colorForRatio(ratio.toDouble()),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        alignment: Alignment.center,
                        child: Text('$day',
                            style: TextStyle(
                                fontSize: 12,
                                color: ratio >= 0.5 && !isFuture
                                    ? Colors.white
                                    : Colors.grey.shade700)),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendDot(Colors.grey.withOpacity(0.15), 'None'),
                      _legendDot(Colors.blue.withOpacity(0.3), '<50%'),
                      _legendDot(Colors.blue.withOpacity(0.6), '<100%'),
                      _legendDot(Colors.green, 'Goal met'),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[month - 1];
  }
}
             
