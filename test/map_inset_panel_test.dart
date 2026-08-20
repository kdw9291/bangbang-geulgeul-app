import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_inset.dart';
import 'package:mapscratch/map_inset_panel.dart';
import 'package:mapscratch/settings_store.dart';

/// M8 인셋 판.
///
/// **앱을 통째로 띄운다.** 판만 따로 만들어 검사하면 셸이 무엇을 넘기는지,
/// 탭이 어느 경로로 가는지가 바뀌어도 통과한다.
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

  Future<void> openApp(
    WidgetTester tester,
    String? stored, {
    CollectionLoadStatus status = CollectionLoadStatus.ok,
    bool? showDiagnostics,
  }) async {
    await tester.pumpWidget(MapScratchApp(
      settingsOpener: () async => SettingsStore(_MemSettings()),
      mapLoader: () async => realMap,
      showDiagnostics: showDiagnostics,
      storeOpener: () async {
        final store = CollectionStore(_MemStorage(stored));
        final result = await store.load();
        if (status == CollectionLoadStatus.ok) return (store, result);
        return (store, CollectionLoadResult(status, result.snapshot));
      },
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('insetToggle')));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('insetPick:$id')));
    await tester.pumpAndSettle();
  }

  /// 인셋 캔버스 위에서 [region] 중심에 해당하는 화면 좌표.
  Offset canvasPointOf(WidgetTester tester, String insetId, Region region) {
    final inset = resolveInset(
      kInsetDefinitions.firstWhere((d) => d.id == insetId),
      realMap,
    );
    final box = tester.getRect(find.byKey(Key('insetCanvas:$insetId')));
    final t = InsetTransform.fit(inset.window, box.size);
    return box.topLeft + t.toCanvas(region.bounds.center);
  }

  Region regionOf(String id) =>
      realMap.regions.firstWhere((r) => r.scratchUnitId == id);

  group('접기', () {
    testWidgets('기본은 접혀 있고 판이 트리에 없다', (tester) async {
      await openApp(tester, null);
      expect(find.byKey(const Key('insetToggle')), findsOneWidget);
      expect(find.byKey(const Key('insetPanel')), findsNothing);
    });

    testWidgets('접힌 상태에서 지도 탭이 막히지 않는다', (tester) async {
      // 투명한 전체 화면 제스처를 깔면 지도가 통째로 막힌다(Codex 27회차).
      await openApp(tester, null);
      // **지도 한가운데는 바다다.** 큰 지역을 정확히 겨냥한다.
      final map = tester.getRect(find.byKey(const Key('koreaMap')));
      final scale = map.width / realMap.size.width;
      final target = regionOf('51720'); // 홍천군 — 가장 큰 지역
      await tester.tapAt(map.topLeft + target.bounds.center * scale);
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget,
          reason: '접힌 인셋이 지도 탭을 먹었다');
    });

    testWidgets('열고 닫을 수 있다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);
      expect(find.byKey(const Key('insetPanel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('insetClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insetPanel')), findsNothing);
    });

    testWidgets('탭을 오가도 펼침이 유지된다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);

      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지도'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('insetPanel')), findsOneWidget);
    });
  });

  group('구역 선택', () {
    testWidgets('한 번에 한 구역만 그린다', (tester) async {
      // 셋을 동시에 그리면 판이 작아져 확대율이 무너진다.
      await openApp(tester, null);
      await openPanel(tester);

      expect(find.byKey(const Key('insetCanvas:capital')), findsOneWidget);
      expect(find.byKey(const Key('insetCanvas:busan')), findsNothing);
      expect(find.byKey(const Key('insetCanvas:daegu')), findsNothing);

      await pick(tester, 'daegu');
      expect(find.byKey(const Key('insetCanvas:daegu')), findsOneWidget);
      expect(find.byKey(const Key('insetCanvas:capital')), findsNothing);
    });

    testWidgets('세 구역을 각각 열 수 있다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);
      for (final id in ['capital', 'busan', 'daegu']) {
        await pick(tester, id);
        expect(find.byKey(Key('insetCanvas:$id')), findsOneWidget, reason: id);
        expect(tester.takeException(), isNull, reason: id);
      }
    });
  });

  group('탭 경로', () {
    testWidgets('인셋에서 지역을 누르면 팝업이 열린다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');

      // 대구 중구 — 본지도에서는 2.6px 라 누를 수 없는 크기다.
      await tester.tapAt(canvasPointOf(tester, 'daegu', regionOf('27110')));
      await tester.pumpAndSettle();

      expect(find.text('중구'), findsWidgets);
      expect(find.text('지역 긁기'), findsOneWidget);
    });

    testWidgets('저장할 수 없는 상태면 긁기 화면으로 못 간다', (tester) async {
      // 인셋이 팝업을 자체 구현하면 이 게이트를 지나친다 — 게이트는
      // `_openRegion` 안에 있다.
      await openApp(tester, null,
          status: CollectionLoadStatus.unsupportedVersion);
      await openPanel(tester);
      await pick(tester, 'daegu');

      await tester.tapAt(canvasPointOf(tester, 'daegu', regionOf('27110')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지역 긁기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('더 새로운 버전'), findsOneWidget);
      expect(find.text('긁기 완료'), findsNothing);
    });

    testWidgets('판을 누르면 아래 지도가 같은 탭을 받지 않는다', (tester) async {
      // **스스로 검증하는 테스트다.** 판 아래에 실제로 지역이 있는 좌표를 찾아
      // ① 판을 닫고 눌러 지역이 열리는 것을 확인하고 ② 판을 연 뒤 같은 좌표가
      // 더 이상 지도로 가지 않는 것을 본다. 판이 바다 위에만 있으면 이 테스트는
      // 아무것도 증명하지 못하므로, 겨냥할 좌표를 계산해서 고른다.
      await openApp(tester, null);
      await openPanel(tester);
      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      final map = tester.getRect(find.byKey(const Key('koreaMap')));
      final scale = map.width / realMap.size.width;

      Offset? probe;
      for (final r in realMap.regions) {
        final p = map.topLeft + r.bounds.center * scale;
        // 판 안이면서 컨트롤을 피해 위쪽 머리글 띠에 있는 점.
        if (panel.contains(p) && p.dy < panel.top + 24) {
          probe = p;
          break;
        }
      }
      if (probe == null) {
        markTestSkipped('판 아래에 지역이 없어 이 테스트는 성립하지 않는다');
        return;
      }

      await tester.tap(find.byKey(const Key('insetClose')));
      await tester.pumpAndSettle();
      await tester.tapAt(probe);
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget,
          reason: '판이 없을 때는 그 자리에서 지역이 열려야 한다');
      Navigator.of(tester.element(find.text('지역 긁기'))).pop();
      await tester.pumpAndSettle();

      await openPanel(tester);
      await tester.tapAt(probe);
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsNothing,
          reason: '판 위를 눌렀는데 아래 지도가 지역을 열었다');
    });

    testWidgets('인셋 여백 탭이 아래 지도로 새지 않는다', (tester) async {
      // 인셋 안의 빈 곳(지역 없음)을 눌러도 아래 지도가 같은 탭을 받으면
      // 엉뚱한 지역이 열린다.
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');

      final box = tester.getRect(find.byKey(const Key('insetCanvas:daegu')));
      await tester.tapAt(box.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(find.text('지역 긁기'), findsNothing,
          reason: '인셋 여백 탭이 아래 지도로 흘렀다');
    });
  });

  group('허용 오차', () {
    testWidgets('어느 지역에도 안 든 빈 자리를 눌러도 가까운 지역이 열린다',
        (tester) async {
      // 지역 중심이나 이웃 지역 안을 누르면 허용 오차가 0 이어도 통과한다 —
      // **이웃 팝업이 열려도 "열렸다" 이기 때문이다.** 어느 지역 path 에도
      // 들지 않으면서 허용 오차 안인 자리를 찾아 겨냥한다.
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');

      final inset = resolveInset(
        kInsetDefinitions.firstWhere((d) => d.id == 'daegu'),
        realMap,
      );
      final box = tester.getRect(find.byKey(const Key('insetCanvas:daegu')));
      final t = InsetTransform.fit(inset.window, box.size);
      final tol = t.mapUnitsPerPx(12);

      Offset? gap;
      for (var y = t.dest.top + 2; y < t.dest.bottom - 2 && gap == null; y += 3) {
        for (var x = t.dest.left + 2; x < t.dest.right - 2; x += 3) {
          final map = t.toMap(Offset(x, y));
          if (map == null) continue;
          if (inset.regions.any((r) => r.path.contains(map))) continue;
          final d = inset.regions
              .map((r) => r.distanceTo(map))
              .reduce((a, b) => a < b ? a : b);
          if (d > 0 && d <= tol) {
            gap = Offset(x, y);
            break;
          }
        }
      }
      expect(gap, isNotNull,
          reason: '빈 자리를 못 찾아 이 테스트가 성립하지 않는다');

      await tester.tapAt(box.topLeft + gap!);
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget,
          reason: '허용 오차 안의 빈 자리를 눌렀는데 아무것도 안 열렸다');
    });
  });

  group('확대와 무관하다', () {
    testWidgets('지도를 3배 확대해도 인셋 위치와 크기가 그대로다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');
      final before = tester.getRect(find.byKey(const Key('insetCanvas:daegu')));

      await tester.tap(find.text('3배 확대'));
      await tester.pumpAndSettle();

      final after = tester.getRect(find.byKey(const Key('insetCanvas:daegu')));
      expect(after, before, reason: '인셋이 지도 확대를 따라갔다');
    });

    testWidgets('확대 전후 같은 인셋 좌표가 같은 지역을 연다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');
      final p = canvasPointOf(tester, 'daegu', regionOf('27110'));

      await tester.tapAt(p);
      await tester.pumpAndSettle();
      final firstFound = find.text('중구').evaluate().isNotEmpty;
      // 미수집 팝업에는 `닫기` 가 없다 — 시트를 뒤로가기로 닫는다.
      Navigator.of(tester.element(find.text('지역 긁기'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('3배 확대'));
      await tester.pumpAndSettle();
      await tester.tapAt(p);
      await tester.pumpAndSettle();

      expect(firstFound, isTrue);
      expect(find.text('중구'), findsWidgets, reason: '확대 후 다른 지역이 열렸다');
    });
  });

  group('수집 반영', () {
    testWidgets('수집하면 인셋 그림이 바뀐다', (tester) async {
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');
      final empty = await _capture(tester, 'daegu');

      // **State 를 새로 만들어야 한다.** 같은 위젯 타입으로 다시 pump 하면
      // `MapSpikePage` State 가 재사용돼 `_load()` 가 다시 돌지 않는다 —
      // 새 저장소를 넘겨도 `_scratched` 가 비어 있는 채로 남는다.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      await openApp(tester, saved(['27110', '27140', '27170']));
      await openPanel(tester);
      await pick(tester, 'daegu');
      final some = await _capture(tester, 'daegu');

      expect(some, isNot(equals(empty)),
          reason: '수집했는데 인셋 그림이 그대로다');
    });
  });

  group('접근성', () {
    testWidgets('접기 버튼이 48px 이상이고 탭 액션이 있다', (tester) async {
      final handle = tester.ensureSemantics();
      await openApp(tester, null);

      final size = tester.getSize(find.byKey(const Key('insetToggle')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      final node = tester.getSemantics(find.byKey(const Key('insetToggle')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.label, contains('도심 확대'));
      handle.dispose();
    });

    testWidgets('지역 목록이 눌러 보이는 버튼이다', (tester) async {
      // **실기기에서 그냥 설명문처럼 보였다.** 이 화면의 접근성 대안이라
      // 발견되지 않으면 없는 것과 같다. 배경과 아이콘으로 버튼임을 알린다.
      await openApp(tester, null);
      await openPanel(tester);

      final button = find.byKey(const Key('insetList'));
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.list)),
        findsOneWidget,
        reason: '아이콘이 없어 눌러 보이지 않는다',
      );
      // 배경이 칠해져 있어야 한다 — 맨 글자면 눌러 보이지 않는다.
      final material = tester.widget<Material>(
          find.ancestor(of: button, matching: find.byType(Material)).first);
      expect(material.color, isNotNull);
    });

    testWidgets('펼친 판의 조작부가 모두 48px 이상이다', (tester) async {
      // 목록 행만 48px 이면 부족하다 — 목록으로 **들어가는 버튼**과 구역 선택,
      // 닫기도 손가락으로 눌러야 한다(Codex 28회차).
      await openApp(tester, null);
      await openPanel(tester);

      for (final k in ['insetClose', 'insetList', 'insetPick:capital',
        'insetPick:busan', 'insetPick:daegu']) {
        final size = tester.getSize(find.byKey(Key(k)));
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
      }
    });

    testWidgets('지역 목록 행이 48px 이상이고 같은 팝업을 연다', (tester) async {
      // 시각 도형은 6~23px 이라 최소 탭 영역을 만족할 수 없다.
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');

      await tester.tap(find.byKey(const Key('insetList')));
      await tester.pumpAndSettle();

      final row = find.byKey(const Key('insetRow:27110'));
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget);
    });

    testWidgets('목록이 수집 여부를 글자로 말한다', (tester) async {
      // 색만으로 상태를 전달하면 안 된다.
      await openApp(tester, saved(['27110']));
      await openPanel(tester);
      await pick(tester, 'daegu');
      await tester.tap(find.byKey(const Key('insetList')));
      await tester.pumpAndSettle();

      expect(find.text('수집'), findsOneWidget);
      expect(find.text('미수집'), findsNWidgets(7));
    });
  });

  group('실제 확대 효과', () {
    testWidgets('화면에 그려진 크기로 재도 목표를 넘는다', (tester) async {
      // **상수가 아니라 실제 위젯 크기로 잰다.** 테스트가 다른 크기를 쓰면
      // "부산 중구가 6px 이상" 이라는 검증이 화면과 무관해진다 — 실제로
      // 테스트 160×200 · PNG 172×190 · UI 176×158 로 갈려 있었고
      // **UI 에서만 5.39px 로 목표를 못 넘고 있었다**(Codex 28회차).
      await openApp(tester, null);
      await openPanel(tester);

      for (final id in ['capital', 'busan', 'daegu']) {
        await pick(tester, id);
        final size = tester.getSize(find.byKey(Key('insetCanvas:$id')));
        final inset = resolveInset(
          kInsetDefinitions.firstWhere((d) => d.id == id),
          realMap,
        );
        final t = InsetTransform.fit(inset.window, size);
        final smallest = inset.regions
            .map((r) => r.bounds.width > r.bounds.height
                ? r.bounds.width
                : r.bounds.height)
            .reduce((a, b) => a < b ? a : b);
        final mainPx = 360.0 / realMap.size.width;
        expect(smallest * t.scale, greaterThan(6),
            reason: '$id: 화면에서 '
                '${(smallest * t.scale).toStringAsFixed(2)}px 밖에 안 된다');
        expect(smallest * t.scale, greaterThan(smallest * mainPx * 2),
            reason: '$id: 본지도 대비 2배도 안 커졌다');
      }
    });
  });

  group('선택 반영', () {
    testWidgets('인셋에서 고르면 인셋 그림에 선택 외곽선이 실제로 그려진다',
        (tester) async {
      // **배선만 보면 안 된다.** `setState(() => _selected = r)` 를 지워도
      // 팝업은 열리므로 "팝업이 열렸다" 만 검사하면 통과한다(Codex 28회차).
      // 선택 전후 픽셀이 실제로 달라지는지 본다.
      await openApp(tester, null);
      await openPanel(tester);
      await pick(tester, 'daegu');
      final before = await _capture(tester, 'daegu');

      await tester.tapAt(canvasPointOf(tester, 'daegu', regionOf('27110')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('지역 긁기'))).pop();
      await tester.pumpAndSettle();

      final after = await _capture(tester, 'daegu');
      expect(after, isNot(equals(before)),
          reason: '선택했는데 인셋 그림이 그대로다');
    });
  });

  group('레이아웃', () {
    testWidgets('좁고 짧은 화면에서는 판이 화면 밖으로 나가지 않는다',
        (tester) async {
      // **폭을 안 보면 390px 판이 360px 화면 밖으로 나간다.** 부모와 판이
      // 각자 판단하면 부모는 세로형인데 판만 좌우형이 되는 상태도 생긴다
      // (Codex 28회차).
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      // **짧고 좁아야 폭 조건을 탄다.** 360×520 은 세로가 넉넉해 애초에
      // 좌우형으로 가지 않으므로 이 검사가 아무것도 증명하지 못한다.
      view.physicalSize = const Size(360 * 3, 360 * 3);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('insetWide')), findsNothing,
          reason: '폭이 390 도 안 되는데 좌우로 폈다');

      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      expect(panel.left, greaterThanOrEqualTo(0),
          reason: '판이 화면 왼쪽 밖으로 나갔다');
      expect(panel.right, lessThanOrEqualTo(360),
          reason: '판이 화면 오른쪽 밖으로 나갔다');
    });

    testWidgets('넓은 세로 화면에서는 좌우 배치를 쓰지 않는다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(800 * 3, 1280 * 3);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      expect(find.byKey(const Key('insetWide')), findsNothing,
          reason: '세로가 넉넉한데 좌우로 폈다');
    });

    testWidgets('지도 영역이 아주 짧아도 판이 영역을 넘지 않는다', (tester) async {
      // **debug 가로에서 실제로 잘렸다.** 진단 UI 가 세로를 먹어 지도 영역이
      // 210px 로 눌리자, 판 높이 하한(120)이 영역을 넘어 위쪽이 잘렸다.
      // 남는 만큼만 쓰고 모자라면 판 안에서 스크롤해야 한다.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(568 * 3, 320 * 3);

      // 진단 UI 를 켠 채로 — 이것이 지도 영역을 짓누른다.
      await openApp(tester, null, showDiagnostics: true);
      await openPanel(tester);
      expect(tester.takeException(), isNull);

      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      final map = tester.getRect(find.byKey(const Key('koreaMap')));
      expect(panel.top, greaterThanOrEqualTo(map.top - 0.5),
          reason: '판이 지도 영역 위로 넘쳐 머리글이 잘린다');
    });

    testWidgets('어떤 화면에서도 캔버스가 눌리지 않는다', (tester) async {
      // **이것이 실제 계약이다.** 캔버스가 부모 제약에 눌리면 확대율이 떨어져
      // 부산 중구가 다시 5px 대로 내려간다. 변환은 실제 크기를 따라가도록
      // 해 두었지만(안전망), 애초에 눌리지 않는 것이 목표다(Codex 28회차).
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      for (final size in [
        const Size(360 * 3, 780 * 3), // 일반 세로
        const Size(320 * 3, 568 * 3), // 좁은 세로
        const Size(568 * 3, 320 * 3), // 가로
      ]) {
        view.physicalSize = size;
        await openApp(tester, null, showDiagnostics: false);
        await openPanel(tester);
        expect(
          tester.getSize(find.byKey(const Key('insetCanvas:capital'))),
          kInsetCanvasSize,
          reason: '$size 에서 캔버스가 눌렸다',
        );
        await tester.tap(find.byKey(const Key('insetClose')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('좁은 화면에서 넘치지 않는다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320 * 3, 568 * 3);
      await openApp(tester, null);
      await openPanel(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('큰 글꼴에서 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openApp(tester, null);
      await openPanel(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('가로 화면에서 판이 지도 영역 안에 들어간다', (tester) async {
      // **실제 수정 대상이던 조합이다.** 세로 좁은 화면과 큰 글꼴을 따로
      // 검사하면 `SingleChildScrollView` 나 `maxHeight` 계산을 지워도
      // 통과할 수 있다(Codex 28회차).
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(568 * 3, 320 * 3);
      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      expect(tester.takeException(), isNull);

      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      final map = tester.getRect(find.byKey(const Key('koreaMap')));
      // 판이 지도 위젯 영역보다 위로 삐져나가면 머리글을 누를 수 없다.
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(map.bottom + 90));

      // 닫기와 지역 목록은 스크롤 없이 눌려야 한다.
      await tester.tap(find.byKey(const Key('insetList')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insetRegionList')), findsOneWidget);
    });

    testWidgets('좁은 화면 + 큰 글꼴에서도 넘치지 않는다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      expect(tester.takeException(), isNull);

      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      expect(panel.top, greaterThanOrEqualTo(0),
          reason: '판이 위로 밀려 나갔다');
    });

    testWidgets('가로에서 판을 펼치면 검색줄을 감추고 닫으면 돌아온다',
        (tester) async {
      // 568px 폭에 검색줄과 390px 판을 함께 두면 검색줄이 39px 넘친다.
      // 판에는 자체 지역 목록이 있으므로 펼친 동안만 감춘다(Codex 28회차).
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(568 * 3, 320 * 3);

      await openApp(tester, null, showDiagnostics: false);
      expect(find.byKey(const Key('searchBar')), findsOneWidget);

      await openPanel(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('searchBar')), findsNothing,
          reason: '가로에서 판과 검색줄이 함께 있으면 넘친다');

      await tester.tap(find.byKey(const Key('insetClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('searchBar')), findsOneWidget,
          reason: '판을 닫았는데 검색줄이 안 돌아온다');
    });

    testWidgets('세로 + 큰 글꼴에서 검색줄과 판이 겹치지 않는다', (tester) async {
      // 세로에서는 검색줄을 그대로 두므로 세로로 비켜 서야 한다.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      expect(tester.takeException(), isNull);

      // **글자가 아니라 검색줄 전체**를 잰다.
      final search = tester.getRect(find.byKey(const Key('searchBar')));
      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      expect(search.bottom, lessThanOrEqualTo(panel.top),
          reason: '검색줄이 인셋 판을 침범한다');
    });

    testWidgets('스크롤한 뒤에도 탭이 정확하다', (tester) async {
      // 판이 스크롤되면 캔버스가 화면에서 옮겨간다. 로컬 좌표는 그대로지만
      // 실제로 눌러 확인한다(Codex 28회차).
      //
      // **가로 화면이 아니라 좁은 세로 화면에서 잰다.** 가로 320 높이에서는
      // 판이 너무 짧아 스크롤해도 캔버스가 거의 안 보인다 — 그 조건에서는
      // `지역 목록` 이 실질적인 경로다(아래 별도 테스트).
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320 * 3, 568 * 3);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      await pick(tester, 'daegu');

      await tester.drag(
          find.byKey(const Key('insetPanel')), const Offset(0, -24));
      await tester.pumpAndSettle();

      // **보이는 지역을 찾아 누른다.** 판이 짧으면 캔버스 대부분이 잘려 있어
      // 특정 지역을 겨냥하면 테스트가 성립하지 않는다.
      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      final inset = resolveInset(
        kInsetDefinitions.firstWhere((d) => d.id == 'daegu'),
        realMap,
      );
      Region? target;
      Offset? point;
      for (final r in inset.regions) {
        final p = canvasPointOf(tester, 'daegu', r);
        if (panel.contains(p)) {
          target = r;
          point = p;
          break;
        }
      }
      expect(target, isNotNull,
          reason: '스크롤 뒤 보이는 지역이 하나도 없어 테스트가 성립하지 않는다');

      await tester.tapAt(point!);
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget,
          reason: '스크롤 뒤 탭이 빗나갔다');
      expect(find.text(target!.name), findsWidgets,
          reason: '스크롤 뒤 다른 지역이 열렸다');
    });

    testWidgets('가로 화면에서는 좌우로 배치해 캔버스가 온전히 보인다',
        (tester) async {
      // 세로로 쌓으면 판 높이가 160 남짓이라 캔버스가 거의 다 잘려 **시각
      // 인셋을 쓸 수 없다.** 목록은 *접근* 경로일 뿐 "한눈에 본다" 는 *표시*
      // 를 대신하지 못한다 — 그것이 인셋이 푸는 문제다(Codex 28회차).
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(568 * 3, 320 * 3);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);

      expect(find.byKey(const Key('insetWide')), findsOneWidget,
          reason: '가로인데 세로 배치다');

      // 캔버스가 판 안에 **온전히** 들어와야 한다.
      final panel = tester.getRect(find.byKey(const Key('insetPanel')));
      final canvas =
          tester.getRect(find.byKey(const Key('insetCanvas:capital')));
      expect(panel.contains(canvas.topLeft), isTrue, reason: '캔버스 위가 잘렸다');
      expect(panel.contains(canvas.bottomRight), isTrue,
          reason: '캔버스 아래가 잘렸다');
      // **크기가 줄지 않아야 한다.** 부모 제약에 눌리면 확대율이 떨어져
      // 부산 중구가 다시 5px 대로 내려간다(Codex 28회차).
      expect(canvas.size, kInsetCanvasSize,
          reason: '가로에서 캔버스가 눌렸다');

      // 구역 선택과 캔버스 탭이 스크롤 없이 동작해야 한다.
      await pick(tester, 'daegu');
      await tester.tapAt(canvasPointOf(tester, 'daegu', regionOf('27110')));
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget);
    });

    testWidgets('가로 화면에서도 지역 목록이 스크롤 없이 열린다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(568 * 3, 320 * 3);

      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      await pick(tester, 'daegu');

      await tester.tap(find.byKey(const Key('insetList')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insetRegionList')), findsOneWidget);

      // 목록은 이름순이라 중구가 마지막이다 — 짧은 시트에서는 아직
      // 만들어지지 않는다. 먼저 나오는 남구로 확인한다.
      await tester.tap(find.byKey(const Key('insetRow:27200')));
      await tester.pumpAndSettle();
      expect(find.text('지역 긁기'), findsOneWidget);
    });

    testWidgets('릴리스 구성에서도 인셋이 정상이다', (tester) async {
      await openApp(tester, null, showDiagnostics: false);
      await openPanel(tester);
      await pick(tester, 'busan');
      expect(find.byKey(const Key('insetCanvas:busan')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 인셋 캔버스를 **실제로 그려진 픽셀**로 떠 온다.
///
/// painter 에 무엇을 넘겼는지만 검사하면 색을 안 칠해도 통과한다.
/// `toImage` 는 위젯 테스트의 가짜 async 큐에서 끝나지 않으므로 `runAsync`
/// 안에서 부른다 — 안에 `pump` 는 넣지 않는다.
Future<Uint8List> _capture(WidgetTester tester, String insetId) async {
  final finder = find.byKey(Key('insetCanvas:$insetId'));
  expect(finder, findsOneWidget);
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(finder);
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
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
