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
  });

  final int balance;
  final int pending;
  final double centsPerPoint;
  final double effectiveCentsPerPoint;
  final int valueCents;
  final Map<String, int> earnRules;
  final List<Campaign> campaigns;

  factory PointsSummary.fromJson(Json j) => PointsSummary(
        balance: asInt(j['balance']) ?? 0,
        pending: asInt(j['pending']) ?? 0,
        centsPerPoint: asDouble(j['cents_per_point']) ?? 1,
        effectiveCentsPerPoint: asDouble(j['effective_cents_per_point']) ?? asDouble(j['cents_per_point']) ?? 1,
        valueCents: asInt(j['value_cents']) ?? 0,
        earnRules: (asMap(j['earn_rules']) ?? const {}).map((k, v) => MapEntry(k, asInt(v) ?? 0)),
        campaigns: asList(j['campaigns'], Campaign.fromJson),
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
  const AwardResult({required this.awardedPoints, required this.alreadyAwarded, required this.balance, this.multiplier = 1});
  final int awardedPoints;
  final bool alreadyAwarded;
  final int balance;
  final double multiplier;

  factory AwardResult.fromJson(Json j) => AwardResult(
        awardedPoints: asInt(j['awarded_points']) ?? 0,
        alreadyAwarded: asBool(j['already_awarded']),
        balance: asInt(j['balance']) ?? 0,
        multiplier: asDouble(j['multiplier']) ?? 1,
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
