import 'json.dart';

enum Diet { alles, flexitarisch, vegetarisch, vegan }

enum ActivityLevel { sportmuffel, eingerostet, moderatAktiv, sehrAktiv }

const activityApi = {
  ActivityLevel.sportmuffel: 'sportmuffel',
  ActivityLevel.eingerostet: 'eingerostet',
  ActivityLevel.moderatAktiv: 'moderat_aktiv',
  ActivityLevel.sehrAktiv: 'sehr_aktiv',
};

const genderOptions = {
  'weiblich': 'Weiblich',
  'maennlich': 'Männlich',
  'divers': 'Divers',
  'keine_angabe': 'Keine Angabe',
};

const ageGroupOptions = {
  'u30': 'Unter 30',
  '30-39': '30 – 39',
  '40-49': '40 – 49',
  '50-59': '50 – 59',
  '60plus': '60 und älter',
};

const intoleranceOptions = {
  'laktose': 'Laktose',
  'gluten': 'Gluten',
  'nuesse': 'Nüsse',
  'fruktose': 'Fruktose',
  'histamin': 'Histamin',
  'ei': 'Ei',
  'soja': 'Soja',
  'fisch': 'Fisch',
};

const notificationTopics = {
  'aufgaben': 'Aufgaben',
  'rezepte': 'Rezepte',
  'motivation': 'Motivation',
  'bewegung': 'Bewegung',
  'wissen': 'Wissen',
};

/// Onboarding-Angaben + Ziele. Entspricht `Onboarding` + `Goals` im Vertrag.
class Profile {
  const Profile({
    this.completed = false,
    this.diet,
    this.meatAmount,
    this.intolerances = const [],
    this.dislikes = const [],
    this.activityLevel,
    this.gender,
    this.ageGroup,
    this.householdSize = 1,
    this.children = 0,
    this.notificationsPerDay = 5,
    this.notificationTopics = const ['aufgaben', 'rezepte', 'motivation'],
    this.quietStart = '21:00',
    this.quietEnd = '07:30',
    this.heightCm,
    this.startWeightKg,
    this.target3m,
    this.target6m,
    this.target12m,
    this.coachingStartDate,
  });

  final bool completed;
  final Diet? diet;

  /// viel | wenig | keins
  final String? meatAmount;
  final List<String> intolerances;
  final List<String> dislikes;
  final ActivityLevel? activityLevel;
  final String? gender;
  final String? ageGroup;
  final int householdSize;
  final int children;
  final int notificationsPerDay;
  final List<String> notificationTopics;
  final String quietStart;
  final String quietEnd;
  final double? heightCm;
  final double? startWeightKg;
  final double? target3m;
  final double? target6m;
  final double? target12m;
  final DateTime? coachingStartDate;

  Profile copyWith({
    bool? completed,
    Diet? diet,
    String? meatAmount,
    List<String>? intolerances,
    List<String>? dislikes,
    ActivityLevel? activityLevel,
    String? gender,
    String? ageGroup,
    int? householdSize,
    int? children,
    int? notificationsPerDay,
    List<String>? notificationTopics,
    String? quietStart,
    String? quietEnd,
    double? heightCm,
    double? startWeightKg,
    double? target3m,
    double? target6m,
    double? target12m,
    DateTime? coachingStartDate,
  }) =>
      Profile(
        completed: completed ?? this.completed,
        diet: diet ?? this.diet,
        meatAmount: meatAmount ?? this.meatAmount,
        intolerances: intolerances ?? this.intolerances,
        dislikes: dislikes ?? this.dislikes,
        activityLevel: activityLevel ?? this.activityLevel,
        gender: gender ?? this.gender,
        ageGroup: ageGroup ?? this.ageGroup,
        householdSize: householdSize ?? this.householdSize,
        children: children ?? this.children,
        notificationsPerDay: notificationsPerDay ?? this.notificationsPerDay,
        notificationTopics: notificationTopics ?? this.notificationTopics,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
        heightCm: heightCm ?? this.heightCm,
        startWeightKg: startWeightKg ?? this.startWeightKg,
        target3m: target3m ?? this.target3m,
        target6m: target6m ?? this.target6m,
        target12m: target12m ?? this.target12m,
        coachingStartDate: coachingStartDate ?? this.coachingStartDate,
      );

  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Body für `PUT /me/profile`.
  Json toApiJson() => {
        'onboarding': {
          'completed': completed,
          'nutrition': {
            if (diet != null) 'diet': diet!.name,
            if (meatAmount != null) 'meat_amount': meatAmount,
            'intolerances': intolerances,
            'dislikes': dislikes,
          },
          if (activityLevel != null) 'activity_level': activityApi[activityLevel],
          'social': {
            if (gender != null) 'gender': gender,
            if (ageGroup != null) 'age_group': ageGroup,
            'household_size': householdSize,
            'children': children,
          },
          'communication': {
            'notifications_per_day': notificationsPerDay,
            // Erweiterung, beim Backend-Thread angefragt:
            'topics': notificationTopics,
            'quiet_hours': {'start': quietStart, 'end': quietEnd},
          },
        },
        'goals': {
          'height_cm': heightCm,
          'start_weight_kg': startWeightKg,
          'target_weight_3m_kg': target3m,
          'target_weight_6m_kg': target6m,
          'target_weight_12m_kg': target12m,
          'coaching_start_date': _date(coachingStartDate),
        },
      };

  factory Profile.fromApiJson(Json me) {
    final o = asMap(me['onboarding']) ?? const {};
    final n = asMap(o['nutrition']) ?? const {};
    final s = asMap(o['social']) ?? const {};
    final c = asMap(o['communication']) ?? const {};
    final q = asMap(c['quiet_hours']) ?? const {};
    final g = asMap(me['goals']) ?? const {};
    final act = asString(o['activity_level']);
    return Profile(
      completed: asBool(o['completed']),
      diet: Diet.values.where((d) => d.name == asString(n['diet'])).firstOrNull,
      meatAmount: asString(n['meat_amount']),
      intolerances: asStringList(n['intolerances']),
      dislikes: asStringList(n['dislikes']),
      activityLevel: activityApi.entries.where((e) => e.value == act).firstOrNull?.key,
      gender: asString(s['gender']),
      ageGroup: asString(s['age_group']),
      householdSize: asInt(s['household_size']) ?? 1,
      children: asInt(s['children']) ?? 0,
      notificationsPerDay: asInt(c['notifications_per_day']) ?? 5,
      notificationTopics: c['topics'] is List ? asStringList(c['topics']) : const ['aufgaben', 'rezepte', 'motivation'],
      quietStart: asString(q['start']) ?? '21:00',
      quietEnd: asString(q['end']) ?? '07:30',
      heightCm: asDouble(g['height_cm']),
      startWeightKg: asDouble(g['start_weight_kg']),
      target3m: asDouble(g['target_weight_3m_kg']),
      target6m: asDouble(g['target_weight_6m_kg']),
      target12m: asDouble(g['target_weight_12m_kg']),
      coachingStartDate: DateTime.tryParse(asString(g['coaching_start_date']) ?? ''),
    );
  }
}

class Me {
  const Me({
    required this.id,
    required this.email,
    required this.firstName,
    required this.hasCoachingAccess,
    required this.profile,
    required this.pointsBalance,
    required this.referralCode,
    this.membershipName,
  });

  final int id;
  final String email;
  final String firstName;
  final bool hasCoachingAccess;
  final Profile profile;
  final int pointsBalance;
  final String referralCode;
  final String? membershipName;

  factory Me.fromJson(Json j) {
    final ms = j['memberships'];
    return Me(
      id: asInt(j['id']) ?? 0,
      email: asString(j['email']) ?? '',
      firstName: asString(j['first_name']) ?? asString(j['display_name']) ?? '',
      hasCoachingAccess: asBool(j['has_coaching_access']),
      profile: Profile.fromApiJson(j),
      pointsBalance: asInt(j['points_balance']) ?? 0,
      referralCode: asString(j['referral_code']) ?? '',
      membershipName: ms is List && ms.isNotEmpty && ms.first is Map ? asString((ms.first as Map)['name']) : null,
    );
  }
}
