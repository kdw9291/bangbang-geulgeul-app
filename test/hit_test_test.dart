import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/hit_test.dart';
import 'package:mapscratch/map_data.dart';

/// [r] 안쪽에 확실히 들어가는 점을 찾는다.
/// 시군구는 오목하거나 섬으로 쪼개져 있어서 bounds 중심이 바깥일 수 있다.
Offset? interiorPoint(Region r) {
  final b = r.bounds;
  const grid = 24;
  for (var i = 1; i < grid; i++) {
    for (var j = 1; j < grid; j++) {
      final p = Offset(
        b.left + b.width * i / grid,
        b.top + b.height * j / grid,
      );
      if (r.path.contains(p)) return p;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  late RegionHitTester tester;

  setUpAll(() async {
    data = await MapData.load();
    tester = RegionHitTester(data.regions);
  });

  test('모든 시군구에서 내부 점을 찾을 수 있다', () {
    final missing = data.regions
        .where((r) => interiorPoint(r) == null)
        .map((r) => '${r.name}(${r.code})')
        .toList();
    expect(missing, isEmpty,
        reason: '내부 점을 못 찾은 지역은 폴리곤이 깨졌을 수 있다: $missing');
  });

  test('내부 점은 해당 지역으로 판정된다', () {
    final wrong = <String>[];
    for (final r in data.regions) {
      final p = interiorPoint(r);
      if (p == null) continue;
      final hit = tester.exact(p);
      if (hit?.code != r.code) {
        wrong.add('${r.name}(${r.code}) -> ${hit?.name ?? "없음"}');
      }
    }
    expect(wrong, isEmpty, reason: '오판정 ${wrong.length}건: $wrong');
  });

  test('바다를 찍으면 아무 지역도 나오지 않는다', () {
    // 지도 좌표계 바깥 (에셋은 원점 0 기준, 여백 10 포함)
    expect(tester.exact(const Offset(-50, -50)), isNull);
    expect(tester.exact(Offset(data.size.width + 50, data.size.height + 50)),
        isNull);
  });

  // Codex 검토 High #1 회귀 방지.
  // bounds 거리로 판정하면 옹진군 bounds(172×107km)가 먼 바다를 삼킨다.
  test('넓은 bounds 안이라도 폴리곤에서 멀면 판정되지 않는다', () {
    final widest = data.regions.reduce((a, b) =>
        (a.bounds.width * a.bounds.height) > (b.bounds.width * b.bounds.height)
            ? a
            : b);

    // 그 지역 bounds 안이면서 어떤 지역에도 속하지 않고, 폴리곤에서 먼 점을 찾는다
    Offset? far;
    final b = widest.bounds;
    for (var i = 1; i < 40 && far == null; i++) {
      for (var j = 1; j < 40; j++) {
        final p = Offset(b.left + b.width * i / 40, b.top + b.height * j / 40);
        if (tester.exact(p) != null) continue;
        if (widest.distanceTo(p) > 25) {
          far = p;
          break;
        }
      }
    }
    expect(far, isNotNull, reason: '검증용 먼 바다 점을 찾지 못했다');
    expect(widest.bounds.contains(far!), isTrue, reason: 'bounds 안이어야 의미가 있다');

    expect(tester.nearest(far, tolerance: 4.0), isNull,
        reason: '폴리곤에서 25km 넘게 떨어졌으므로 4km 허용으로는 잡히면 안 된다');
  });

  test('허용 오차는 폴리곤까지의 실제 거리로 판단한다', () {
    // 가장 작은 지역 경계에서 바깥으로 조금씩 나가며 거리와 판정을 대조한다
    final r = data.regions.reduce((a, b) =>
        (a.bounds.width * a.bounds.height) < (b.bounds.width * b.bounds.height)
            ? a
            : b);
    final center = r.bounds.center;
    expect(r.distanceTo(center), 0, reason: '내부 점은 거리 0이어야 한다');

    // 먼 곳은 거리도 크고 판정도 안 돼야 한다
    final away = Offset(center.dx + 200, center.dy + 200);
    expect(r.distanceTo(away), greaterThan(100));
    expect(tester.nearest(away, tolerance: 4.0)?.code, isNot(r.code));
  });

  test('허용 오차를 0 이하로 주면 정확 판정만 남는다', () {
    expect(tester.nearest(const Offset(-50, -50), tolerance: 0), isNull);

    // 내부 점은 허용 오차와 무관하게 여전히 판정돼야 한다
    final r = data.regions.first;
    final inside = interiorPoint(r);
    expect(inside, isNotNull);
    expect(tester.nearest(inside!, tolerance: 0)?.code, r.code);
  });

  // Codex 재검토 Low 회귀 방지.
  // Rect.contains 는 오른쪽·아래 경계를 제외하므로 후보 필터에 그대로 쓰면
  // 거리가 정확히 tolerance 인 점이 방향에 따라 다르게 처리된다.
  test('bounds 네 방향 모두에서 허용 오차 경계가 동일하게 동작한다', () {
    // 바다 한가운데 홀로 떨어진 지역을 고른다 — 이웃 간섭을 배제하기 위해
    final r = data.regions.firstWhere((x) => x.name == '울릉군',
        orElse: () => data.regions.first);
    final b = r.bounds;
    const t = 5.0;

    // 각 방향으로 bounds 에서 정확히 t 만큼 떨어진 점
    final probes = <String, Offset>{
      '왼쪽': Offset(b.left - t, b.center.dy),
      '오른쪽': Offset(b.right + t, b.center.dy),
      '위': Offset(b.center.dx, b.top - t),
      '아래': Offset(b.center.dx, b.bottom + t),
    };

    for (final e in probes.entries) {
      final p = e.value;
      final actual = r.distanceTo(p);
      // 후보 필터를 통과했다면, 실제 거리 기준 판정과 결과가 일치해야 한다
      final hit = tester.nearest(p, tolerance: t + 0.001);
      if (actual <= t) {
        expect(hit, isNotNull,
            reason: '${e.key}: 실제 거리 ${actual.toStringAsFixed(2)}km 는 허용 안인데 누락');
      }
      // 넉넉한 허용에서는 네 방향 모두 반드시 후보에 들어와야 한다
      expect(tester.nearest(p, tolerance: actual + 1.0), isNotNull,
          reason: '${e.key}: 실제 거리보다 큰 허용인데도 누락');
    }
  });

  test('화면 픽셀 허용 오차는 배율에 반비례한다', () {
    // 확대하면 화면 1px 이 덮는 지도 거리가 줄어야 한다
    final atOne = tapToleranceInMapUnits(
        mapUnitsPerWidgetPx: 1.36, viewerScale: 1, tolerancePx: 12);
    final atThree = tapToleranceInMapUnits(
        mapUnitsPerWidgetPx: 1.36, viewerScale: 3, tolerancePx: 12);
    expect(atThree, closeTo(atOne / 3, 1e-9));

    // 배율이 0이나 음수로 들어와도 터지지 않아야 한다
    expect(
        tapToleranceInMapUnits(mapUnitsPerWidgetPx: 1.36, viewerScale: 0),
        greaterThan(0));
  });

  test('해안선 바로 바깥 2km 는 잡아주고, 먼 바다는 잡지 않는다', () {
    // 최남단 지역(서귀포시) 남쪽은 열린 바다다.
    // bounds 가 아니라 **폴리곤에서** 2km 떨어진 점을 만들어야 의미가 있다.
    final south = data.regions
        .reduce((a, b) => a.bounds.bottom > b.bounds.bottom ? a : b);

    Offset? justOutside;
    for (var step = 0.5; step <= 3.0 && justOutside == null; step += 0.25) {
      for (var t = 0.05; t < 0.95; t += 0.02) {
        final x = south.bounds.left + south.bounds.width * t;
        final p = Offset(x, south.bounds.bottom + step);
        if (tester.exact(p) != null) continue;
        final d = south.distanceTo(p);
        if (d > 0.5 && d < 3.0) {
          justOutside = p;
          break;
        }
      }
    }

    expect(justOutside, isNotNull, reason: '해안 근처 바다 점을 찾지 못했다');
    expect(tester.exact(justOutside!), isNull, reason: '바다이므로 정확 판정은 없다');
    expect(south.distanceTo(justOutside), lessThan(3.0));

    final near = tester.nearest(justOutside, tolerance: 4.0);
    expect(near, isNotNull, reason: '폴리곤에서 3km 미만이므로 4km 허용에 잡혀야 한다');
    expect(near!.sido, data.sidoNames.indexOf('제주특별자치도'),
        reason: '최남단 해안 바로 밖에서 가장 가까운 것은 제주여야 한다');

    // 같은 방향으로 훨씬 멀어지면 잡히지 않아야 한다
    final farSea = Offset(justOutside.dx, south.bounds.bottom + 60.0);
    expect(tester.nearest(farSea, tolerance: 4.0), isNull);
  });

  // `nearest()` 는 exact 가 실패할 때만 폴리곤 거리를 재므로, 바다 탭이 최악이다.
  // 다도해 지역의 넓은 bounds 가 후보로 걸리면 링 전체를 훑는다.
  test('바다 탭(최악 경로) 판정 속도도 프레임 예산 안에 들어온다', () {
    final probes = <Offset>[];
    for (var i = 0; i < 60; i++) {
      for (var j = 0; j < 4; j++) {
        final p = Offset(
          data.size.width * (i % 20) / 20,
          data.size.height * j / 4,
        );
        if (tester.exact(p) == null) probes.add(p);
      }
    }
    expect(probes, isNotEmpty);

    final sw = Stopwatch()..start();
    for (final p in probes) {
      tester.nearest(p, tolerance: 16.0);
    }
    sw.stop();
    final perUs = sw.elapsedMicroseconds / probes.length;
    // ignore: avoid_print
    print('바다 탭 ${probes.length}회 · 1회 평균 ${perUs.toStringAsFixed(1)}us');

    // 탭 1회당 계산이므로 프레임 예산(16.7ms)에 한참 못 미쳐야 한다
    expect(perUs, lessThan(5000));
  });

  test('판정 속도가 프레임 예산 대비 충분히 빠르다', () {
    final points = <Offset>[];
    for (final r in data.regions) {
      final p = interiorPoint(r);
      if (p != null) points.add(p);
    }

    final sw = Stopwatch()..start();
    for (final p in points) {
      tester.exact(p);
    }
    sw.stop();

    final perQueryUs = sw.elapsedMicroseconds / points.length;
    // ignore: avoid_print
    print('판정 ${points.length}회 · 총 ${sw.elapsedMilliseconds}ms · '
        '1회 평균 ${perQueryUs.toStringAsFixed(1)}us');

    // 드래그 중 매 프레임 판정하므로 1ms(=1000us) 안에는 끝나야 한다
    expect(perQueryUs, lessThan(1000));
  });
}
