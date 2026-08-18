import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_painter.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';
import 'package:mapscratch/region_description.dart';
import 'package:mapscratch/settings_store.dart';

/// M6 랜드마크 갤러리.
///
/// **앱을 통째로 띄워 하단 탭으로 들어간다.** 갤러리만 따로 만들어 검사하면
/// 셸이 스냅샷을 어떻게 넘기는지, 카드가 어떤 경로로 팝업을 여는지가 바뀌어도
/// 통과한다 — 기존 335개가 전부 지도 탭에서만 열기 때문에 이번엔
/// "기존 테스트가 안 깨졌다" 가 안전 신호가 못 된다(Codex 23회차).
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

  /// 경주시(첨성대). 랜드마크가 있는 지역이다.
  const gyeongju = '47130';

  /// 의성군. **랜드마크가 없는** 지역이라 갤러리에 아예 나오지 않는다.
  const uiseong = '47730';

  String saved(Iterable<String> ids) {
    var snap = CollectionSnapshot.empty;
    for (final id in ids) {
      snap = snap.collect(CollectedUnit(
        scratchUnitId: id,
        collectedAtUtc: DateTime.parse('2026-08-14T15:30:00Z'),
        utcOffsetMinutes: 540, // 한국 → 현지로는 8월 15일
      ));
    }
    return encodeCollection(snap);
  }

  int mapLoads = 0;
  int storeOpens = 0;

  Future<void> openApp(
    WidgetTester tester,
    String? stored, {
    CollectionLoadStatus status = CollectionLoadStatus.ok,
  }) async {
    mapLoads = 0;
    storeOpens = 0;
    await tester.pumpWidget(MapScratchApp(
      settingsOpener: () async => SettingsStore(_MemSettings()),
      mapLoader: () async {
        mapLoads++;
        return realMap;
      },
      storeOpener: () async {
        storeOpens++;
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

  Future<void> goGallery(WidgetTester tester) async {
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();
  }

  Future<void> goMap(WidgetTester tester) async {
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
  }

  /// 갤러리를 끌어 [target] 이 **화면 안에 온전히** 올 때까지 찾는다.
  ///
  /// 두 가지를 다 해야 한다. ① `sweep` 뒤에는 이미 바닥이라 먼저 맨 위로
  /// 되돌린다 ② 카드가 화면 아래쪽에 걸쳐 있으면 `tap` 이 빗나가므로
  /// 중심이 안전한 높이에 올 때까지 조금 더 끈다.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    final scroll = find.byKey(const Key('galleryScroll'));
    for (var i = 0; i < 60; i++) {
      await tester.drag(scroll, const Offset(0, 400));
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < 60 && target.evaluate().isEmpty; i++) {
      await tester.drag(scroll, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(target, findsWidgets, reason: '끝까지 끌어도 나오지 않았다');

    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (var i = 0; i < 10; i++) {
      final c = tester.getCenter(target);
      if (c.dy < height - 140 && c.dy > 60) return;
      await tester.drag(scroll, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
  }

  /// 갤러리를 **바닥까지 훑으면서** 매 화면에서 [check] 를 돌린다.
  ///
  /// `SliverList` 는 화면에 보이는 줄만 만든다. 한 화면만 보고 검사하면
  /// 37개 중 두어 개만 확인하고 통과한다 — 처음 쓴 유출 테스트가 정확히
  /// 그랬다. 이 프로젝트에서 반복된 "테스트가 약했다" 와 같은 유형이다.
  ///
  /// **끌기 횟수로 끝내지 않고 `maxScrollExtent` 로 끝낸다.** 횟수 상한으로
  /// 빠져나오면 항목이 늘었을 때 조용히 덜 훑고 통과한다(Codex 24회차).
  /// 한 번에 뷰포트의 80%만 움직여 검사 화면이 서로 겹치게 한다.
  Future<Set<String>> sweep(WidgetTester tester, void Function() check) async {
    final scroll = find.byKey(const Key('galleryScroll'));
    ScrollPosition position() => tester
        .state<ScrollableState>(find.descendant(
            of: scroll, matching: find.byType(Scrollable)))
        .position;

    final seen = <String>{};
    void record() {
      check();
      for (final id in kPlannedLandmarks) {
        if (find.byKey(Key('galleryCard:$id')).evaluate().isNotEmpty) {
          seen.add(id);
        }
      }
    }

    position().jumpTo(0);
    await tester.pumpAndSettle();
    record();

    while (position().pixels < position().maxScrollExtent) {
      final step = position().viewportDimension * 0.8;
      position().jumpTo(
          (position().pixels + step).clamp(0.0, position().maxScrollExtent));
      await tester.pumpAndSettle();
      record();
    }

    expect(position().extentAfter, lessThan(1.0),
        reason: '바닥까지 훑지 못했다');
    return seen;
  }

  group('목록 구성', () {
    test('랜드마크 세 집합이 정확히 일치한다', () {
      // 갤러리 목록의 단일 원본이다. 하나라도 어긋나면 `!` 가 터지거나
      // 칸이 비는데, 런타임까지 가기 전에 여기서 잡는다.
      expect(kPlannedLandmarks.length, 37);
      expect(kLandmarkArt.keys.toSet(), kPlannedLandmarks);
      expect(kLandmarkDescription.keys.toSet(), kPlannedLandmarks);
    });

    testWidgets('랜드마크가 없는 지역은 갤러리에 나오지 않는다', (tester) async {
      // 232개 전부가 아니라 37개만 늘어놓는다는 결정(2026-08-18).
      await openApp(tester, saved([uiseong]));
      await goGallery(tester);

      // 훑는 내내 한 번도 나오지 않아야 한다. 한 화면만 보면 당연히 없다.
      await sweep(tester, () {
        expect(find.byKey(const Key('galleryCard:$uiseong')), findsNothing);
      });
      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));
      expect(find.byKey(const Key('galleryCard:$gyeongju')), findsOneWidget);
    });
  });

  group('미수집 유출 금지', () {
    testWidgets('빈 상태에서 랜드마크 이름과 설명이 하나도 없다', (tester) async {
      // **"가리고 긁을 때 공개" 결정의 핵심이다.** 이름 한 단어도 힌트가 된다.
      await openApp(tester, null);
      await goGallery(tester);

      final seen = await sweep(tester, () {
        for (final id in kPlannedLandmarks) {
          expect(find.text(kLandmarkDescription[id]!), findsNothing,
              reason: '미수집인데 설명이 새어 나왔다: $id');

          final artName = kLandmarkArt[id]!.name;
          // **`독도` 만 예외다.** 랜드마크 이름과 지역명이 같은 유일한 항목이라
          // 문자열 부재로 검사하면 위양성이 난다 — 지역명은 지도와 검색에 이미
          // 공개돼 있어 가리는 대상이 아니다(Codex 23회차).
          if (artName == '독도') continue;
          expect(find.text(artName), findsNothing,
              reason: '미수집인데 랜드마크 이름이 새어 나왔다: $id');
        }
      });
      expect(seen.length, 37, reason: '검사하지 못하고 지나친 칸이 있다');
    });

    testWidgets('잠금 카드에는 공개 전용 위젯이 하나도 없다', (tester) async {
      // 문자열 검사만으로는 `독도` 같은 예외를 덮지 못한다. 공개 카드에만
      // 붙는 key 가 없다는 것으로 구조적으로 확인한다.
      await openApp(tester, null);
      await goGallery(tester);

      await sweep(tester, () {
        expect(find.byKey(const Key('galleryLandmarkName')), findsNothing);
        expect(find.byKey(const Key('galleryDescription')), findsNothing);
      });
    });

    testWidgets('수집한 것만 공개되고 나머지는 잠긴 채로 있다', (tester) async {
      await openApp(tester, saved([gyeongju]));
      await goGallery(tester);

      // **끝까지 훑으며 공개된 이름을 모은다.** 한 화면만 보고 "하나뿐" 이라고
      // 하면 화면 밖에서 새는 것을 놓친다.
      final revealed = <String>{};
      await sweep(tester, () {
        for (final e in find.byKey(const Key('galleryLandmarkName')).evaluate()) {
          revealed.add((e.widget as Text).data!);
        }
      });
      expect(revealed, {'첨성대'}, reason: '수집한 하나만 공개돼야 한다');

      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));
      expect(find.text(kLandmarkDescription[gyeongju]!), findsOneWidget);
      expect(find.text('2026년 8월 15일'), findsOneWidget,
          reason: '수집 당시 오프셋으로 푼 날짜여야 한다');
    });
  });

  group('통합 긁기 단위', () {
    // 서울 `11000` · 제주 `50000` 은 **지역명이 시도명과 같다.**
    // 그대로 이으면 "제주특별자치도 제주특별자치도" 가 된다 —
    // 실기기에서 눈으로 보고서야 찾았고, 단위 테스트도 PNG 도 못 잡았다.
    // `main.dart` 팝업과 `scratch_page.dart` 는 이미 이 규칙을 지키고 있었다.
    const jeju = '50000';
    const seoul = '11000';

    testWidgets('수집 카드에 시도명을 두 번 쓰지 않는다', (tester) async {
      await openApp(tester, saved([jeju, seoul]));
      await goGallery(tester);

      await sweep(tester, () {
        expect(find.textContaining('제주특별자치도 제주특별자치도'), findsNothing,
            reason: '시도명이 두 번 나왔다');
        expect(find.textContaining('서울특별시 서울특별시'), findsNothing,
            reason: '시도명이 두 번 나왔다');
      });
    });

    testWidgets('잠금 카드도 같은 말을 두 줄로 쓰지 않는다', (tester) async {
      await openApp(tester, null);
      await goGallery(tester);
      await scrollTo(tester, find.byKey(const Key('galleryCard:$jeju')));

      final texts = find
          .descendant(
              of: find.byKey(const Key('galleryCard:$jeju')),
              matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .where((t) => t == '제주특별자치도')
          .length;
      expect(texts, 1, reason: '같은 이름이 두 줄로 나왔다');
    });
  });

  group('진행 표시', () {
    testWidgets('빈 상태는 0/37 이다', (tester) async {
      await openApp(tester, null);
      await goGallery(tester);
      expect(find.text('0/37'), findsOneWidget);
    });

    testWidgets('랜드마크 없는 지역만 수집해도 0/37 이다', (tester) async {
      // `snapshot.length` 를 그대로 쓰면 1/37 이 된다.
      await openApp(tester, saved([uiseong]));
      await goGallery(tester);
      expect(find.text('0/37'), findsOneWidget);
    });

    testWidgets('알 수 없는 ID 는 세지 않는다', (tester) async {
      // 저장은 보존하되 표시에서는 뺀다는 M1 계약이 여기에도 적용된다.
      await openApp(tester, saved(['99999']));
      await goGallery(tester);
      expect(find.text('0/37'), findsOneWidget);
    });

    testWidgets('랜드마크를 수집하면 1/37 이 된다', (tester) async {
      await openApp(tester, saved([gyeongju]));
      await goGallery(tester);
      expect(find.text('1/37'), findsOneWidget);
    });
  });

  group('탭 전환', () {
    testWidgets('지도와 저장소를 다시 읽지 않는다', (tester) async {
      // 갤러리가 저장소를 따로 열면 스냅샷이 둘로 갈라진다.
      await openApp(tester, null);
      expect(mapLoads, 1);
      expect(storeOpens, 1);

      await goGallery(tester);
      await goMap(tester);
      await goGallery(tester);

      expect(mapLoads, 1, reason: '탭 전환이 지도를 다시 읽었다');
      expect(storeOpens, 1, reason: '탭 전환이 저장소를 다시 열었다');
    });

    testWidgets('갤러리 스크롤 위치가 탭을 오가도 남는다', (tester) async {
      // **`IndexedStack` 이어야 통과한다.** 탭마다 화면을 조건부로 갈아 끼우면
      // 갤러리 `Scrollable` 의 State 가 폐기돼 맨 위로 되돌아간다.
      // `_tc`·`_cache` 는 `_MapSpikePageState` 필드라 조건부 교체로도 살아남으므로
      // identity 검사만으로는 이 차이를 잡지 못한다 — 실제로 심어 보고 알았다.
      await openApp(tester, null);
      await goGallery(tester);
      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));
      final before = tester.getCenter(
          find.byKey(const Key('galleryCard:$gyeongju')));

      await goMap(tester);
      await goGallery(tester);

      expect(find.byKey(const Key('galleryCard:$gyeongju')), findsWidgets,
          reason: '탭을 오가자 갤러리가 맨 위로 되돌아갔다');
      expect(tester.getCenter(find.byKey(const Key('galleryCard:$gyeongju'))),
          before,
          reason: '스크롤 위치가 유지되지 않았다');
    });

    testWidgets('지도 확대·이동 상태와 Picture 캐시가 보존된다', (tester) async {
      await openApp(tester, null);

      final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer));
      final tc = viewer.transformationController!;
      tc.value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 1, 1);
      await tester.pump();

      final painter = tester
          .widget<CustomPaint>(find.byKey(const Key('koreaMap')))
          .painter as KoreaMapPainter;

      await goGallery(tester);
      await goMap(tester);

      final after = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer));
      expect(identical(after.transformationController, tc), isTrue,
          reason: '탭 전환이 지도 State 를 새로 만들었다');
      expect(after.transformationController!.value, tc.value,
          reason: '확대·이동이 초기화됐다');

      final painterAfter = tester
          .widget<CustomPaint>(find.byKey(const Key('koreaMap')))
          .painter as KoreaMapPainter;
      expect(identical(painterAfter.cache, painter.cache), isTrue,
          reason: 'Picture 캐시가 버려졌다');
    });
  });

  group('팝업 경로', () {
    testWidgets('카드를 누르면 지역 팝업이 열린다', (tester) async {
      await openApp(tester, saved([gyeongju]));
      await goGallery(tester);
      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));

      await tester.tap(find.byKey(const Key('galleryCard:$gyeongju')));
      await tester.pumpAndSettle();

      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('저장할 수 없는 상태면 긁기 화면으로 못 간다', (tester) async {
      // 갤러리가 팝업을 자체 구현하면 이 게이트를 지나치게 된다 —
      // 게이트는 `_openRegion` 안에 있다(Codex 23회차 High).
      await openApp(tester, null,
          status: CollectionLoadStatus.unsupportedVersion);
      await goGallery(tester);
      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));

      await tester.tap(find.byKey(const Key('galleryCard:$gyeongju')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지역 긁기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('더 새로운 버전'), findsOneWidget);
      expect(find.text('긁기 완료'), findsNothing);
    });
  });

  group('접근성', () {
    testWidgets('잠금 카드를 스크린 리더로 실행할 수 있다', (tester) async {
      // `excludeSemantics: true` 는 자식 `InkWell` 의 탭 액션까지 지운다.
      // 라벨만 검사하면 **읽히지만 눌리지 않는 카드**를 놓친다(Codex 24회차).
      // **`addTearDown` 으로 미루면 안 된다.** 핸들 검사가 그보다 먼저 돈다.
      final handle = tester.ensureSemantics();

      await openApp(tester, null);
      await goGallery(tester);

      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));
      final node =
          tester.getSemantics(find.byKey(const Key('galleryCard:$gyeongju')));

      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: '스크린 리더가 읽어 주고도 실행할 수 없다');
      // 가리는 것은 랜드마크뿐이다. 지역명·시도명은 읽혀야 한다.
      expect(node.label, contains('경주시'));
      expect(node.label, contains('경상북도'));
      expect(node.label, isNot(contains('첨성대')),
          reason: '접근성 라벨로 랜드마크 이름이 샜다');
      handle.dispose();
    });
  });

  group('수집 반영', () {
    testWidgets('지도에서 긁으면 갤러리가 곧바로 따라온다', (tester) async {
      // 이번 기능의 핵심 상태 경로다. 갤러리가 스냅샷을 자기 State 에 복사하면
      // 여기서 0/37 에 머문다(Codex 23회차 High · 24회차 테스트 누락 지적).
      await openApp(tester, null);
      await goGallery(tester);
      expect(find.text('0/37'), findsOneWidget);

      await goMap(tester);
      await tester.tap(find.text('지역 검색'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '경주시');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '경주시').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('지역 긁기'));
      await tester.pumpAndSettle();

      // 임계치를 넘길 때까지 실제로 훑는다 — `collection_flow_test` 와 같은 방식.
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (var y = 40.0; y < size.height - 40; y += 12) {
        await tester.dragFrom(Offset(20, y), Offset(size.width - 40, 0));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('지도로 돌아가기'), findsOneWidget,
          reason: '긁기가 완료되지 않아 수집 반영을 볼 수 없다');
      await tester.tap(find.text('지도로 돌아가기'));
      await tester.pumpAndSettle();

      await goGallery(tester);
      expect(find.text('1/37'), findsOneWidget,
          reason: '수집이 갤러리에 반영되지 않았다');
    });
  });

  group('레이아웃', () {
    testWidgets('360×640 에서 지도 폭이 현재 허용선 아래로 내려가지 않는다',
        (tester) async {
      // `NavigationBar` 가 세로 공간을 가져가면 지도 폭까지 줄어든다
      // (`_buildMap` 이 `c.maxHeight` 에 맞춰 축소한다). 같은 조건에서 재 보면
      // 360×640 에서 278.1 → **215.3 (−22.6%)**, 320×568 에서 221.6 → 158.7 이다.
      //
      // **이 테스트는 이미 일어난 축소를 되돌리지 않는다.** 지금 값을 바닥으로
      // 못박아 하단에 무엇을 더 얹을 때 조용히 지나가지 않게 할 뿐이다
      // (Codex 24회차). `200` 은 제품 기준이 아니라 현재값 215.3 에 여유를 둔
      // 임의값이며, 진짜 원인은 릴리스에도 나오는 S1 진단 UI(`_StatsBar`·
      // `_Controls`)다 — **M8 인셋 전에 정리**하기로 기록했다.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(360 * 3, 640 * 3);
      await openApp(tester, null);

      final size = tester.getSize(find.byKey(const Key('koreaMap')));
      expect(size.width, greaterThan(200),
          reason: '지도가 더 좁아졌다 — 하단에 얹은 것을 다시 본다');
    });

    testWidgets('좁은 화면에서 마지막 카드까지 닿는다', (tester) async {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320 * 3, 568 * 3);
      await openApp(tester, null);
      await goGallery(tester);

      // **37칸 전부에 실제로 닿아야 한다.**
      final seen = await sweep(tester, () {});
      expect(seen.length, 37, reason: '스크롤로 닿지 못한 칸이 있다');
      expect(tester.takeException(), isNull);
    });

    testWidgets('큰 글꼴에서 글자가 잘리지 않는다', (tester) async {
      // 고정 높이·고정 비율이 큰 글꼴에서 글자를 잘랐던 전례가 있다(M9).
      // 큰 글꼴에서는 1열로 내려간다.
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openApp(tester, saved([gyeongju]));
      await goGallery(tester);
      await scrollTo(tester, find.byKey(const Key('galleryCard:$gyeongju')));

      expect(tester.takeException(), isNull);
      expect(find.text('첨성대'), findsOneWidget);
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
