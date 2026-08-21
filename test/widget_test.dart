import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('지도 에셋이 긁기 단위 193개와 시도 16개를 담고 있다', () async {
    final data = await MapData.load();
    expect(data.regions.length, 193);
    expect(data.sidoNames.length, 16);
    expect(data.sidoLines.length, 16);
    expect(data.vertexCount, greaterThan(10000));

    // **모든 시도에 색이 있어야 한다.**
    //
    // 예전에는 배열 인덱스 범위만 봤는데, 그러면 순서가 바뀌어도 통과한다.
    // 실제로 시도 외곽선 색이 전부 어긋난 버그가 그렇게 지나갔다(S1).
    // 이름으로 찾으므로 이름이 빠졌는지를 본다.
    for (final name in data.sidoNames) {
      expect(kSidoColorByName[name], isNotNull, reason: '색이 없다: $name');
    }
    expect(kSidoColorByName.length, data.sidoNames.length,
        reason: '색표에 지도에 없는 시도가 있다');

    for (final r in data.regions) {
      expect(r.sido, inInclusiveRange(0, data.sidoNames.length - 1));
      expect(r.bounds.isEmpty, isFalse);

      // **길이를 5로 못 박지 않는다.** `scratchUnitId` 는 불투명 ID 계약이라
      // 자릿수에 의미를 두지 않는다. 통계청 코드 5자리와 합성 ID `11000`·`50000`,
      // 독도 `DK001` 이 우연히 전부 5문자일 뿐이고, 다음에 신설하는 단위가
      // 그럴 이유는 없다.
      //
      // 대신 **문자 집합은 계약으로 둔다.** 저장·URL·서버 DTO 로 그대로 나가는
      // 값이라 공백·제어문자·구분자가 섞이면 조용히 깨진다. 길이를 뺀 자리를
      // "비어 있지 않다" 로만 채우면 `DK 001` 같은 값이 통과한다 (Codex 14회차).
      expect(r.scratchUnitId, matches(RegExp(r'^[A-Za-z0-9]+$')),
          reason: '영숫자만 쓴다: "${r.scratchUnitId}"');
    }

    // 코드는 유일해야 한다 — 긁은 상태를 코드로 저장하기 때문
    expect(data.regions.map((r) => r.scratchUnitId).toSet().length, 193);
  });

  test('모든 링이 닫혀 있다', () async {
    // `Region.distanceTo()` 는 연속한 정점 쌍만 훑는다. 링이 닫혀 있지 않으면
    // **마지막→첫 정점 변이 거리 계산에서 통째로 빠져** 그 변 쪽 탭 허용 오차가
    // 사라진다. 원본 GeoJSON 은 전부 닫혀 오지만, 독도처럼 손으로 만들어 넣는
    // 지역이 생기면 이 불변식이 조용히 깨진다 — 실제로 한 번 깨뜨렸다.
    final data = await MapData.load();
    final open = <String>[];
    for (final r in data.regions) {
      for (final ring in r.rings) {
        final n = ring.length;
        if (ring[0] != ring[n - 2] || ring[1] != ring[n - 1]) {
          open.add('${r.scratchUnitId} ${r.name}');
        }
      }
    }
    expect(open, isEmpty);
  });

  test('지도 비율이 실제 국토에 가깝다', () async {
    final data = await MapData.load();
    final ratio = data.size.height / data.size.width;
    expect(ratio, greaterThan(1.15));
    expect(ratio, lessThan(1.40));
  });

  testWidgets('앱이 뜨고 지도를 그린다', (tester) async {
    // 에셋 로딩은 실제 I/O 라 testWidgets 의 FakeAsync 안에서는 완료되지 않는다.
    // runAsync 로 감싸야 Future 가 진행된다.
    // 또 pumpAndSettle 은 쓸 수 없다 — FrameStats 가 프레임마다 notifyListeners 를
    // 호출해 통계 바가 계속 리빌드되므로 트리가 영원히 안정되지 않는다.
    await tester.runAsync(() async {
      await tester.pumpWidget(MapScratchApp(settingsOpener: _testSettings));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // **기다림이 두 번이다.** 설정을 읽어 테마를 정한 뒤에야 지도 로딩이
      // 시작된다(M12). 어두운 바다를 고른 사용자에게 밝은 지도가 먼저
      // 번쩍이지 않게 하려고 일부러 순서를 준 것이다.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('벤치마크 시작'), findsOneWidget);
      expect(find.textContaining('지역 193개'), findsOneWidget);
    });
  });

  testWidgets('지도 밖 빈 공간이 보이지 않게 이동이 제한된다', (tester) async {
    // boundaryMargin 이 넉넉하면 지도를 화면 밖으로 끌어낼 수 있고,
    // minScale 이 1 미만이면 축소했을 때 지도가 화면보다 작아진다.
    // 둘 다 배경만 남는 빈 공간을 만든다.
    // 에셋 로딩은 실제 I/O 라 `runAsync` 로 감싸야 진행된다.
    // `pumpAndSettle` 은 FrameStats 가 프레임마다 알리므로 정착하지 않는다.
    await tester.runAsync(() async {
      await tester.pumpWidget(MapScratchApp(settingsOpener: _testSettings));
      // 설정 → 지도 순서라 기다림이 두 번이다.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      final v =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(v.minScale, 1.0, reason: '배율 1이 꽉 찬 상태다. 더 줄이면 빈 공간이 생긴다');
      expect(v.boundaryMargin, EdgeInsets.zero,
          reason: '여백을 주면 지도를 화면 밖으로 끌어낼 수 있다');
      expect(v.maxScale, greaterThan(1.0));

      // **`InteractiveViewer` 의 자식은 지도여야 한다.**
      //
      // 자식이 뷰포트 크기(`Center` 등)가 되면 `boundaryMargin` 이 제한하는
      // 대상이 지도가 아니라 뷰포트가 되어, 크게 확대해 끌면 지도가 화면 밖으로
      // 나간다. M14 에서 실제로 이렇게 깨뜨렸다 (Codex 13회차 지적).
      final child = v.child;
      expect(child, isA<SizedBox>(),
          reason: 'InteractiveViewer 의 자식은 지도 크기여야 한다');
      final box = child as SizedBox;
      expect(box.width, isNotNull);
      expect(box.height, isNotNull);
      expect(box.width! < tester.view.physicalSize.width, isTrue,
          reason: '자식이 뷰포트 전체 크기면 이동 경계가 지도 기준이 아니다');
    });
  });
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
