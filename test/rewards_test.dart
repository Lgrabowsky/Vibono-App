import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibono/data/api/api_exception.dart';
import 'package:vibono/data/api/mock_vibono_api.dart';
import 'package:vibono/data/local/local_store.dart';
import 'package:vibono/data/models/app_config.dart';
import 'package:vibono/data/models/content.dart';
import 'package:vibono/data/models/rewards.dart';
import 'package:vibono/data/models/sync_item.dart';
import 'package:vibono/data/sync/sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Modelle', () {
    test('GET /config: Prämien und erlaubte Arten', () {
      final c = RemoteConfig.fromJson({
        'shop_links': {'physical_products': true, 'points_redemption': true},
        'features': {
          'shop_points': true,
          'purchase_points': false,
          'coaching_points': true,
          'rewards': true,
          'reward_kinds': ['content', 'download'],
        },
      });
      expect(c.featureRewards, isTrue);
      expect(c.rewardKinds, ['content', 'download']);
      expect(c.featurePurchasePoints, isFalse);
      expect(c.featureCoachingPoints, isTrue);
    });

    test('Katalog mit allen drei Prämienarten', () {
      final cat = RewardCatalog.fromJson({
        'balance': 640,
        'items': [
          {'id': 1, 'kind': 'content', 'title': 'Rezept', 'cost_points': 300, 'can_redeem': true, 'content': {'post_id': 81, 'type': 'recipe'}},
          {'id': 3, 'kind': 'download', 'title': 'eBook', 'cost_points': 500, 'unavailable_reason': 'insufficient_points', 'file': {'name': 'buch.pdf', 'size_bytes': 1200000}},
          {'id': 4, 'kind': 'renewal_discount', 'title': '10 €', 'cost_points': 1000, 'discount': {'label': '10 € Rabatt', 'valid_days': 90}},
        ],
        'unlocked': [
          {'id': 9, 'reward_id': 4, 'kind': 'renewal_discount', 'title': '10 €', 'points': 1000, 'created_at': '2026-11-21T10:00:00Z', 'coupon': {'code': 'VP-ABCD-EFGH', 'used': false, 'label': '10 € Rabatt'}},
        ],
      });
      expect(cat.items.map((r) => r.kind), [RewardKind.content, RewardKind.download, RewardKind.renewalDiscount]);
      expect(cat.items[0].postId, 81);
      expect(cat.items[0].contentType, 'recipe');
      expect(cat.items[1].canRedeem, isFalse);
      expect(cat.items[1].fileName, 'buch.pdf');
      expect(cat.items[2].discountLabel, '10 € Rabatt');
      expect(cat.unlocked.single.coupon!.code, 'VP-ABCD-EFGH');
    });

    test('Exklusiver Beitrag in der Inhaltsliste', () {
      final i = ContentItem.fromJson({
        'id': 81,
        'type': 'recipe',
        'title': 'Exklusiv',
        'locked': true,
        'exclusive': true,
        'reward': {'id': 1, 'cost_points': 300, 'unlocked': false},
      });
      expect(i.exclusive && i.locked, isTrue);
      expect(i.rewardId, 1);
      expect(i.rewardCost, 300);
      expect(ContentItem.fromJson(i.toJson()).rewardCost, 300);
    });
  });

  group('Demo-Schnittstelle', () {
    late LocalStore store;
    late MockVibonoApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await LocalStore.open();
      api = MockVibonoApi(store, latency: Duration.zero);
      await api.login('test@example.com', 'geheim');
    });

    test('In der App kein Verlängerungsrabatt, auf der Website schon', () async {
      expect((await api.rewards('android')).items.map((r) => r.kind), isNot(contains(RewardKind.renewalDiscount)));
      expect((await api.rewards('web')).items.map((r) => r.kind), contains(RewardKind.renewalDiscount));
    });

    test('Exklusives Rezept: gesperrt, freischalten kostet Punkte, danach lesbar', () async {
      final recipes = await api.content('recipes');
      final ex = recipes.firstWhere((r) => r.exclusive);
      expect(ex.locked, isTrue);
      expect(ex.ingredients, isEmpty);
      await expectLater(
        api.contentItem(ex.id),
        throwsA(isA<ApiException>().having((e) => e.isRewardRequired, 'isRewardRequired', isTrue)),
      );

      // Demo-Konto hat 240 Punkte: Rezept (300) geht noch nicht, Tipp (200) schon.
      final cat = await api.rewards('ios');
      final rezept = cat.items.firstWhere((r) => r.postId == ex.id);
      expect(rezept.canRedeem, isFalse);
      expect(rezept.unavailableReason, 'insufficient_points');
      await expectLater(api.redeemReward(rezept.id, 'ios'), throwsA(isA<ApiException>()));

      final tipp = cat.items.firstWhere((r) => r.kind == RewardKind.content && r.contentType == 'tip');
      final res = await api.redeemReward(tipp.id, 'ios');
      expect(res.balance, cat.balance - tipp.costPoints);
      expect((await api.contentItem(tipp.postId!)).contentHtml, isNotNull);
      final again = (await api.rewards('ios')).items.firstWhere((r) => r.id == tipp.id);
      expect(again.unlocked, isTrue);
      expect(again.canRedeem, isFalse);
    });

    test('Lektion erledigt bringt einmal 10 Punkte', () async {
      final repo = SyncRepository(api, store)..load();
      await repo.sync();
      final before = (await api.points()).balance;
      await repo.upsert(SyncCollection.lessonsDone, '375530', {'post_id': 375530});
      await repo.sync();
      expect((await api.points()).balance, before + 10);
      await repo.remove(SyncCollection.lessonsDone, '375530');
      await repo.sync();
      await repo.upsert(SyncCollection.lessonsDone, '375530', {'post_id': 375530});
      await repo.sync();
      expect((await api.points()).balance, before + 10, reason: 'Häkchen neu setzen bringt nichts');
      expect((await api.points()).earnRules.keys, containsAll(['lesson_done', 'course_done']));
      expect((await api.points()).earnRules.keys, isNot(contains('purchase')));
    });
  });
}
