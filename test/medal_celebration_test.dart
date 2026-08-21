import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/achievement.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/medal_celebration.dart';
import 'package:mapscratch/settings_store.dart';

/// 메달 축하 팝업 (2026-08-19 M10 사용자 요청).
///
/// **앱을 통째로 띄워 실제로 긁는다.** 축하를 띄우는 자리가 저장 성공 직후라,
/// 화면만 따로 만들어 검사하면 그 조건이 바뀌어도 통과한다.
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

  /// 카탈로그 앞에서부터 [n] 곳을 수집한 저장 파일.
  String savedFirst(int n) {
    var snap = CollectionSnapshot.empty;
    for (final r in realMap.regions.take(n)) {
      snap = snap.collect(CollectedUnit(
        scratchUnitId: r.scratchUnitId,
        collectedAtUtc: DateTime.parse('2026-08-14T15:30:00Z'),
        utcOffsetMinutes: 540,
      ));
    }
    return encodeCollection(snap);
  }

  /// 아직 수집하지 않은 지역 중 **이름이 유일한** 첫 곳.
  ///
  /// 그냥 다음 지역을 쓰면 안 된다 — `서구` 는 네 곳이라 검색 결과에서 다른
  /// 지역을 누르게 된다. 실제로 그렇게 깨졌다.
  String firstUncollected(int collectedCount) {
    final dup = <String, int>{};
    for (final r in realMap.regions) {
      dup[r.name] = (dup[r.name] ?? 0) + 1;
    }
    return realMap.regions
        .skip(collectedCount)
        .firstWhere((r) => dup[r.name] == 1)
        .name;
  }

  Future<void> openApp(WidgetTester tester, String? stored,
      {CollectionStorage? storage}) async {
    await tester.pumpWidget(MapScratchApp(
      settingsOpener: () async => SettingsStore(_MemSettings()),
      mapLoader: () async => realMap,
      showDiagnostics: false,
      storeOpener: () async {
        final store = CollectionStore(storage ?? _MemStorage(stored));
        return (store, await store.load());
      },
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  /// 검색으로 지역을 골라 긁기 화면까지 간 뒤 임계치를 넘긴다.
  Future<void> scratch(WidgetTester tester, String name) async {
    await tester.tap(find.text('지역 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('지역 긁기'));
    await tester.pumpAndSettle();

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var y = 40.0; y < size.height - 40; y += 12) {
      await tester.dragFrom(Offset(20, y), Offset(size.width - 40, 0));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 700));
    // **`pumpAndSettle` 을 쓰지 않는다.** 긁기 화면에 지속 애니메이션이 있어
    // 안정 상태에 도달하지 않는다 — `collection_flow_test` 와 같은 이유다.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('축하 시점', () {
    testWidgets('19곳에서 한 곳 더 긁으면 20곳 메달을 축하한다', (tester) async {
      await openApp(tester, savedFirst(19));
      await scratch(tester, firstUncollected(19));

      expect(find.byKey(const Key('medalCelebration')), findsOneWidget);
      expect(find.text('20곳 메달을 땄어요'), findsOneWidget);
      expect(find.text('20/193곳'), findsOneWidget);
    });

    testWidgets('메달을 넘지 않는 수집에는 뜨지 않는다', (tester) async {
      // 경계값. 5곳에서 6곳이 되는 것으로는 아무것도 열리지 않는다.
      await openApp(tester, savedFirst(5));
      await scratch(tester, firstUncollected(5));

      expect(find.byKey(const Key('medalCelebration')), findsNothing);
    });

    testWidgets('닫으면 사라지고 다시 뜨지 않는다', (tester) async {
      await openApp(tester, savedFirst(19));
      await scratch(tester, firstUncollected(19));

      await tester.tap(find.byKey(const Key('medalCelebrationClose')));
      // 다이얼로그 닫힘 애니메이션이 끝나야 트리에서 빠진다.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('medalCelebration')), findsNothing);

      // 긁기 화면을 닫고 지도로 돌아와도 다시 뜨지 않는다.
      await tester.tap(find.text('지도로 돌아가기'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('medalCelebration')), findsNothing);
    });
  });

  group('저장 완료를 붙잡지 않는다', () {
    testWidgets('축하가 떠 있어도 기록하는 중이 아니고 나갈 수 있다', (tester) async {
      // **실기기에서 눈으로 찾은 결함이다.** 축하를 `await` 하면 긁기 화면이
      // `onCollected` 가 끝나기를 기다리느라 저장이 끝났는데도 "기록하는 중" 에
      // 머물고 이탈도 막힌다(M1 계약). 저장은 이미 성공했으므로 거짓 표시다.
      await openApp(tester, savedFirst(19));
      await scratch(tester, firstUncollected(19));

      expect(find.byKey(const Key('medalCelebration')), findsOneWidget);
      expect(find.textContaining('기록하는 중'), findsNothing,
          reason: '저장이 끝났는데 기록 중으로 보인다');
      // 완료 상태의 버튼이 이미 나와 있어야 한다.
      expect(find.text('지도로 돌아가기'), findsOneWidget,
          reason: '축하가 완료 화면을 붙잡고 있다');
    });
  });

  group('수명', () {
    testWidgets('뒤로가기가 팝업부터 닫고 그다음 긁기 화면을 닫는다', (tester) async {
      // 팝업은 `unawaited` 로 띄우므로 아래 화면과 수명이 얽히지 않아야 한다.
      // "버튼이 트리에 있다" 만 보면 모달 장벽 때문에 못 누르는 상태를 놓친다
      // (Codex 29회차).
      await openApp(tester, savedFirst(19));
      await scratch(tester, firstUncollected(19));
      expect(find.byKey(const Key('medalCelebration')), findsOneWidget);

      await tester.binding.handlePopRoute();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('medalCelebration')), findsNothing,
          reason: '뒤로가기가 팝업을 안 닫았다');
      expect(find.text('지도로 돌아가기'), findsOneWidget,
          reason: '팝업만 닫히고 긁기 화면은 남아야 한다');

      // 팝업이 사라졌으니 이제 실제로 누를 수 있어야 한다.
      await tester.tap(find.text('지도로 돌아가기'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('koreaMap')), findsOneWidget);
    });

    testWidgets('짧은 가로 화면 + 큰 글꼴에서 넘치지 않는다', (tester) async {
      // **팝업만 직접 띄운다.** 가로 + 2.5배 글꼴에서는 검색·긁기 흐름 자체가
      // 성립하지 않아 전체 경로로는 이 레이아웃을 검사할 수 없다.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(568 * 3, 320 * 3);
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final medals = MedalSet.forTotal(193);
      await tester.pumpWidget(MaterialApp(
        home: AppThemeScope(
          theme: kThemeLight,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMedalCelebration(
                context,
                medal: medals.medals.last, // 문구가 가장 긴 전국 완주
                collected: 193,
                total: 193,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('medalCelebration')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 닫기 버튼이 실제로 눌려야 한다 — 넘치면 화면 밖에 있다.
      await tester.tap(find.byKey(const Key('medalCelebrationClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('medalCelebration')), findsNothing);
    });
  });

  group('저장 실패', () {
    testWidgets('저장에 실패하면 축하하지 않는다', (tester) async {
      // **수집이 성립하지 않았는데 축하하면 거짓말이 된다.**
      await openApp(tester, null, storage: _FailingStorage(savedFirst(19)));
      await scratch(tester, firstUncollected(19));

      expect(find.byKey(const Key('medalCelebration')), findsNothing,
          reason: '저장이 실패했는데 메달을 축하했다');
    });
  });

  group('전국 완주', () {
    testWidgets('마지막 한 곳을 긁으면 완주 문구가 나온다', (tester) async {
      await openApp(tester, savedFirst(192));
      await scratch(tester, firstUncollected(192));

      expect(find.text('전국을 다 모았어요!'), findsOneWidget);
      expect(find.text('193/193곳'), findsOneWidget);
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

/// 읽기는 되지만 **쓰기가 실패**하는 저장소.
class _FailingStorage implements CollectionStorage {
  _FailingStorage(this._contents);
  final String? _contents;

  @override
  Future<String?> read() async => _contents;
  @override
  Future<void> writeAtomically(String contents) =>
      Future.error(StateError('디스크가 가득 찼다'));
  @override
  Future<String> quarantine() async => 'collection.corrupt.test.json';
}

class _MemSettings implements SettingsStorage {
  String? _contents;
  @override
  Future<String?> read() async => _contents;
  @override
  Future<void> writeAtomically(String contents) async => _contents = contents;
}
