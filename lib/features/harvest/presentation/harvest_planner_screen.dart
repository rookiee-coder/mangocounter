import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/domain/scan_chat_context.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../history/application/history_controller.dart';
import '../../history/domain/scan_record.dart';
import '../../settings/application/settings_controller.dart';
import '../data/harvest_ai_forecast_service.dart';
import '../data/harvest_notification_service.dart';
import '../data/harvest_reminder_store.dart';
import '../domain/harvest_forecast.dart';
import '../domain/harvest_reminder.dart';

class HarvestPlannerScreen extends ConsumerStatefulWidget {
  const HarvestPlannerScreen({super.key});

  @override
  ConsumerState<HarvestPlannerScreen> createState() =>
      _HarvestPlannerScreenState();
}

class _HarvestPlannerScreenState extends ConsumerState<HarvestPlannerScreen> {
  late final HarvestReminderStore _store;
  Map<String, HarvestReminder> _reminders = {};
  bool _loaded = false;
  bool _isRefreshingAi = false;
  String? _forecastSignature;
  List<HarvestForecast>? _aiForecasts;
  late DateTime _calendarMonth;
  late DateTime _selectedCalendarDate;

  @override
  void initState() {
    super.initState();
    _store = HarvestReminderStore(ref.read(sharedPreferencesProvider));
    _reminders = _store.load();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month);
    _selectedCalendarDate = HarvestPredictor.dateOnly(now);
    _loaded = true;
  }

  void _changeCalendarMonth(int offset) {
    setState(() {
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + offset);
    });
  }

  void _selectCalendarDate(DateTime date) {
    setState(() => _selectedCalendarDate = HarvestPredictor.dateOnly(date));
  }

  void _askAiAboutTree(HarvestForecast forecast) {
    final scanContext = ScanChatContext(
      totalCount: forecast.totalFruit,
      ripeCount: forecast.ripeFruit,
      unripeCount: forecast.unripeFruit,
      overRipeCount: forecast.overRipeFruit,
    );
    final prediction = DateFormat.MMMd().format(forecast.recommendedHarvestDate);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          scanContext: scanContext,
          initialQuestion: '''
I need advice for ${forecast.treeLabel}. Its latest scan found ${forecast.totalFruit} mangoes: ${forecast.ripeFruit} ripe, ${forecast.unripeFruit} unripe, and ${forecast.overRipeFruit} overripe. The planned inspection/harvest date is $prediction. ${forecast.predictionReason ?? ''}
Give a concise field plan for this specific tree, including whether to harvest now, rescan, or protect the fruit.
''',
        ),
      ),
    );
  }

  Future<void> _setReminder(HarvestForecast forecast) async {
    final reminder = HarvestReminder(
      treeId: forecast.treeId,
      harvestDate: forecast.recommendedHarvestDate,
    );
    final scheduled = await HarvestNotificationService.instance.schedule(
      reminder,
      forecast,
    );
    if (!mounted) return;
    if (!scheduled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications are disabled. Enable them to set this reminder.'),
        ),
      );
      return;
    }
    setState(() => _reminders = {..._reminders, forecast.treeId: reminder});
    await _store.save(_reminders);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${forecast.treeLabel} will be reminded automatically on ${DateFormat.MMMd().format(forecast.recommendedHarvestDate)} at 8:00 AM.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshAiForecasts(
    List<HarvestForecast> localForecasts,
    List<ScanRecord> records,
    String signature,
  ) async {
    if (_forecastSignature == signature || _isRefreshingAi) return;
    setState(() {
      _forecastSignature = signature;
      _isRefreshingAi = true;
      _aiForecasts = null;
    });
    final predictions = await const HarvestAiForecastService().predictAll(
      localForecasts: localForecasts,
      scans: records,
      apiKey: ref.read(settingsProvider).geminiApiKey,
    );
    final forecasts = [
      for (final forecast in localForecasts)
        predictions[forecast.treeId] ?? forecast,
    ];
    if (!mounted) return;
    setState(() {
      _aiForecasts = forecasts;
      _isRefreshingAi = false;
    });
    await _syncEnabledReminders(forecasts);
  }

  Future<void> _syncEnabledReminders(List<HarvestForecast> forecasts) async {
    var updated = _reminders;
    for (final forecast in forecasts) {
      final previous = updated[forecast.treeId];
      if (previous == null || forecast.needsRescan) continue;
      if (DateUtils.isSameDay(
        previous.harvestDate,
        forecast.recommendedHarvestDate,
      )) {
        continue;
      }
      final reminder = HarvestReminder(
        treeId: forecast.treeId,
        harvestDate: forecast.recommendedHarvestDate,
      );
      await HarvestNotificationService.instance.schedule(reminder, forecast);
      updated = {...updated, forecast.treeId: reminder};
    }
    if (!mounted || identical(updated, _reminders)) return;
    setState(() => _reminders = updated);
    await _store.save(updated);
  }

  Future<void> _removeReminder(HarvestForecast forecast) async {
    final reminder = _reminders[forecast.treeId];
    if (reminder == null) return;
    await HarvestNotificationService.instance.cancel(reminder);
    if (!mounted) return;
    setState(() {
      _reminders = {..._reminders}..remove(forecast.treeId);
    });
    await _store.save(_reminders);
  }

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Harvest calendar')),
      body: scans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load scan history: $error')),
        data: (records) {
          final treeIds = records
              .map((record) => record.treeId)
              .whereType<String>()
              .toSet();
          final localForecasts = treeIds
              .map((treeId) => HarvestPredictor.forecastForTree(treeId, records))
              .whereType<HarvestForecast>()
              .toList()
            ..sort((a, b) => a.recommendedHarvestDate.compareTo(b.recommendedHarvestDate));
          final signatureParts = records
              .where((record) => record.treeId != null)
              .map((record) => '${record.treeId}:${record.id}:${record.createdAt}')
              .toList()
            ..sort();
          final signature = signatureParts.join('|');
          if (_forecastSignature != signature && !_isRefreshingAi) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _refreshAiForecasts(localForecasts, records, signature);
            });
          }
          final forecasts = _aiForecasts ?? localForecasts;
          return _HarvestPlannerBody(
            forecasts: forecasts,
            reminders: _reminders,
            onSetReminder: _setReminder,
            onRemoveReminder: _removeReminder,
            loaded: _loaded,
            isRefreshingAi: _isRefreshingAi,
            aiEnabled: ref.watch(settingsProvider).geminiApiKey.isNotEmpty,
            calendarMonth: _calendarMonth,
            selectedCalendarDate: _selectedCalendarDate,
            onPreviousMonth: () => _changeCalendarMonth(-1),
            onNextMonth: () => _changeCalendarMonth(1),
            onDateSelected: _selectCalendarDate,
            onAskAi: _askAiAboutTree,
          );
        },
      ),
    );
  }
}

class _HarvestPlannerBody extends StatelessWidget {
  final List<HarvestForecast> forecasts;
  final Map<String, HarvestReminder> reminders;
  final ValueChanged<HarvestForecast> onSetReminder;
  final ValueChanged<HarvestForecast> onRemoveReminder;
  final bool loaded;
  final bool isRefreshingAi;
  final bool aiEnabled;
  final DateTime calendarMonth;
  final DateTime selectedCalendarDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<HarvestForecast> onAskAi;

  const _HarvestPlannerBody({
    required this.forecasts,
    required this.reminders,
    required this.onSetReminder,
    required this.onRemoveReminder,
    required this.loaded,
    required this.isRefreshingAi,
    required this.aiEnabled,
    required this.calendarMonth,
    required this.selectedCalendarDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
    required this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final scheduled = forecasts
        .where((forecast) => !forecast.needsRescan)
        .toList(growable: false);
    final rescan = forecasts.where((forecast) => forecast.needsRescan).toList();
    final harvestNow = scheduled
        .where((forecast) => forecast.readiness == HarvestReadiness.harvestNow)
        .length;
    final plannedFruit = scheduled.fold<int>(
      0,
      (total, forecast) => total + forecast.totalFruit,
    );
    final nextForecast = scheduled.isEmpty
        ? null
        : (scheduled.toList()
              ..sort(
                (first, second) => first.recommendedHarvestDate.compareTo(
                  second.recommendedHarvestDate,
                ),
              ))
            .first;
    final selectedPlans = scheduled
        .where((forecast) => DateUtils.isSameDay(
              forecast.recommendedHarvestDate,
              selectedCalendarDate,
            ))
        .toList(growable: false);
    if (forecasts.isEmpty) {
      return const _EmptyPlanner();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('PER-TREE HARVEST PLAN', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        const Text(
          'Forecasts use the ripeness mix from each tree’s latest assigned scan. Confirm maturity in the orchard before picking.',
        ),
        const SizedBox(height: 18),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.botanicalGradient,
            borderRadius: AppShapes.leafCut,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withOpacity(.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.spa_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ORCHARD HARVEST BOARD',
                          style: TextStyle(
                            color: Color(0xFFB9E0C3),
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$plannedFruit mangoes across ${scheduled.length} planned trees',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (harvestNow > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE0B2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$harvestNow NOW',
                        style: const TextStyle(
                          color: Color(0xFF7A3900),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              if (nextForecast != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Divider(color: Color(0x4DFFFFFF), height: 1),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.event_available_rounded,
                      color: Color(0xFFFFD98A),
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NEXT PREDICTED HARVEST',
                            style: TextStyle(
                              color: Color(0xFFB9E0C3),
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${nextForecast.treeLabel} - ${DateFormat('EEE, MMM d').format(nextForecast.recommendedHarvestDate)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      nextForecast.readiness == HarvestReadiness.harvestNow
                          ? 'TODAY'
                          : 'IN ${nextForecast.recommendedHarvestDate.difference(DateUtils.dateOnly(DateTime.now())).inDays} DAYS',
                      style: const TextStyle(
                        color: Color(0xFFFFD98A),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (isRefreshingAi)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: aiEnabled
                  ? AppColors.surfaceContainerLow
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  aiEnabled
                      ? Icons.auto_awesome_rounded
                      : Icons.offline_bolt_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    aiEnabled
                        ? 'AI dates refresh automatically after every assigned tree scan.'
                        : 'Cloud AI is not configured. Add your Gemini key in Settings for automatic AI dates.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        _InteractiveMonthCalendar(
          forecasts: scheduled,
          month: calendarMonth,
          selectedDate: selectedCalendarDate,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onDateSelected: onDateSelected,
        ),
        const SizedBox(height: 20),
        if (scheduled.isNotEmpty) ...[
          Text(
            'Plans for ${DateFormat.MMMd().format(selectedCalendarDate)}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (selectedPlans.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('No tree is planned for harvest on this day.'),
            ),
          for (final forecast in selectedPlans)
            _ForecastCard(
              forecast: forecast,
              reminder: reminders[forecast.treeId],
              onSetReminder: () => onSetReminder(forecast),
              onRemoveReminder: () => onRemoveReminder(forecast),
              onAskAi: () => onAskAi(forecast),
            ),
        ],
        if (rescan.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Needs a fresh scan', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final forecast in rescan)
            _ForecastCard(
              forecast: forecast,
              reminder: null,
              onSetReminder: () {},
              onRemoveReminder: () {},
              onAskAi: () => onAskAi(forecast),
            ),
        ],
      ],
    );
  }
}

class _CalendarStrip extends StatelessWidget {
  final List<HarvestForecast> forecasts;
  final DateTime start;

  const _CalendarStrip({required this.forecasts, required this.start});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = start.add(Duration(days: index));
          final count = forecasts
              .where((forecast) => DateUtils.isSameDay(forecast.recommendedHarvestDate, date))
              .length;
          final selected = count > 0;
          final color = selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest;
          return Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(DateFormat.E().format(date), style: TextStyle(color: selected ? Colors.white : null)),
                const SizedBox(height: 4),
                Text('${date.day}', style: TextStyle(fontWeight: FontWeight.bold, color: selected ? Colors.white : null)),
                const SizedBox(height: 5),
                Text(
                  count == 0 ? '—' : '$count tree${count == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 10, color: selected ? Colors.white : null),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InteractiveMonthCalendar extends StatelessWidget {
  final List<HarvestForecast> forecasts;
  final DateTime month;
  final DateTime selectedDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  const _InteractiveMonthCalendar({
    required this.forecasts,
    required this.month,
    required this.selectedDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  });

  Color _markerColor(List<HarvestForecast> plans) {
    if (plans.any((plan) => plan.readiness == HarvestReadiness.harvestNow)) {
      return const Color(0xFFC96A1A);
    }
    if (plans.any((plan) => plan.readiness == HarvestReadiness.nearlyReady)) {
      return AppColors.ripeAmber;
    }
    return AppColors.unripeGreen;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final today = HarvestPredictor.dateOnly(DateTime.now());
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCF8),
        borderRadius: AppShapes.leafCut,
        border: Border.all(color: AppColors.outlineTint, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withOpacity(.08),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.botanicalGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(5),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: onPreviousMonth,
                    color: Colors.white,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'MANGO HARVEST WINDOW',
                          style: TextStyle(
                            color: Color(0xFFB9E0C3),
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .9,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.yMMMM().format(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: onNextMonth,
                    color: Colors.white,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final weekday in weekdays)
                  Expanded(
                    child: Text(
                      weekday,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppColors.mutedGraphite,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final day = index - firstWeekday + 1;
                if (day < 1 || day > daysInMonth) return const SizedBox();
                final date = DateTime(month.year, month.month, day);
                final plans = forecasts
                    .where((forecast) => DateUtils.isSameDay(
                          forecast.recommendedHarvestDate,
                          date,
                        ))
                    .toList(growable: false);
                final count = plans.length;
                final markerColor = _markerColor(plans);
                final selected = DateUtils.isSameDay(date, selectedDate);
                final isToday = DateUtils.isSameDay(date, today);
                return Semantics(
                  button: true,
                  label: '${DateFormat.yMMMMd().format(date)}, $count planned trees',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onDateSelected(date),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: count > 0
                            ? markerColor.withOpacity(selected ? .94 : .14)
                            : selected
                                ? primary.withOpacity(.10)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: isToday
                            ? Border.all(color: primary, width: 1.2)
                            : null,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              color: count > 0 && selected
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: selected || isToday
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                          if (count > 0)
                            Positioned(
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white.withOpacity(.92)
                                      : markerColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    color: selected ? markerColor : Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _CalendarLegend(
                  color: AppColors.unripeGreen,
                  label: 'Developing',
                ),
                _CalendarLegend(
                  color: AppColors.ripeAmber,
                  label: 'Near harvest',
                ),
                _CalendarLegend(
                  color: Color(0xFFC96A1A),
                  label: 'Harvest now',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Each marker shows the number of trees planned for that date.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _CalendarLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.mutedGraphite,
          ),
        ),
      ],
    );
  }
}

class _ForecastCard extends StatelessWidget {
  final HarvestForecast forecast;
  final HarvestReminder? reminder;
  final VoidCallback onSetReminder;
  final VoidCallback onRemoveReminder;
  final VoidCallback onAskAi;

  const _ForecastCard({
    required this.forecast,
    required this.reminder,
    required this.onSetReminder,
    required this.onRemoveReminder,
    required this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (forecast.readiness) {
      HarvestReadiness.harvestNow => Colors.red.shade700,
      HarvestReadiness.nearlyReady => Colors.orange.shade800,
      HarvestReadiness.developing => AppColors.primaryGreen,
      HarvestReadiness.rescanNeeded => Colors.blueGrey,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.park_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(forecast.treeLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
                Text(
                  forecast.needsRescan
                      ? 'RESCAN'
                  : DateFormat.MMMd().format(forecast.recommendedHarvestDate),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(forecast.summary),
            if (!forecast.needsRescan) ...[
              const SizedBox(height: 5),
              Text(
                forecast.isAiPrediction
                    ? 'Gemini forecast${forecast.confidence == null ? '' : ' · ${forecast.confidence!.round()}% evidence confidence'}'
                    : 'On-device ripeness estimate',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Latest scan: ${DateFormat.MMMd().format(forecast.scanDate)}  ·  ${forecast.totalFruit} detected  ·  ${forecast.ripeFruit} ripe  ·  ${forecast.unripeFruit} unripe',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!forecast.needsRescan) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onAskAi,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Ask AI about this tree'),
                  ),
                  reminder == null
                      ? TextButton.icon(
                          onPressed: onSetReminder,
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Enable automatic reminder'),
                        )
                      : TextButton.icon(
                          onPressed: onRemoveReminder,
                          icon: const Icon(Icons.notifications_off_outlined),
                          label: const Text('Remove reminder'),
                        ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyPlanner extends StatelessWidget {
  const _EmptyPlanner();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 48),
              SizedBox(height: 12),
              Text('No assigned-tree scans yet', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Select a tree in the orchard map before scanning. Its ripeness results will appear here as a harvest forecast.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
