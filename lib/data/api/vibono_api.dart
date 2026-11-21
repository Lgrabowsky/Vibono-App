import '../models/app_config.dart';
import '../models/coaching_day.dart';
import '../models/content.dart';
import '../models/energy.dart';
import '../models/home_feed.dart';
import '../models/json.dart';
import '../models/points.dart';
import '../models/profile.dart';
import '../models/sync_item.dart';

class SyncPull {
  const SyncPull({required this.cursor, required this.hasMore, required this.full, required this.changes});
  final String cursor;
  final bool hasMore;
  final bool full;
  final List<SyncItem> changes;
}

class SyncPushResult {
  const SyncPushResult({required this.cursor, required this.serverItems});
  final String? cursor;

  /// Bei `stale`: der neuere Stand vom Server.
  final List<SyncItem> serverItems;
}

/// Schnittstelle zum WordPress-Plugin `vibono-app-api`
/// (`/wp-json/vibono/v1`, Vertrag: docs/api/openapi.yaml).
abstract interface class VibonoApi {
  Future<RemoteConfig> config(String platform);

  Future<Me> login(String username, String password, {String? deviceName});
  Future<Me> register({required String email, required String password, String? firstName, String? referralCode});
  Future<void> logout();
  Future<void> requestPasswordReset(String email);
  bool get hasSession;

  Future<Me> me();
  Future<Me> updateProfile(Profile profile);
  Future<void> deleteAccount();
  Future<void> registerDevice(String token, String platform);

  Future<SyncPull> syncPull({String? cursor});
  Future<SyncPushResult> syncPush(List<Json> changes);

  Future<CoachingDay> coachingDay(DateTime date);

  /// Startseite „Heute“: Stichwörter, Quiz, Challenges, Meldungen.
  Future<HomeFeed> home(DateTime date, String platform);
  Future<List<ContentItem>> content(String type, {String? search, List<String>? tags, int? course, int page = 1});
  Future<List<Course>> courses();
  Future<ContentItem> contentItem(int id);

  Future<PointsSummary> points();
  Future<List<LedgerEntry>> ledger({int page = 1});
  Future<AwardResult> reportAppOpen();
  Future<ReadingSession> startReading(int postId);
  Future<ReadingProgress> readingHeartbeat(String sessionId, int activeSeconds, double scrollDepth);
  Future<AwardResult> completeReading(String sessionId, {int? quizAnswer});
  Future<ReferralInfo> referral();

  /// Einmal-Link für eingeloggten Browser auf vibono.de, nur wenn erlaubt.
  Future<Uri> webSession(String redirectPath);

  Future<List<Food>> foods(String query);
  Future<RecipeScanResult> scanRecipe(String imageBase64, String mime);
  Future<PhotoAnalysisResult> analyzePhoto(String imageBase64, String mime, {String? description});
}
