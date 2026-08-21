import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/settings_store.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_description.dart';

/// M4 팝업 개편. **앱을 통째로 띄워** 실제 배선으로 연다 —
/// 팝업만 따로 만들어 검사하면 `_openRegion` 이 넘기는 값이 바뀌어도 통과한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData realMap;
  setUpAll(() async => realMap = await MapData.load());

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3.0;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// 경주시(첨성대 랜드마크)를 미리 수집해 둔 저장 파일.
  String savedWith({String? memo}) => encodeCollection(
        CollectionSnapshot.empty.collect(CollectedUnit(
          scratchUnitId: '47130',
          collectedAtUtc: DateTime.parse('2026-08-14T15:30:00Z'),
          utcOffsetMinutes: 540, // 한국 → 현지로는 8월 15일
          memo: memo,
        )),
      );

  Future<void> openApp(WidgetTester tester, String? saved) async {
    await tester.pumpWidget(MapScratchApp(
      settingsOpener: _testSettings,
      mapLoader: () async => realMap,
      storeOpener: () async {
        final store = CollectionStore(_MemStorage(saved));
        return (store, await store.load());
      },
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  /// 검색으로 지역을 골라 팝업을 연다. 탭 좌표를 계산하지 않아도 된다.
  Future<void> openRegion(WidgetTester tester, String name) async {
    await tester.tap(find.text('지역 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, name).first);
    await tester.pumpAndSettle();
  }

  group('미수집', () {
    testWidgets('랜드마크 이름도 설명도 내보내지 않는다', (tester) async {
      // **"가리고 긁을 때 공개" 결정의 핵심이다.** 이름 한 단어도 힌트가 된다.
      await openApp(tester, null);
      await openRegion(tester, '경주시');

      expect(find.text('지역 긁기'), findsOneWidget);
      expect(find.textContaining('첨성대'), findsNothing,
          reason: '미수집인데 랜드마크 이름이 새어 나왔다');
      expect(find.text(kLandmarkDescription['47130']!), findsNothing,
          reason: '미수집인데 설명이 새어 나왔다');
    });

    testWidgets('그래도 시도 진행률은 보여준다', (tester) async {
      // 193번 반복되는 고정 문구만 두면 다음 목표가 보이지 않는다.
      await openApp(tester, null);
      await openRegion(tester, '경주시');

      expect(find.textContaining('경상북도'), findsWidgets);
      expect(find.textContaining('남았어요'), findsOneWidget);
    });
  });

  group('수집 후', () {
    testWidgets('설명·수집일·진행률을 함께 보여준다', (tester) async {
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');

      expect(find.text(kLandmarkDescription['47130']!), findsOneWidget);
      // **수집 당시 오프셋으로 푼 날짜다.** UTC 로는 8월 14일이지만
      // 한국에서 수집했으므로 8월 15일이어야 한다.
      expect(find.textContaining('2026년 8월 15일'), findsOneWidget);
      expect(find.textContaining('남았어요'), findsOneWidget);
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('메모가 있으면 보여준다', (tester) async {
      // 입력은 M5 지만, M4 는 이미 있는 메모를 보여줄 수 있어야 한다.
      await openApp(tester, savedWith(memo: '비 오는 날의 첨성대'));
      await openRegion(tester, '경주시');

      expect(find.byKey(const Key('regionMemo')), findsOneWidget);
      expect(find.text('비 오는 날의 첨성대'), findsOneWidget);
    });

    testWidgets('메모가 없으면 빈 자리를 만들지 않는다', (tester) async {
      // `find.text('')` 로는 부족하다 — 빈 여백이 생겨도 잡지 못한다
      // (Codex 20회차). 메모 칸 자체가 없어야 한다.
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');

      expect(find.byKey(const Key('regionMemo')), findsNothing);
    });

    testWidgets('공백뿐인 메모도 칸을 만들지 않는다', (tester) async {
      await openApp(tester, savedWith(memo: '   '));
      await openRegion(tester, '경주시');

      expect(find.byKey(const Key('regionMemo')), findsNothing);
    });

    testWidgets('랜드마크가 없는 지역은 카테고리 문구로 간다', (tester) async {
      final saved = encodeCollection(
        CollectionSnapshot.empty.collect(CollectedUnit(
          scratchUnitId: '47250', // 상주시 — 랜드마크 없음
          collectedAtUtc: DateTime.parse('2026-08-14T00:00:00Z'),
          utcOffsetMinutes: 540,
        )),
      );
      await openApp(tester, saved);
      await openRegion(tester, '상주시');

      expect(find.text(descriptionFor('47250')), findsOneWidget);
    });
  });

  testWidgets('세로가 짧아도 넘치지 않고 버튼을 누를 수 있다', (tester) async {
    // 기본 테스트 화면(800×600)에서 30px 넘치던 것을 M3 에서 발견했다.
    //
    // **트리에 있는지만 보면 부족하다.** 버튼이 화면 밖에 있어도 통과한다
    // (Codex 20회차). 실제로 눌러서 시트가 닫히는지까지 본다.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 1800);
    view.devicePixelRatio = 3.0;

    await openApp(tester, savedWith(memo: '짧은 화면에서도 잘 보이는지'));
    await openRegion(tester, '경주시');

    expect(tester.takeException(), isNull, reason: '팝업이 넘쳤다');

    // **스크롤하지 않고 누른다.** `ensureVisible` 로 끌어올려 누르면 버튼이
    // 처음부터 화면 밖이어도 통과한다.
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(find.text('닫기'), findsNothing,
        reason: '버튼이 처음부터 화면 밖이라 눌리지 않았다');
  });
}

class _MemStorage implements CollectionStorage {
  _MemStorage(this.contents);
  String? contents;

  @override
  Future<String?> read() async => contents;
  @override
  Future<void> writeAtomically(String c) async => contents = c;
  @override
  Future<String> quarantine() async {
    contents = null;
    return 'corrupt.json';
  }
}

/// 설정 저장소를 주입한다. 실제 파일 경로는 `flutter test` 에서
/// `path_provider` 가 없어 늘 실패하므로, 주입하지 않으면 **모든 테스트가
/// 설정 로드를 기다리는 상태**에 머문다.
Future<SettingsStore> _testSettings() async {
  final s = SettingsStore(_InMemorySettings());
  await s.load();
  return s;
}

class _InMemorySettings implements SettingsStorage {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> writeAtomically(String c) async => contents = c;
}
