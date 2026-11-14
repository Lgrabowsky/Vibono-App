import 'json.dart';

/// `GET /config`. Steuert u. a., ob die App auf den Shop verlinken darf.
class RemoteConfig {
  const RemoteConfig({
    this.linkPhysicalProducts = false,
    this.linkMemberships = false,
    this.linkPointsRedemption = false,
    this.shopUrl,
    this.pointsEnabled = true,
    this.centsPerPoint = 1,
    this.minAppVersion = '1.0.0',
  });

  final bool linkPhysicalProducts;
  final bool linkMemberships;
  final bool linkPointsRedemption;
  final String? shopUrl;
  final bool pointsEnabled;
  final double centsPerPoint;
  final String minAppVersion;

  /// Konservativer Standard, falls /config nicht erreichbar ist:
  /// keinerlei Shop-Hinweise in der App.
  static const safeDefault = RemoteConfig();

  factory RemoteConfig.fromJson(Json j) {
    final s = asMap(j['shop_links']) ?? const {};
    return RemoteConfig(
      linkPhysicalProducts: asBool(s['physical_products']),
      linkMemberships: asBool(s['memberships']),
      linkPointsRedemption: asBool(s['points_redemption']),
      shopUrl: asString(j['shop_url']),
      pointsEnabled: j['points_enabled'] == null ? true : asBool(j['points_enabled']),
      centsPerPoint: asDouble(j['cents_per_point']) ?? 1,
      minAppVersion: asString(j['min_app_version']) ?? '1.0.0',
    );
  }
}
