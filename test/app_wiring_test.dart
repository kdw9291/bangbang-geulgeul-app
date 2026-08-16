import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/settings_store.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_painter.dart';

/// **앱 최상위 배선.** 저장소·지도 로드가 화면과 어떻게 맞물리는지 본다.
///
/// 이 파일이 생긴 이유는 `path_provider` 가 `flutter test` 에서
/// `MissingPluginException` 이라 저장소가 늘 `readFailed` 로 떨어졌기 때문이다.
/// 그 상태로는 **정상 배선을 테스트가 한 번도 지나가지 않는다**(Codex 16회차).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData realMap;
  setUpAll(() async => realMap = await MapData.load());

  // 기본 테스트 화면(800×600)은 실제 폰보다 **가로로 넓고 세로로 짧다.**
  // 소개 팝업이 세로로 넘쳐 레이아웃 오류가 났다. 실기기(Galaxy S25) 크기로 맞춘다.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// 바이트만 흉내 내는 저장소. 파싱·직렬화는 프로덕션 코드가 한다.
  CollectionStorage mem(String? contents) => _MemStorage(contents);

  StoreOpener opener(CollectionStorage storage, {Future<void>? gate}) {
    return () async {
      if (gate != null) await gate;
      final store = CollectionStore(storage);
      return (store, await store.load());
    };
  }

  MapLoader mapAfter(Future<void>? gate) => () async {
        if (gate != null) await gate;
        return realMap;
      };

  Future<void> pumpApp(
    WidgetTester tester, {
    required MapLoader mapLoader,
    required StoreOpener storeOpener,
  }) async {
    await tester.pumpWidget(MapScratchApp(
      settingsOpener: _testSettings,
      mapLoader: mapLoader,
      storeOpener: storeOpener,
    ));
    await tester.pump();
  }

  /// **`runAsync` 안에서는 `pump` 를 부르지 않는다.** 대기와 렌더를 섞으면
  /// `setState` 가 화면에 반영되지 않는다 — 실제로 한 번 그렇게 썼다가 고쳤다.
  ///
  /// 벽시계로 기다리지 않는다. 이 테스트의 I/O 는 전부 메모리이고 지도는
  /// `setUpAll` 에서 이미 읽었으므로, 마이크로태스크만 흘려보내면 충분하다.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  /// 지도 painter 가 실제로 받은 수집 집합.
  Set<String> scratchedInPainter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<KoreaMapPainter>()
      .single
      .scratched;

  group('로드 순서', () {
    testWidgets('저장 로드가 늦으면 지도를 아직 열지 않는다', (tester) async {
      // 지도만 먼저 띄우면 ① 잠깐 전부 미수집으로 보이고 ② 그 사이 완료가
      // 가능하며 ③ 늦게 온 로드가 그 결과를 덮어쓴다.
      final gate = Completer<void>();
      await pumpApp(tester,
          mapLoader: mapAfter(null),
          storeOpener: opener(mem(null), gate: gate.future));

      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: '저장 로드가 끝나지 않았는데 지도가 열렸다');

      gate.complete();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('지도 로드가 늦으면 지도를 아직 열지 않는다', (tester) async {
      final gate = Completer<void>();
      await pumpApp(tester,
          mapLoader: mapAfter(gate.future), storeOpener: opener(mem(null)));

      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: '지도 로드가 끝나지 않았는데 화면이 열렸다');

      gate.complete();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('둘 다 끝나면 저장돼 있던 수집이 지도에 반영된다', (tester) async {
      final saved = encodeCollection(CollectionSnapshot.empty.collect(
        CollectedUnit(
          scratchUnitId: 'DK001',
          collectedAtUtc: DateTime.parse('2026-08-14T00:00:00Z'),
          utcOffsetMinutes: 540,
        ),
      ));
      await pumpApp(tester,
          mapLoader: mapAfter(null), storeOpener: opener(mem(saved)));
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // **painter 가 실제로 무엇을 받았는지 본다.** `지역 232개` 는 수집이
      // 비어 있어도 뜨므로, 그것만 보면 반영 코드를 지워도 통과한다
      // (Codex 17회차).
      expect(scratchedInPainter(tester), contains('DK001'));
    });
  });

  group('검색 진입', () {
    // **검색은 접근 수단일 뿐이고 그 뒤 흐름은 탭과 같아야 한다.**
    // 시트가 `Region` 을 돌려주는 것까지만 검사하면, 나중에 별도 경로가
    // 생기거나 쓰기 차단을 건너뛰어도 잡지 못한다 (Codex 18회차).

    Future<void> pickFromSearch(WidgetTester tester, String query) async {
      await tester.tap(find.text('지역 검색'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      // 입력란에도 같은 글자가 있으므로 **결과 행**을 짚어서 누른다.
      await tester.tap(find.widgetWithText(ListTile, query).first);
      await tester.pumpAndSettle();
    }

    testWidgets('검색으로 고르면 탭했을 때와 같은 소개 팝업이 열린다', (tester) async {
      await pumpApp(tester,
          mapLoader: mapAfter(null), storeOpener: opener(mem(null)));
      await settle(tester);

      await pickFromSearch(tester, '경주시');

      // 소개 팝업의 표지 — 지역명과 긁기 버튼.
      expect(find.text('지역 긁기'), findsOneWidget);
      expect(find.text('경주시'), findsWidgets);
    });

    testWidgets('쓰기 불가 상태에서는 검색으로 들어가도 긁기로 넘어가지 않는다', (tester) async {
      // 더 새로운 버전이라 쓰기를 막은 상태. 긁게 두면 사용자가 한 일이
      // 통째로 버려진다.
      await pumpApp(tester,
          mapLoader: mapAfter(null),
          storeOpener: opener(mem('{"version":99,"units":[]}')));
      await settle(tester);

      await pickFromSearch(tester, '경주시');
      await tester.tap(find.text('지역 긁기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('업데이트'), findsWidgets);
      expect(find.text('손가락으로 문질러 긁어보세요'), findsNothing,
          reason: '쓰기 불가인데 긁기 화면으로 넘어갔다');
    });
  });

  group('지도 제스처', () {
    // `onTapDown` 이던 것을 `onTapUp` 으로 바꿨다. 누르는 순간 팝업을 열면
    // 지도를 끌려던 것까지 선택으로 처리된다 (M9, S1 이월).

    /// 지도 한가운데. 내륙이라 어느 지역이든 걸린다.
    Offset mapCenter(WidgetTester tester) =>
        tester.getCenter(find.byType(InteractiveViewer));

    testWidgets('탭하면 소개 팝업이 열린다', (tester) async {
      await pumpApp(tester,
          mapLoader: mapAfter(null), storeOpener: opener(mem(null)));
      await settle(tester);

      await tester.tapAt(mapCenter(tester));
      await tester.pumpAndSettle();

      expect(find.text('지역 긁기'), findsOneWidget);
    });

    testWidgets('끌면 팝업이 열리지 않는다', (tester) async {
      await pumpApp(tester,
          mapLoader: mapAfter(null), storeOpener: opener(mem(null)));
      await settle(tester);

      // **손을 잠깐 댔다가 끈다.** 곧바로 휙 끄는 동작으로는 차이가 안 난다 —
      // `onTapDown` 은 누른 뒤 약 100ms(`kPressTimeout`)가 지나야 발동하므로,
      // 빠른 드래그에서는 어느 쪽이든 팝업이 안 열린다. 실제 사용자는
      // 손을 대고 잠시 뒤에 끈다.
      final g = await tester.startGesture(mapCenter(tester));
      await tester.pump(const Duration(milliseconds: 200));
      await g.moveBy(const Offset(0, -160));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(find.text('지역 긁기'), findsNothing,
          reason: '끌었는데 팝업이 열렸다');
    });
  });

  group('로드 실패 안내', () {
    testWidgets('손상 파일은 시작 직후 알린다', (tester) async {
      // 조용히 빈 상태로 시작하면 사용자는 기록이 사라진 것을 모른 채
      // 새로 긁기 시작한다.
      await pumpApp(tester,
          mapLoader: mapAfter(null), storeOpener: opener(mem('깨진 내용')));
      await settle(tester);

      expect(find.textContaining('읽을 수 없어'), findsOneWidget);
      expect(find.textContaining('따로 보관'), findsOneWidget);
    });

    testWidgets('더 새로운 버전은 업데이트를 안내한다', (tester) async {
      await pumpApp(tester,
          mapLoader: mapAfter(null),
          storeOpener: opener(mem('{"version":99,"units":[]}')));
      await settle(tester);

      expect(find.textContaining('업데이트'), findsOneWidget);
    });

    testWidgets('정상 로드에서는 아무 안내도 뜨지 않는다', (tester) async {
      await pumpApp(tester,
          mapLoader: mapAfter(null), storeOpener: opener(mem(null)));
      await settle(tester);

      expect(find.byType(SnackBar), findsNothing);
    });
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
