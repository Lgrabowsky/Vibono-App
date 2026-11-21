import 'json.dart';

/// Prämienart: exklusiver Beitrag, eBook/PDF oder Rabatt auf die Verlängerung.
enum RewardKind { content, download, renewalDiscount }

RewardKind rewardKindFrom(String? s) => switch (s) {
      'download' => RewardKind.download,
      'renewal_discount' => RewardKind.renewalDiscount,
      _ => RewardKind.content,
    };

String rewardKindKey(RewardKind k) => switch (k) {
      RewardKind.content => 'content',
      RewardKind.download => 'download',
      RewardKind.renewalDiscount => 'renewal_discount',
    };

/// Eine Prämie aus `GET /rewards` (RewardItem im API-Vertrag).
class Reward {
  const Reward({
    required this.id,
    required this.kind,
    required this.title,
    this.description = '',
    required this.costPoints,
    this.imageUrl,
    this.redeemedCount = 0,
    this.unlocked = false,
    this.canRedeem = false,
    this.unavailableReason,
    this.postId,
    this.contentType,
    this.fileName,
    this.fileSizeBytes,
    this.discountLabel,
    this.validDays,
  });

  final int id;
  final RewardKind kind;
  final String title;
  final String description;
  final int costPoints;
  final String? imageUrl;
  final int redeemedCount;

  /// Inhalte und Dateien: schon freigeschaltet.
  final bool unlocked;
  final bool canRedeem;

  /// insufficient_points | already_unlocked | limit_reached | not_available_here | disabled
  final String? unavailableReason;

  /// Nur exklusive Inhalte: Beitrag und Art (recipe, tip, lesson).
  final int? postId;
  final String? contentType;

  /// Nur eBooks/PDFs.
  final String? fileName;
  final int? fileSizeBytes;

  /// Nur Verlängerungsrabatt, z. B. „10 € Rabatt“.
  final String? discountLabel;
  final int? validDays;

  factory Reward.fromJson(Json j) {
    final content = asMap(j['content']);
    final file = asMap(j['file']);
    final discount = asMap(j['discount']);
    return Reward(
      id: asInt(j['id']) ?? 0,
      kind: rewardKindFrom(asString(j['kind'])),
      title: asString(j['title']) ?? '',
      description: asString(j['description']) ?? '',
      costPoints: asInt(j['cost_points']) ?? 0,
      imageUrl: asString(j['image_url']),
      redeemedCount: asInt(j['redeemed_count']) ?? 0,
      unlocked: asBool(j['unlocked']),
      canRedeem: asBool(j['can_redeem']),
      unavailableReason: asString(j['unavailable_reason']),
      postId: asInt(content?['post_id']),
      contentType: asString(content?['type']),
      fileName: asString(file?['name']),
      fileSizeBytes: asInt(file?['size_bytes']),
      discountLabel: asString(discount?['label']),
      validDays: asInt(discount?['valid_days']),
    );
  }

  Json toJson() => {
        'id': id,
        'kind': rewardKindKey(kind),
        'title': title,
        'description': description,
        'cost_points': costPoints,
        'image_url': imageUrl,
        'redeemed_count': redeemedCount,
        'unlocked': unlocked,
        'can_redeem': canRedeem,
        'unavailable_reason': unavailableReason,
        'content': postId == null ? null : {'post_id': postId, 'type': contentType},
        'file': fileName == null ? null : {'name': fileName, 'size_bytes': fileSizeBytes},
        'discount': discountLabel == null ? null : {'label': discountLabel, 'valid_days': validDays},
      };
}

/// Persönlicher Gutschein aus der Prämie „Rabatt auf Verlängerung“.
class RewardCoupon {
  const RewardCoupon({required this.code, this.expiresAt, this.used = false, this.label = ''});
  final String code;
  final DateTime? expiresAt;
  final bool used;
  final String label;

  factory RewardCoupon.fromJson(Json j) => RewardCoupon(
        code: asString(j['code']) ?? '',
        expiresAt: DateTime.tryParse(asString(j['expires_at']) ?? ''),
        used: asBool(j['used']),
        label: asString(j['label']) ?? '',
      );
}

/// Eine eingelöste Prämie (RewardUnlock im API-Vertrag).
class RewardUnlock {
  const RewardUnlock({
    required this.id,
    required this.rewardId,
    required this.kind,
    required this.title,
    required this.points,
    required this.createdAt,
    this.postId,
    this.coupon,
  });

  final int id;
  final int rewardId;
  final RewardKind kind;
  final String title;
  final int points;
  final DateTime createdAt;
  final int? postId;
  final RewardCoupon? coupon;

  factory RewardUnlock.fromJson(Json j) => RewardUnlock(
        id: asInt(j['id']) ?? 0,
        rewardId: asInt(j['reward_id']) ?? 0,
        kind: rewardKindFrom(asString(j['kind'])),
        title: asString(j['title']) ?? '',
        points: asInt(j['points']) ?? 0,
        createdAt: DateTime.tryParse(asString(j['created_at']) ?? '') ?? DateTime.now(),
        postId: asInt(j['post_id']),
        coupon: asMap(j['coupon']) == null ? null : RewardCoupon.fromJson(asMap(j['coupon'])!),
      );
}

/// `GET /rewards`: Punktestand, Katalog und eigene Prämien.
class RewardCatalog {
  const RewardCatalog({required this.balance, required this.items, required this.unlocked});
  final int balance;
  final List<Reward> items;
  final List<RewardUnlock> unlocked;

  factory RewardCatalog.fromJson(Json j) => RewardCatalog(
        balance: asInt(j['balance']) ?? 0,
        items: asList(j['items'], Reward.fromJson),
        unlocked: asList(j['unlocked'], RewardUnlock.fromJson),
      );
}

/// `POST /rewards/{id}/redeem`.
class RewardRedeemResult {
  const RewardRedeemResult({required this.unlock, required this.balance});
  final RewardUnlock unlock;
  final int balance;

  factory RewardRedeemResult.fromJson(Json j) =>
      RewardRedeemResult(unlock: RewardUnlock.fromJson(asMap(j['unlock']) ?? const {}), balance: asInt(j['balance']) ?? 0);
}
