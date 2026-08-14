import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('지도 에셋이 긁기 단위 231개와 시도 16개를 담고 있다', () async {
    final data = await MapData.load();
    expect(data.regions.length, 231);
    expect(data.sidoNames.length, 16);
    expect(data.sidoLines.length, 16);
    expect(data.vertexCount, greaterThan(10000));

    // 시도 인덱스가 색 배열 범위를 벗어나면 렌더에서 터진다
    for (final r in data.regions) {
      expect(r.sido, inInclusiveRange(0, kSidoColors.length - 1));
      expect(r.scratchUnitId.length, 5);
      expect(r.bounds.isEmpty, isFalse);
    }

    // 코드는 유일해야 한다 — 긁은 상태를 코드로 저장하기 때문
    expect(data.regions.map((r) => r.scratchUnitId).toSet().length, 231);
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
      await tester.pumpWidget(const MapScratchApp());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('벤치마크 시작'), findsOneWidget);
      expect(find.textContaining('지역 231개'), findsOneWidget);
    });
  });
}
