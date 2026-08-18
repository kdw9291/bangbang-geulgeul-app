import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/settings_store.dart';

/// M7 기록 탭.
///
/// **앱을 통째로 띄워 하단 탭으로 들어간다.** 화면만 따로 만들어 검사하면
/// 셸이 어떤 집합을 넘기는지가 바뀌어도 통과한다 — 기존 테스트가 전부 지도
/// 탭에서만 열기 때문에 "안 깨졌다" 가 안전 신호가 못 된다(M6 에서 배웠다).
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

  String saved(Iterable<String> ids) {
    var snap = CollectionSnapshot.empty;
    for (final id in ids) {
      snap = snap.collect(CollectedUnit(
        scratchUnitId: id,
        collectedAtUtc: DateTime.parse('2026-08-14T15:30:00Z'),
        utcOffsetMinutes: 540,
      ));
    }
    return encodeCollection(snap);
  }

  /// 카탈로그 앞에서부터 [n] 개를 수집한 상태를 만든다.
  String savedFirst(int n) =>
      saved(realMap.regions.take(n).map((r) => r.scratchUnitId));

  Future<void> openApp(
    WidgetTester tester,
    String? stored, {
    bool? showDiagnostics,
  }) async {
    await tester.pumpWidget(MapScratchApp(
      settingsOpener: () async => SettingsStore(_MemSettings()),
      mapLoader: () async => realMap,
      showDiagnostics: showDiagnostics,
      storeOpener: () async {
        final store = CollectionStore(_MemStorage(stored));
        return (store, await store.load());
      },
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  Future<void> goRecords(WidgetTester tester) async {
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
  }

  group('탭 구성', () {
    testWidgets('하단 탭이 지도·갤러리·기록 셋이다', (tester) async {
      await openApp(tester, null);
      expect(find.text('지도'), findsOneWidget);
      expect(find.text('갤러리'), findsOneWidget);
      expect(find.text('기록'), findsOneWidget);
    });

    testWidgets('탭을 오가도 지도와 저장소를 다시 읽지 않는다', (tester) async {
      var maps = 0;
      var stores = 0;
      await tester.pumpWidget(MapScratchApp(
        settingsOpener: () async => SettingsStore(_MemSettings()),
        mapLoader: () async {
          maps++;
          return realMap;
        },
        storeOpener: () async {
          stores++;
          final store = CollectionStore(_MemStorage(null));
          return (store, await store.load());
        },
      ));
      await tester.pump();
      await tester.runAsync(() => Future<void>.value());
      await tester.pump();
      await tester.pump();

      await goRecords(tester);
      await tester.tap(find.text('갤러리'));
      await tester.pumpAndSettle();
      await goRecords(tester);

      expect(maps, 1);
      expect(stores, 1);
    });
  });

  group('전체 달성률', () {
    testWidgets('빈 상태는 0/232 이고 첫 메달까지 20곳이다', (tester) async {
      await openApp(tester, null);
      await goRecords(tester);

      expect(find.text('0/232'), findsOneWidget);
      expect(find.text('20곳 메달까지 20곳 남았어요'), findsOneWidget);
    });

    testWidgets('알 수 없는 ID 는 달성률에 섞이지 않는다', (tester) async {
      // 여기서 1/232 가 나오면 `snapshot.length` 를 쓴 것이다.
      await openApp(tester, saved(['99999']));
      await goRecords(tester);

      expect(find.text('0/232'), findsOneWidget);
    });

    testWidgets('수집하면 남은 수가 줄어든다', (tester) async {
      await openApp(tester, savedFirst(5));
      await goRecords(tester);

      expect(find.text('5/232'), findsOneWidget);
      expect(find.text('20곳 메달까지 15곳 남았어요'), findsOneWidget);
    });
  });

  group('메달', () {
    testWidgets('빈 상태에서 다섯 개가 전부 미획득이다', (tester) async {
      await openApp(tester, null);
      await goRecords(tester);

      for (final id in ['count20', 'count50', 'count100', 'count150',
        'nationwide']) {
        expect(find.byKey(Key('medal:$id')), findsOneWidget, reason: id);
      }
      expect(find.text('획득'), findsNothing);
      expect(find.text('미획득'), findsNWidgets(5));
    });

    testWidgets('20곳에서 첫 메달만 획득이다', (tester) async {
      await openApp(tester, savedFirst(20));
      await goRecords(tester);

      expect(find.text('획득'), findsOneWidget);
      expect(find.text('미획득'), findsNWidgets(4));
      expect(find.text('50곳 메달까지 30곳 남았어요'), findsOneWidget);
    });

    testWidgets('19곳에서는 아직 하나도 없다', (tester) async {
      // 경계값. `>` 로 잘못 쓰면 20 에서도 안 나오고, `>=` 를 19 에 쓰면 여기서 난다.
      await openApp(tester, savedFirst(19));
      await goRecords(tester);
      expect(find.text('획득'), findsNothing);
    });

    testWidgets('전부 모으면 다섯 개 획득이고 다음 메달 문구가 없다', (tester) async {
      await openApp(tester, savedFirst(232));
      await goRecords(tester);

      expect(find.text('232/232'), findsOneWidget);
      expect(find.text('획득'), findsNWidgets(5));
      expect(find.text('전국을 다 모았어요!'), findsOneWidget);
      expect(find.textContaining('남았어요'), findsNothing,
          reason: '완주했는데 남은 곳을 말하고 있다');
    });
  });

  group('진단 수명주기', () {
    testWidgets('같은 State 에서 진단을 껐다 켜면 UI 가 양방향으로 따라온다',
        (tester) async {
      // `showDiagnostics` 를 `initState` 에서 한 번만 읽어 캐시하면 여기서 깨진다.
      // 같은 위젯 타입·키라 State 가 재사용되므로 `didUpdateWidget` 이 필요하다
      // (Codex 25회차).
      await openApp(tester, null, showDiagnostics: false);
      expect(find.text('벤치마크 시작'), findsNothing);

      await openApp(tester, null, showDiagnostics: true);
      expect(find.text('벤치마크 시작'), findsOneWidget);

      await openApp(tester, null, showDiagnostics: false);
      expect(find.text('벤치마크 시작'), findsNothing);
    });

    testWidgets('진단을 끄면 진단으로 만든 상태도 되돌아간다', (tester) async {
      // 수집만 멈추면 수동 벤치마크가 계속 돌고 데모 채움이 지도에 남는다 —
      // seam 이 "릴리스 구성" 을 온전히 재현하지 못한다(Codex 26회차).
      await openApp(tester, null, showDiagnostics: true);
      await tester.tap(find.text('시도선 끄기'));
      await tester.pump();
      await tester.tap(find.text('벤치마크 시작'));
      await tester.pump();
      expect(find.text('벤치마크 중지'), findsOneWidget);

      await openApp(tester, null, showDiagnostics: false);
      await openApp(tester, null, showDiagnostics: true);

      expect(find.text('벤치마크 시작'), findsOneWidget,
          reason: '진단을 껐는데 수동 벤치마크가 계속 돈다');
      expect(find.text('시도선 끄기'), findsOneWidget,
          reason: '진단으로 끈 시도선이 그대로 남았다');
    });
  });

  group('메달 접근성', () {
    testWidgets('획득 여부를 스크린 리더가 읽는다', (tester) async {
      // `excludeSemantics: true` 를 쓰므로 대체 라벨이 실제로 붙는지 본다.
      // 색과 테두리만으로 상태를 말하면 안 된다.
      final handle = tester.ensureSemantics();
      await openApp(tester, savedFirst(20));
      await goRecords(tester);

      final got = tester.getSemantics(find.byKey(const Key('medal:count20')));
      expect(got.label, '20곳 메달 획득');
      expect(got.getSemanticsData().hasAction(SemanticsAction.tap), isFalse,
          reason: '누를 수 없는 요소에 탭 액션이 생겼다');

      final notYet =
          tester.getSemantics(find.byKey(const Key('medal:count50')));
      expect(notYet.label, '50곳 메달 미획득');

      final nation =
          tester.getSemantics(find.byKey(const Key('medal:nationwide')));
      expect(nation.label, '전국 완주 메달 미획득');
      handle.dispose();
    });
  });

  group('시도 목록', () {
    testWidgets('16개가 데이터 순서대로 모두 나온다', (tester) async {
      // 16행뿐이라 지연 생성이 없다 — 스크롤 없이 전부 트리에 있어야 한다.
      await openApp(tester, null);
      await goRecords(tester);

      for (final name in realMap.sidoNames) {
        expect(find.byKey(Key('sido:$name')), findsOneWidget, reason: name);
      }
    });

    testWidgets('완주한 시도는 1/1 이든 47/47 이든 같은 완료 표기다', (tester) async {
      // 1/1 세 곳만 특별 취급하면 경기 47/47 과 표현이 갈린다(Codex 25회차).
      final gyeonggi = realMap.regions
          .where((r) => realMap.sidoNames[r.sido] == '경기도')
          .map((r) => r.scratchUnitId);
      await openApp(tester, saved(['11000', ...gyeonggi]));
      await goRecords(tester);

      expect(find.text('완료'), findsNWidgets(2),
          reason: '서울(1/1)과 경기(47/47) 둘 다 완료여야 한다');
      expect(find.text('1/1'), findsNothing);
      expect(find.text('47/47'), findsNothing);
    });

    testWidgets('미완주 시도는 분수로 보여준다', (tester) async {
      await openApp(tester, saved(['47130']));
      await goRecords(tester);

      expect(find.byKey(const Key('sido:경상북도')), findsOneWidget);
      expect(find.text('1/24'), findsOneWidget);
    });

    testWidgets('접근성 라벨에 분모가 들어간다', (tester) async {
      // "완료" 만 읽으면 몇 곳짜리 시도인지 알 수 없다.
      final handle = tester.ensureSemantics();
      await openApp(tester, saved(['11000']));
      await goRecords(tester);

      final seoul =
          tester.getSemantics(find.byKey(const Key('sido:서울특별시')));
      expect(seoul.label, contains('1곳 중 1곳'));
      expect(seoul.label, contains('완료'));

      final gb = tester.getSemantics(find.byKey(const Key('sido:경상북도')));
      expect(gb.label, contains('24곳 중 0곳'));
      handle.dispose();
    });
  });

  group('S1 진단 UI', () {
    testWidgets('기본(debug·profile)에서는 그대로 보인다', (tester) async {
      // 성능 측정 도구를 잃으면 안 된다. `kDebugMode` 로 막았다가 profile 에서
      // 사라져 고생한 전례가 있다(2026-08-15).
      await openApp(tester, null);
      expect(find.text('벤치마크 시작'), findsOneWidget);
      expect(find.text('3배 확대'), findsOneWidget);
    });

    testWidgets('릴리스 구성에서는 전부 사라진다', (tester) async {
      // `kReleaseMode` 는 컴파일 타임 상수라 뒤집을 수 없다. seam 이 없으면
      // 이 계약을 아무 테스트도 지나가지 않는다(Codex 25회차).
      await openApp(tester, null, showDiagnostics: false);

      for (final label in ['벤치마크 시작', '시도선 끄기', '3배 확대', '초기화',
        '60칸 채우기']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.textContaining('fps'), findsNothing);
      expect(find.textContaining('지도를 탭하면'), findsNothing);
    });

    testWidgets('릴리스 구성에서 지도가 넓어진다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(360 * 3, 640 * 3);

      await openApp(tester, null, showDiagnostics: true);
      final withUi = tester.getSize(find.byKey(const Key('koreaMap')));

      await openApp(tester, null, showDiagnostics: false);
      final without = tester.getSize(find.byKey(const Key('koreaMap')));

      expect(without.width, greaterThan(withUi.width),
          reason: '진단 UI 를 뺐는데 지도가 넓어지지 않았다');
    });

    testWidgets('릴리스 구성에서도 세 탭이 정상이다', (tester) async {
      await openApp(tester, savedFirst(20), showDiagnostics: false);
      await goRecords(tester);
      expect(find.text('20/232'), findsOneWidget);
      expect(find.text('획득'), findsOneWidget);
    });
  });

  group('레이아웃', () {
    testWidgets('큰 글꼴에서 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openApp(tester, savedFirst(60));
      await goRecords(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('60/232'), findsOneWidget);
    });

    testWidgets('좁은 화면에서 마지막 시도까지 스크롤된다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320 * 3, 568 * 3);

      await openApp(tester, null);
      await goRecords(tester);

      final last = realMap.sidoNames.last;
      await tester.scrollUntilVisible(find.byKey(Key('sido:$last')), 200,
          scrollable: find.descendant(
              of: find.byKey(const Key('recordsScroll')),
              matching: find.byType(Scrollable)));
      expect(find.byKey(Key('sido:$last')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _MemStorage implements CollectionStorage {
  _MemStorage(this._contents);
  String? _contents;

  @override
  Future<String?> read() async => _contents;
  @override
  Future<void> writeAtomically(String contents) async => _contents = contents;
  @override
  Future<String> quarantine() async {
    _contents = null;
    return 'collection.corrupt.test.json';
  }
}

class _MemSettings implements SettingsStorage {
  String? _contents;
  @override
  Future<String?> read() async => _contents;
  @override
  Future<void> writeAtomically(String contents) async => _contents = contents;
}
