import 'dart:async';

import 'package:flutter/material.dart';

/// Formats the time left until an exam opens, exactly like the website's
/// `useCountdown` (`src/hooks/useCountdown.ts`):
///
///  * under a day  → `HH:MM:SS`
///  * a day or more → `{days}{dayLabel}HH:MM:SS`, where the web passes
///    `"يوم"` in Arabic (rendered `"3 يوم 05:04:03"`) and falls back to `"d"`
///    (rendered `"3d 05:04:03"`).
String formatExamCountdown(Duration remaining, {String? dayLabel}) {
  final total = remaining.inSeconds;
  if (total <= 0) return '00:00:00';

  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;

  String pad(int n) => n.toString().padLeft(2, '0');
  final clock = '${pad(hours)}:${pad(minutes)}:${pad(seconds)}';
  if (days <= 0) return clock;

  final suffix = dayLabel != null && dayLabel.isNotEmpty ? ' $dayLabel ' : 'd ';
  return '$days$suffix$clock';
}

/// The day label the website hands `useCountdown` for [locale].
String examCountdownDayLabel(Locale locale) =>
    locale.languageCode == 'ar' ? 'يوم' : 'd';

/// Live countdown to an exam's start time — the app's version of the web's
/// `ExamActionButton` in `NewestExams.tsx`.
///
/// While the start time is in the future it renders [countdownBuilder] (by
/// default an orange timer pill, matching the web). The moment the countdown
/// reaches zero it switches to [readyBuilder] — the Start button — and calls
/// [onReached] once so the host can refresh anything else that depends on the
/// exam being open (status badge, bucket).
///
/// Only this widget ticks: the one-second timer calls `setState` on its own
/// small subtree, never on the screen that hosts it, and is cancelled as soon
/// as it reaches zero or the widget is disposed.
class ExamCountdown extends StatefulWidget {
  const ExamCountdown({
    super.key,
    required this.startTime,
    required this.readyBuilder,
    this.countdownBuilder,
    this.onReached,
  });

  /// When the exam opens.
  final DateTime startTime;

  /// Shown once [startTime] has passed — normally the Start button.
  final WidgetBuilder readyBuilder;

  /// Shown while counting down; receives the formatted remaining time.
  /// Defaults to [ExamCountdownPill].
  final Widget Function(BuildContext context, String formatted)?
      countdownBuilder;

  /// Called once when the countdown reaches zero.
  final VoidCallback? onReached;

  @override
  State<ExamCountdown> createState() => _ExamCountdownState();
}

class _ExamCountdownState extends State<ExamCountdown> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _reached = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant ExamCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      _timer?.cancel();
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _computeRemaining() => widget.startTime.difference(DateTime.now());

  void _start() {
    _remaining = _computeRemaining();
    _reached = _remaining.inSeconds <= 0;
    if (_reached) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final remaining = _computeRemaining();
    if (remaining.inSeconds <= 0) {
      _timer?.cancel();
      _timer = null;
      setState(() {
        _remaining = Duration.zero;
        _reached = true;
      });
      widget.onReached?.call();
      return;
    }
    setState(() => _remaining = remaining);
  }

  @override
  Widget build(BuildContext context) {
    if (_reached) return widget.readyBuilder(context);

    final formatted = formatExamCountdown(
      _remaining,
      dayLabel: examCountdownDayLabel(Localizations.localeOf(context)),
    );
    final builder = widget.countdownBuilder;
    if (builder != null) return builder(context, formatted);
    return ExamCountdownPill(formatted: formatted);
  }
}

/// The website's upcoming-exam action: an orange pill with a timer icon and
/// the remaining time in tabular figures, taking the Start button's place.
class ExamCountdownPill extends StatelessWidget {
  const ExamCountdownPill({
    super.key,
    required this.formatted,
    this.height = 44,
    this.borderRadius = 12,
    this.fontSize = 14,
  });

  final String formatted;
  final double height;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 16,
            color: Color(0xFFEA580C),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              formatted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: const Color(0xFFC2410C),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
