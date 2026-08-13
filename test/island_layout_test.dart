import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/island_layout.dart';
import 'package:mapscratch/map_data.dart';

Float32List _square(double x, double y, double side) => Float32List.fromList(
    [x, y, x + side, y, x + side, y + side, x, y + side]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('재배치 대상 판정', () {
    test('링이 하나면 재배치하지 않는다', () {
      // 섬이 하나뿐이면 모을 것이 없다.
      expect(
          needsPacking([_square(0, 0, 1)], const Rect.fromLTRB(0, 0, 100, 100)),
          isFalse);
    });

    test('육지가 bounds 대비 충분하면 재배치하지 않는다', () {
      final rings = [_square(0, 0, 8), _square(0, 0, 8)];
      expect(needsPacking(rings, const Rect.fromLTRB(0, 0, 10, 10)), isFalse);
    });

    test('육지가 임계치 미만이면 재배치한다', () {
      final rings = [_square(0, 0, 1), _square(50, 50, 1)];
      expect(needsPacking(rings, const Rect.fromLTRB(0, 0, 100, 100)), isTrue);
    });
  });

  group('재배치', () {
    test('섬 개수와 모양이 보존된다', () {
      // 옮기기만 한다. 배율을 바꾸면 섬끼리의 크기 감각이 깨진다.
      final rings = [_square(0, 0, 10), _square(500, 500, 6)];
      final layout = packIslands(rings);
      expect(layout.placements.length, 2);
      for (final p in layout.placements) {
        expect(p.ring.length, isIn([8]));
      }
    });

    test('재배치가 육지 밀도를 크게 높인다', () {
      // 멀리 떨어진 섬 4개. 원래 bounds 대비 육지는 1% 미만이다.
      final rings = [
        _square(0, 0, 5),
        _square(300, 10, 5),
        _square(20, 280, 5),
        _square(290, 290, 5),
      ];
      final layout = packIslands(rings);
      expect(layout.fillRatio, greaterThan(0.4));
    });

    test('결과가 정사각형에 가깝다', () {
      // 화면 비율과 무관하게 잘 들어가야 한다.
      final rings = [for (var i = 0; i < 9; i++) _square(i * 100.0, 0, 7)];
      final layout = packIslands(rings);
      final ratio = layout.bounds.width / layout.bounds.height;
      expect(ratio, greaterThan(0.4));
      expect(ratio, lessThan(2.5));
    });

    test('빈 입력에서 터지지 않는다', () {
      final layout = packIslands([]);
      expect(layout.placements, isEmpty);
      expect(layout.bounds, Rect.zero);
    });

    test('가장 큰 섬은 bbox 가 아니라 면적으로 고른다', () {
      // 가늘고 긴 띠는 bbox 가 커도 면적이 작다.
      final thin = Float32List.fromList([0, 0, 100, 95, 100, 100, 5, 5]);
      final blob = _square(0, 0, 30);
      final layout = packIslands([thin, blob]);
      final largest = buildLargestIslandPath(layout);
      final b = largest.getBounds();
      expect(b.width, closeTo(30, 0.5));
      expect(b.height, closeTo(30, 0.5));
    });
  });

  group('실제 에셋', () {
    late MapData data;
    setUpAll(() async => data = await MapData.load());

    test('재배치 대상은 실측 4개 지역이다', () {
      // 옹진군 0.93% · 신안군 5.44% · 안산시단원구 8.31% · 여수시 9.11%
      final hits = <String>[];
      for (final r in data.regions) {
        if (needsPacking(r.rings, r.bounds)) hits.add(r.code);
      }
      expect(hits.toSet(), {'28720', '12870', '41273', '12130'});
    });

    test('옹진군 재배치가 육지 밀도를 40% 이상으로 올린다', () {
      final r = data.regions.firstWhere((x) => x.code == '28720');
      final layout = packIslands(r.rings);
      debugPrint('옹진군 육지비율 0.93% → '
          '${(layout.fillRatio * 100).toStringAsFixed(1)}%');
      expect(layout.fillRatio, greaterThan(0.40));
      expect(layout.placements.length, r.rings.length);
    });

    test('신안군 링 42개가 모두 배치된다', () {
      // 하나라도 빠지면 그 섬은 긁을 수 없게 되고 65% 에 도달하지 못할 수 있다.
      final r = data.regions.firstWhere((x) => x.code == '12870');
      final layout = packIslands(r.rings);
      expect(layout.placements.length, r.rings.length);
    });
  });
}
