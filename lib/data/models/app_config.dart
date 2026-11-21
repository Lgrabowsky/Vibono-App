import 'json.dart';

/// `GET /config`. Steuert u. a., ob die App auf den Shop verlinken darf und
/// welche Module auf vibono.de schon eingeschaltet sind (`features`).
class RemoteConfig {
  const RemoteConfig({
    this.featureReferral = false,
    this.featureShopPoints = false,
    this.featureWebReading = false,
    this.featurePurchasePoints = false,
    this.featureCoachingPoints = false,
    this.featureRewards = false,
    this.rewardKinds = const [],
    this.linkPhysicalProducts = false,
    this.linkMemberships = false,
    this.linkPointsRedemption = false,
    this.shopUrl,
    this.pointsEnabled = true,
    this.centsPerPoint = 1,
    this.minAppVersion = '1.0.0',
  });

  /// Freunde werben (Empfehlungscode, `GET /referral`).
  final bool featureReferral;

  /// Modul „Punkte im Shop“ auf vibono.de eingeschaltet (Reiter in Mein Konto).
  final bool featureShopPoints;

  /// Lesepunkte auch für Artikel, die auf der Website gelesen werden.
  final bool featureWebReading;

  /// Punkte für Einkäufe im Shop (seit 21.11.2026 standardmäßig aus).
  final bool featurePurchasePoints;

  /// Punkte für erledigte Lektionen und abgeschlossene Kurse.
  final bool featureCoachingPoints;

  /// Prämien: Punkte gegen exklusive Inhalte, eBooks/PDFs, Verlängerungsrabatt.
  final bool featureRewards;

  /// Prämienarten, die die App auf dieser Plattform einlösen darf
  /// (`content`, `download`, `renewal_discount`).
  final List<String> rewardKinds;

  final bool linkPhysicalProducts;
  final bool linkMemberships;
  final bool linkPointsRedemption;
  final String? shopUrl;
  final bool pointsEnabled;
  final double centsPerPoint;
  final String minAppVersion;

  /// Konservativer Standard, falls /config nicht erreichbar ist:
  /// keine Shop-Hinweise und keine noch nicht freigeschalteten Module.
  static const safeDefault = RemoteConfig();

  factory RemoteConfig.fromJson(Json j) {
    final s = asMap(j['shop_links']) ?? const {};
    final f = asMap(j['features']) ?? const {};
    final shopPoints = asBool(f['shop_points']);
    return RemoteConfig(
      featureReferral: asBool(f['referral']),
      featureShopPoints: shopPoints,
      featureWebReading: asBool(f['web_reading']),
      featurePurchasePoints: asBool(f['purchase_points']),
      featureCoachingPoints: asBool(f['coaching_points']),
      featureRewards: asBool(f['rewards']),
      rewardKinds: asStringList(f['reward_kinds']),
      linkPhysicalProducts: asBool(s['physical_products']),
      linkMemberships: asBool(s['memberships']),
      // Ohne Shop-Punkte gibt es auch nichts einzulösen.
      linkPointsRedemption: shopPoints && asBool(s['points_redemption']),
      shopUrl: asString(j['shop_url']),
      pointsEnabled: j['points_enabled'] == null ? true : asBool(j['points_enabled']),
      centsPerPoint: asDouble(j['cents_per_point']) ?? 1,
      minAppVersion: asString(j['min_app_version']) ?? '1.0.0',
    );
  }
}
