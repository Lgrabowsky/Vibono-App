import 'json.dart';

class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.reasons,
    required this.multiplier,
    required this.endsAt,
    required this.active,
  });

  final int id;
  final String name;
  final String description;

  /// earn | redeem
  final String kind;
  final List<String> reasons;
  final double multiplier;
  final DateTime? endsAt;
  final bool active;

  factory Campaign.fromJson(Json j) => Campaign(
        id: asInt(j['id']) ?? 0,
        name: asString(j['name']) ?? '',
        description: asString(j['description']) ?? '',
        kind: asString(j['kind']) ?? 'earn',
        reasons: asStringList(j['reasons']),
        multiplier: asDouble(j['multiplier']) ?? 1,
        endsAt: DateTime.tryParse(asString(j['ends_at']) ?? ''),
        active: asBool(j['active']),
      );
}

class PointsSummary {
  const PointsSummary({
    required this.balance,
    required this.pending,
    required this.centsPerPoint,
    required this.effectiveCentsPerPoint,
    required this.valueCents,
    required this.earnRules,
    required this.campaigns,
    this.streak = AppStreak.disabled,
  });

  final int balance;
  final int pending;
  final double centsPerPoint;
  final double effectiveCentsPerPoint;
  final int valueCents;
  final Map<String, int> earnRules;
  final List<Campaign> campaigns;
  final AppStreak streak;

  factory PointsSummary.fromJson(Json j) => PointsSummary(
        balance: asInt(j['balance']) ?? 0,
        pending: asInt(j['pending']) ?? 0,
        centsPerPoint: asDouble(j['cents_per_point']) ?? 1,
        effectiveCentsPerPoint: asDouble(j['effective_cents_per_point']) ?? asDouble(j['cents_per_point']) ?? 1,
        valueCents: asInt(j['value_cents']) ?? 0,
        earnRules: (asMap(j['earn_rules']) ?? const {}).map((k, v) => MapEntry(k, asInt(v) ?? 0)),
        campaigns: asList(j['campaigns'], Campaign.fromJson),
        streak: AppStreak.fromJson(asMap(j['streak'])),
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.points,
    required this.reason,
    required this.status,
    required this.label,
    required this.createdAt,
    this.multiplier = 1,
  });

  final int id;
  final int points;
  final String reason;
  final String status;
  final String label;
  final DateTime createdAt;
  final double multiplier;

  factory LedgerEntry.fromJson(Json j) => LedgerEntry(
        id: asInt(j['id']) ?? 0,
        points: asInt(j['points']) ?? 0,
        reason: asString(j['reason']) ?? '',
        status: asString(j['status']) ?? 'confirmed',
        label: asString(j['label']) ?? '',
        createdAt: DateTime.tryParse(asString(j['created_at']) ?? '') ?? DateTime.now(),
        multiplier: asDouble(j['multiplier']) ?? 1,
      );
}

class AwardResult {
  const AwardResult({
    required this.awardedPoints,
    required this.alreadyAwarded,
    required this.balance,
    this.multiplier = 1,
    this.streak,
  });
  final int awardedPoints;
  final bool alreadyAwarded;
  final int balance;
  final double multiplier;

  /// Nur beim täglichen Öffnen: neuer Stand der Serie.
  final AppStreak? streak;

  factory AwardResult.fromJson(Json j) => AwardResult(
        awardedPoints: asInt(j['awarded_points']) ?? 0,
        alreadyAwarded: asBool(j['already_awarded']),
        balance: asInt(j['balance']) ?? 0,
        multiplier: asDouble(j['multiplier']) ?? 1,
        streak: j.containsKey('streak') ? AppStreak.fromJson(asMap(j['streak'])) : null,
      );
}

class ReferralInfo {
  const ReferralInfo({
    required this.code,
    required this.link,
    required this.shareText,
    required this.invited,
    required this.converted,
    required this.pointsEarned,
    required this.pointsPerReferral,
    required this.friendBonusPoints,
  });

  final String code;
  final String link;
  final String shareText;
  final int invited;
  final int converted;
  final int pointsEarned;
  final int pointsPerReferral;
  final int friendBonusPoints;

  factory ReferralInfo.fromJson(Json j) => ReferralInfo(
        code: asString(j['code']) ?? '',
        link: asString(j['link']) ?? '',
        shareText: asString(j['share_text']) ?? '',
        invited: asInt(j['invited']) ?? 0,
        converted: asInt(j['converted']) ?? 0,
        pointsEarned: asInt(j['points_earned']) ?? 0,
        pointsPerReferral: asInt(j['points_per_referral']) ?? 0,
        friendBonusPoints: asInt(j['friend_bonus_points']) ?? 0,
      );
}

class ReadingSession {
  const ReadingSession({
    required this.sessionId,
    required this.postId,
    required this.minActiveSeconds,
    required this.minScrollDepth,
    required this.heartbeatIntervalSeconds,
    required this.points,
    this.quizQuestion,
    this.quizAnswers = const [],
  });

  final String sessionId;
  final int postId;
  final int minActiveSeconds;
  final double minScrollDepth;
  final int heartbeatIntervalSeconds;
  final int points;
  final String? quizQuestion;
  final List<String> quizAnswers;

  factory ReadingSession.fromJson(Json j) {
    final quiz = asMap(j['quiz']);
    return ReadingSession(
      sessionId: asString(j['session_id']) ?? '',
      postId: asInt(j['post_id']) ?? 0,
      minActiveSeconds: asInt(j['min_active_seconds']) ?? 30,
      minScrollDepth: asDouble(j['min_scroll_depth']) ?? 0.9,
      heartbeatIntervalSeconds: asInt(j['heartbeat_interval_seconds']) ?? 10,
      points: asInt(j['points']) ?? 0,
      quizQuestion: asString(quiz?['question']),
      quizAnswers: asStringList(quiz?['answers']),
    );
  }
}

class ReadingProgress {
  const ReadingProgress({required this.acceptedActiveSeconds, required this.scrollDepth, required this.readyToComplete});
  final int acceptedActiveSeconds;
  final double scrollDepth;
  final bool readyToComplete;

  factory ReadingProgress.fromJson(Json j) => ReadingProgress(
        acceptedActiveSeconds: asInt(j['accepted_active_seconds']) ?? 0,
        scrollDepth: asDouble(j['scroll_depth']) ?? 0,
        readyToComplete: asBool(j['ready_to_complete']),
      );
}

/// Eine Stufe der Serie: ab Tag [fromDay] in Folge gibt es [points] Punkte pro Tag.
class StreakLevel {
  const StreakLevel(this.fromDay, this.points);
  final int fromDay;
  final int points;

  factory StreakLevel.fromJson(Json j) => StreakLevel(asInt(j['from_day']) ?? 1, asInt(j['points']) ?? 0);
  Json toJson() => {'from_day': fromDay, 'points': points};
}

/// Serie (Streak) fürs tägliche Öffnen der App. Je mehr Tage in Folge, desto
/// mehr Punkte pro Tag. Stufen, Schutztage und das Verhalten beim Abreißen
/// stellt Vibono im Backend ein.
class AppStreak {
  const AppStreak({
    required this.enabled,
    this.days = 0,
    this.best = 0,
    this.openedToday = false,
    this.alive = false,
    this.todayDay = 1,
    this.todayPoints = 0,
    this.stage,
    this.nextStage,
    this.daysToNextStage = 0,
    this.levels = const [],
    this.gracePerMonth = 0,
    this.graceLeft = 0,
    this.onBreak = 'drop_level',
    this.event,
    this.bridgedDays = 0,
    this.previousDays = 0,
  });

  static const disabled = AppStreak(enabled: false);

  final bool enabled;

  /// Tage in Folge (inkl. heute, wenn heute geöffnet). 0 = keine laufende Serie.
  final int days;
  final int best;
  final bool openedToday;
  final bool alive;

  /// Der wievielte Tag heute zählt und wie viele Punkte er bringt (ohne Aktion).
  final int todayDay;
  final int todayPoints;
  final StreakLevel? stage;
  final StreakLevel? nextStage;
  final int daysToNextStage;
  final List<StreakLevel> levels;
  final int gracePerMonth;
  final int graceLeft;

  /// drop_level | reset
  final String onBreak;

  /// Nur nach dem Öffnen: first | continued | bridged | broken | same_day
  final String? event;
  final int bridgedDays;
  final int previousDays;

  int get stageIndex => stage == null ? 0 : levels.indexWhere((l) => l.fromDay == stage!.fromDay).clamp(0, levels.length);

  factory AppStreak.fromJson(Json? j) {
    if (j == null || !asBool(j['enabled'])) return disabled;
    final today = asMap(j['today']) ?? const {};
    final next = asMap(j['next_stage']);
    final stage = asMap(j['stage']);
    return AppStreak(
      enabled: true,
      days: asInt(j['days']) ?? 0,
      best: asInt(j['best']) ?? 0,
      openedToday: asBool(j['opened_today']),
      alive: asBool(j['alive']),
      todayDay: asInt(today['day']) ?? 1,
      todayPoints: asInt(today['points']) ?? 0,
      stage: stage == null ? null : StreakLevel.fromJson(stage),
      nextStage: next == null ? null : StreakLevel.fromJson(next),
      daysToNextStage: asInt(next?['days_left']) ?? 0,
      levels: asList(j['levels'], StreakLevel.fromJson),
      gracePerMonth: asInt(j['grace_per_month']) ?? 0,
      graceLeft: asInt(j['grace_left']) ?? 0,
      onBreak: asString(j['on_break']) ?? 'drop_level',
      event: asString(j['event']),
      bridgedDays: asInt(j['bridged_days']) ?? 0,
      previousDays: asInt(j['previous_days']) ?? 0,
    );
  }
}
