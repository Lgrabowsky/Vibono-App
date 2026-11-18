import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/api/api_exception.dart';
import '../data/api/vibono_api.dart';
import '../data/local/local_store.dart';
import '../data/models/app_config.dart';
import '../data/models/coaching_day.dart';
import '../data/models/content.dart';
import '../data/models/json.dart';
import '../data/models/points.dart';
import '../data/models/profile.dart';
import '../data/sync/sync_repository.dart';
import '../domain/coaching_plan.dart';

/// Werden in `main()` mit echten Instanzen überschrieben.
final storeProvider = Provider<LocalStore>((ref) => throw UnimplementedError('storeProvider'));
final apiProvider = Provider<VibonoApi>((ref) => throw UnimplementedError('apiProvider'));
final syncProvider = ChangeNotifierProvider<SyncRepository>((ref) => throw UnimplementedError('syncProvider'));

String get platformName => kIsWeb
    ? 'web'
    : switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => 'web',
      };

/// Feature-Flags vom Server. Ohne Verbindung gilt der sichere Standard
/// (keine Shop-Hinweise).
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  try {
    return await ref.watch(apiProvider).config(platformName);
  } catch (_) {
    return RemoteConfig.safeDefault;
  }
});

// ---------------------------------------------------------------------------
// Sitzung
// ---------------------------------------------------------------------------

/// Nach dem Login geht es sofort in die App. Das Onboarding ist freiwillig
/// und startet über eine Kachel auf der Startseite.
enum SessionStatus { loading, loggedOut, ready }

class SessionState {
  const SessionState(this.status, [this.me]);
  final SessionStatus status;
  final Me? me;
  Profile get profile => me?.profile ?? const Profile();
}

class SessionNotifier extends Notifier<SessionState> {
  static const _kMe = 'u.me';
  static const _kPendingProfile = 'u.profile.pending';

  VibonoApi get _api => ref.read(apiProvider);
  LocalStore get _store => ref.read(storeProvider);

  @override
  SessionState build() {
    Future.microtask(_restore);
    return const SessionState(SessionStatus.loading);
  }

  SessionState _stateFor(Me me) => SessionState(SessionStatus.ready, me);

  Future<void> _restore() async {
    if (!_api.hasSession) {
      state = const SessionState(SessionStatus.loggedOut);
      return;
    }
    final cached = asMap(_store.readJson(_kMe));
    if (cached != null) state = _stateFor(Me.fromJson(cached));
    try {
      await _flushPendingProfile();
      final me = await _api.me();
      await _remember(me);
      state = _stateFor(me);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        state = const SessionState(SessionStatus.loggedOut);
      } else if (cached == null) {
        state = const SessionState(SessionStatus.loggedOut);
      }
    }
    unawaited(ref.read(syncProvider).sync());
  }

  Future<void> _remember(Me me) async {
    final raw = <String, dynamic>{
      'id': me.id,
      'email': me.email,
      'first_name': me.firstName,
      'has_coaching_access': me.hasCoachingAccess,
      'points_balance': me.pointsBalance,
      'referral_code': me.referralCode,
      if (me.membershipName != null) 'memberships': [
        {'name': me.membershipName},
      ],
      ...me.profile.toApiJson(),
    };
    await _store.writeJson(_kMe, raw);
  }

  Future<void> login(String username, String password) async {
    final me = await _api.login(username.trim(), password, deviceName: 'Vibono-App ($platformName)');
    await _remember(me);
    state = _stateFor(me);
    unawaited(ref.read(syncProvider).sync());
  }

  Future<void> register(String email, String password, String firstName, String? referralCode) async {
    final me = await _api.register(
      email: email.trim(),
      password: password,
      firstName: firstName.trim().isEmpty ? null : firstName.trim(),
      referralCode: referralCode == null || referralCode.trim().isEmpty ? null : referralCode.trim(),
    );
    await _remember(me);
    state = _stateFor(me);
  }

  /// Speichert Angaben; ohne Netz wird später nachgereicht.
  Future<void> saveProfile(Profile profile) async {
    final current = state.me;
    try {
      final me = await _api.updateProfile(profile);
      await _store.writeJson(_kPendingProfile, null);
      await _remember(me);
      state = _stateFor(me);
    } on ApiException catch (e) {
      if (!e.isOffline || current == null) rethrow;
      await _store.writeJson(_kPendingProfile, profile.toApiJson());
      final me = Me(
        id: current.id,
        email: current.email,
        firstName: current.firstName,
        hasCoachingAccess: current.hasCoachingAccess,
        profile: profile,
        pointsBalance: current.pointsBalance,
        referralCode: current.referralCode,
        membershipName: current.membershipName,
      );
      await _remember(me);
      state = _stateFor(me);
    }
  }

  Future<void> _flushPendingProfile() async {
    final p = asMap(_store.readJson(_kPendingProfile));
    if (p == null) return;
    await _api.updateProfile(Profile.fromApiJson(p));
    await _store.writeJson(_kPendingProfile, null);
  }

  Future<void> refreshMe() async {
    try {
      final me = await _api.me();
      await _remember(me);
      state = _stateFor(me);
    } catch (_) {}
  }

  Future<void> logout() async {
    await _api.logout();
    await _store.clearUserData();
    await ref.read(syncProvider).reset();
    state = const SessionState(SessionStatus.loggedOut);
  }

  Future<void> deleteAccount() async {
    await _api.deleteAccount();
    await logout();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

// ---------------------------------------------------------------------------
// Tag & Inhalte
// ---------------------------------------------------------------------------

class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() => CoachingPlan.dateOnly(DateTime.now());

  void previous() => state = state.subtract(const Duration(days: 1));
  void next() => state = state.add(const Duration(days: 1));
  void today() => state = CoachingPlan.dateOnly(DateTime.now());
}

final selectedDateProvider = NotifierProvider<SelectedDate, DateTime>(SelectedDate.new);

final coachingDayProvider = FutureProvider.family<CoachingDay, DateTime>((ref, date) async {
  // Bei geänderten Angaben (Startdatum, Ernährung) neu laden.
  ref.watch(sessionProvider.select((s) => s.me?.profile));
  return ref.watch(apiProvider).coachingDay(date);
});

final recipesProvider = FutureProvider<List<ContentItem>>((ref) => ref.watch(apiProvider).content('recipes'));
final tipsProvider = FutureProvider<List<ContentItem>>((ref) => ref.watch(apiProvider).content('tips'));
final coursesProvider = FutureProvider<List<Course>>((ref) => ref.watch(apiProvider).courses());
final contentItemProvider =
    FutureProvider.family<ContentItem, int>((ref, id) => ref.watch(apiProvider).contentItem(id));

// ---------------------------------------------------------------------------
// Punkte
// ---------------------------------------------------------------------------

/// Aktueller Punktestand, wird nach jeder Gutschrift sofort aktualisiert.
class PointsBalance extends Notifier<int?> {
  @override
  int? build() => ref.watch(sessionProvider.select((s) => s.me?.pointsBalance));

  void set(int balance) => state = balance;
}

final pointsBalanceProvider = NotifierProvider<PointsBalance, int?>(PointsBalance.new);

/// Serie fürs tägliche Öffnen, wie sie die letzte Antwort auf „App geöffnet“
/// geliefert hat. `null`, bis die App sich heute gemeldet hat; dann gilt der
/// Stand aus „Heute“ bzw. „Punkte“.
class AppStreakState extends Notifier<AppStreak?> {
  @override
  AppStreak? build() {
    ref.watch(sessionProvider.select((s) => s.me?.id));
    return null;
  }

  void set(AppStreak? streak) => state = streak;
}

final appStreakProvider = NotifierProvider<AppStreakState, AppStreak?>(AppStreakState.new);
final pointsProvider = FutureProvider<PointsSummary>((ref) => ref.watch(apiProvider).points());
final ledgerProvider = FutureProvider<List<LedgerEntry>>((ref) => ref.watch(apiProvider).ledger());
/// `null`, solange „Freunde werben“ auf vibono.de ausgeschaltet ist.
final referralProvider = FutureProvider<ReferralInfo?>((ref) async {
  final config = await ref.watch(remoteConfigProvider.future);
  if (!config.featureReferral) return null;
  try {
    return await ref.watch(apiProvider).referral();
  } on ApiException catch (e) {
    if (e.isFeatureDisabled) return null;
    rethrow;
  }
});
