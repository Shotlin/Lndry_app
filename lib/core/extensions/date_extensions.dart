import 'package:intl/intl.dart';

/// DateTime extensions for the LNDRY app.
///
/// LNDRY only operates in India, so every date/time shown to a user must
/// read as IST (UTC+5:30) regardless of the device's own timezone —
/// `.toLocal()` isn't good enough, since a misconfigured or travelling
/// device would then silently show the wrong time (and, near midnight,
/// the wrong calendar date entirely).
extension DateTimeExt on DateTime {
  /// This instant's wall-clock fields shifted to IST, independent of this
  /// DateTime's own UTC/local flag or the device's timezone.
  DateTime get ist => toUtc().add(const Duration(hours: 5, minutes: 30));

  // ── Formatters (always IST) ────────────────────────────────────────────────

  /// "27 Jun 2026"
  String get toDateString => DateFormat('dd MMM yyyy').format(ist);

  /// "09:30 PM"
  String get toTimeString => DateFormat('hh:mm a').format(ist);

  /// "27 Jun 2026, 09:30 PM"
  String get toDateTimeString => DateFormat('dd MMM yyyy, hh:mm a').format(ist);

  /// "27 Jun"
  String get toDayMonth => DateFormat('dd MMM').format(ist);

  /// "June 2026"
  String get toMonthYear => DateFormat('MMMM yyyy').format(ist);

  /// "Sat, 27 Jun"
  String get toDayDate => DateFormat('EEE, dd MMM').format(ist);

  /// "Saturday"
  String get toFullDay => DateFormat('EEEE').format(ist);

  /// "Sat"
  String get toShortDay => DateFormat('EEE').format(ist);

  /// ISO 8601 UTC string
  String get toIso => toUtc().toIso8601String();

  // ── Relative time ─────────────────────────────────────────────────────────

  /// "Just now", "5 min ago", "2 hr ago", "Yesterday", "27 Jun 2026"
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return toDateString;
  }

  // ── Comparison helpers (IST calendar day) ─────────────────────────────────
  bool get isToday {
    final n = DateTime.now().ist;
    final s = ist;
    return s.year == n.year && s.month == n.month && s.day == n.day;
  }

  bool get isTomorrow {
    final t = DateTime.now().ist.add(const Duration(days: 1));
    final s = ist;
    return s.year == t.year && s.month == t.month && s.day == t.day;
  }

  bool get isYesterday {
    final y = DateTime.now().ist.subtract(const Duration(days: 1));
    final s = ist;
    return s.year == y.year && s.month == y.month && s.day == y.day;
  }

  bool get isFuture  => isAfter(DateTime.now());
  bool get isPast    => isBefore(DateTime.now());

  /// Whether two DateTimes fall on the same IST calendar day.
  bool isSameDay(DateTime other) {
    final a = ist;
    final b = other.ist;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ── Manipulation ──────────────────────────────────────────────────────────
  DateTime get startOfDay => DateTime(year, month, day, 0, 0, 0);
  DateTime get endOfDay   => DateTime(year, month, day, 23, 59, 59);
  DateTime get startOfMonth => DateTime(year, month, 1);
  DateTime get endOfMonth   => DateTime(year, month + 1, 0);
  DateTime get nextDay     => add(const Duration(days: 1));
  DateTime get prevDay     => subtract(const Duration(days: 1));
}

/// Nullable DateTime extensions
extension NullableDateTimeExt on DateTime? {
  String get orNa => this?.toDateString ?? 'N/A';
  bool   get isNullOrPast =>
      this == null || this!.isBefore(DateTime.now());
}
