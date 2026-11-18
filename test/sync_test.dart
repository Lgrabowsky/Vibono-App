import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibono/data/api/mock_vibono_api.dart';
import 'package:vibono/data/local/local_store.dart';
import 'package:vibono/data/models/sync_item.dart';
import 'package:vibono/data/sync/sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late MockVibonoApi api;
  late SyncRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    api = MockVibonoApi(store, latency: Duration.zero);
    await api.login('test@example.com', 'geheim');
    repo = SyncRepository(api, store)..load();
  });

  test('erster Abgleich holt vorhandene MyVibono-Daten', () async {
    await repo.sync();
    expect(repo.has(SyncCollection.favorites, 'recipe:9002'), isTrue);
    expect(repo.items(SyncCollection.weight), isNotEmpty);
  });

  test('lokale Änderung landet auf dem Server und übersteht einen Neustart', () async {
    await repo.sync();
    await repo.upsert(SyncCollection.lessonsDone, '375528', {'post_id': 375528});
    await repo.sync();
    expect(repo.pendingChanges, 0);

    final fresh = SyncRepository(api, store)..load();
    expect(fresh.has(SyncCollection.lessonsDone, '375528'), isTrue);

    // Ein zweites Gerät (leerer Speicher, gleicher Server) sieht die Änderung.
    SharedPreferences.setMockInitialValues({
      for (final k in ['mock.server', 'mock.session', 'mock.me']) k: (await SharedPreferences.getInstance()).get(k)!,
    });
    final other = await LocalStore.open();
    final repo2 = SyncRepository(MockVibonoApi(other, latency: Duration.zero), other)..load();
    await repo2.sync();
    expect(repo2.has(SyncCollection.lessonsDone, '375528'), isTrue);
  });

  test('Löschen wird übertragen', () async {
    await repo.sync();
    await repo.remove(SyncCollection.favorites, 'recipe:9002');
    await repo.sync();
    final pull = await api.syncPull();
    final item = pull.changes.firstWhere((c) => c.key == 'recipe:9002');
    expect(item.deleted, isTrue);
  });

  test('Lese-Nachweis: ohne Lesezeit keine Punkte', () async {
    final s = await api.startReading(375528);
    await api.readingHeartbeat(s.sessionId, 999, 1.0); // Server deckelt per Wanduhr
    expect(() => api.completeReading(s.sessionId), throwsA(anything));
  });

  test('tägliche Öffnung gibt nur einmal Punkte', () async {
    final a = await api.reportAppOpen();
    final b = await api.reportAppOpen();
    expect(a.awardedPoints, 5);
    expect(b.awardedPoints, 0);
    expect(b.alreadyAwarded, isTrue);
  });
}
