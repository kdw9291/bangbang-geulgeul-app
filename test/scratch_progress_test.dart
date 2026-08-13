import 'dart:math' as math;

import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/geometry.dart';
import 'package:mapscratch/map_data.dart';

/// `_ScratchPageState` 의 표본 수집·진행률 계산과 **같은 규칙**을 재현한 것.
///
/// 위젯 상태 내부 로직이라 직접 호출할 수 없어 규칙을 옮겨 검증한다.
/// 상수(minSamples 300, maxGrid 220, brush 26)가 바뀌면 여기도 함께 고쳐야 한다.
class ProgressModel {
  ProgressModel(this.region, {this.brush = 26.0}) {
    final b = region.bounds;
    // 화면 400x600 에 맞추는 변환 (실제 페이지와 같은 방식)
    const pad = 36.0;
    final k = math.min((400 - pad * 2) / b.width, (600 - pad * 2) / b.height);
    _m = Matrix4.identity()
      ..translateByDouble(200 - b.center.dx * k, 300 - b.center.dy * k, 0, 1)
      ..scaleByDouble(k, k, 1, 1);

    samples = _collect(40);
    if (samples.length < 300) {
      const first = 41 * 41;
      final ratio = samples.length / first;
      final needed = ratio <= 0 ? 220 : math.sqrt(300 / ratio).ceil();
      samples = _collect(needed.clamp(41, 220));
    }
    covered = List.filled(samples.length, false);
  }

  final Region region;
  final double brush;
  late final Matrix4 _m;
  late List<Offset> samples;
  late List<bool> covered;
  int coveredCount = 0;
  Offset? _prev;

  List<Offset> _collect(int grid) {
    final b = region.bounds;
    final out = <Offset>[];
    for (var i = 0; i <= grid; i++) {
      final x = b.left + b.width * i / grid;
      for (var j = 0; j <= grid; j++) {
        final p = Offset(x, b.top + b.height * j / grid);
        if (region.path.contains(p)) {
          out.add(MatrixUtils.transformPoint(_m, p));
        }
      }
    }
    return out;
  }

  double get ratio => samples.isEmpty ? 0 : coveredCount / samples.length;

  void startStroke() => _prev = null;

  void addPoint(Offset p) {
    final prev = _prev;
    for (var i = 0; i < samples.length; i++) {
      if (covered[i]) continue;
      final d = prev == null
          ? (samples[i] - p).distance
          : distancePointToSegment(samples[i], prev, p);
      if (d <= brush) {
        covered[i] = true;
        coveredCount++;
      }
    }
    _prev = p;
  }

  /// 시작점에서 끝점까지 [steps] 개의 점으로 나눠 입력한다.
  void drag(Offset from, Offset to, int steps) {
    startStroke();
    for (var i = 0; i <= steps; i++) {
      addPoint(Offset.lerp(from, to, i / steps)!);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  late Region jeju; // 크고 단순한 지역
  late Region ongjin; // 다도해 — 표본이 마르던 지역

  setUpAll(() async {
    data = await MapData.load();
    jeju = data.regions.firstWhere((r) => r.name == '서귀포시');
    ongjin = data.regions.firstWhere((r) => r.name == '옹진군');
  });

  // Codex 지적 #5 앞부분 회귀 방지.
  test('같은 자취면 입력 점 개수가 달라도 진행률이 같다', () {
    final from = const Offset(60, 300);
    final to = const Offset(340, 300);

    final coarse = ProgressModel(jeju)..drag(from, to, 2);
    final fine = ProgressModel(jeju)..drag(from, to, 60);

    // ignore: avoid_print
    print('점 3개: ${(coarse.ratio * 100).toStringAsFixed(2)}% · '
        '점 61개: ${(fine.ratio * 100).toStringAsFixed(2)}%');

    expect(coarse.samples.length, fine.samples.length);
    expect(coarse.coveredCount, fine.coveredCount,
        reason: '선분 보간이면 이벤트 밀도와 무관해야 한다');
  });

  test('점 기준으로 세면 입력 밀도에 따라 결과가 달라진다 (회귀 대조)', () {
    // 보간 없이 점만 보는 옛 방식을 재현해 차이를 보인다
    int countByPoints(Region r, Offset from, Offset to, int steps) {
      final m = ProgressModel(r);
      var n = 0;
      for (var i = 0; i <= steps; i++) {
        final p = Offset.lerp(from, to, i / steps)!;
        for (var k = 0; k < m.samples.length; k++) {
          if (m.covered[k]) continue;
          if ((m.samples[k] - p).distance <= m.brush) {
            m.covered[k] = true;
            n++;
          }
        }
      }
      return n;
    }

    const from = Offset(60, 300);
    const to = Offset(340, 300);
    final coarse = countByPoints(jeju, from, to, 2);
    final fine = countByPoints(jeju, from, to, 60);
    // ignore: avoid_print
    print('옛 방식 — 점 3개: $coarse개 · 점 61개: $fine개');
    expect(coarse, lessThan(fine),
        reason: '옛 방식은 점이 성기면 덜 덮인다. 이 차이를 없애는 것이 이번 수정의 목적');
  });

  // Codex 지적 #5 뒷부분 회귀 방지.
  test('다도해 지역도 표본이 충분히 확보된다', () {
    final m = ProgressModel(ongjin);
    // ignore: avoid_print
    print('옹진군 표본 ${m.samples.length}개 · '
        '1점당 ${(100 / m.samples.length).toStringAsFixed(2)}%');
    expect(m.samples.length, greaterThanOrEqualTo(300),
        reason: '고정 41x41 격자에서는 15개뿐이었다');
  });

  test('모든 지역이 최소 표본 수를 만족한다', () {
    final short = <String, int>{};
    for (final r in data.regions) {
      final n = ProgressModel(r).samples.length;
      if (n < 300) short[r.name] = n;
    }
    // ignore: avoid_print
    print('표본 300개 미만 지역: ${short.length}개');
    if (short.isNotEmpty) {
      // ignore: avoid_print
      print('  $short');
    }
    expect(short, isEmpty);
  });

  test('표본 수집 비용이 화면 진입을 막을 정도는 아니다', () {
    // 가장 불리한 지역(다도해)에서 측정
    final sw = Stopwatch()..start();
    final m = ProgressModel(ongjin);
    sw.stop();
    // ignore: avoid_print
    print('옹진군 표본 수집 ${sw.elapsedMilliseconds}ms (${m.samples.length}개)');
    expect(sw.elapsedMilliseconds, lessThan(400));
  });

  // 표본이 늘고(15 -> 310) 거리 계산이 점에서 선분으로 바뀌었으므로
  // 드래그 이벤트당 비용이 프레임 예산을 위협하지 않는지 확인한다.
  test('드래그 이벤트당 처리 비용이 프레임 예산 안에 들어온다', () {
    Region worst = data.regions.first;
    var worstN = 0;
    for (final r in [ongjin, jeju, data.regions.firstWhere((x) => x.name == '신안군')]) {
      final n = ProgressModel(r).samples.length;
      if (n > worstN) {
        worstN = n;
        worst = r;
      }
    }

    final m = ProgressModel(worst);
    const steps = 200;
    m.startStroke();
    final sw = Stopwatch()..start();
    for (var i = 0; i <= steps; i++) {
      m.addPoint(Offset.lerp(
          const Offset(50, 100), const Offset(350, 500), i / steps)!);
    }
    sw.stop();
    final perUs = sw.elapsedMicroseconds / (steps + 1);
    // ignore: avoid_print
    print('${worst.name} 표본 ${m.samples.length}개 · '
        '이벤트당 ${perUs.toStringAsFixed(1)}us');

    // 프레임 예산 16.7ms 의 일부만 써야 한다. 이벤트는 프레임당 여러 번 올 수 있다
    expect(perUs, lessThan(3000));
  });

  test('진행률은 0에서 시작해 긁을수록 오른다', () {
    final m = ProgressModel(jeju);
    expect(m.ratio, 0);
    m.drag(const Offset(60, 300), const Offset(340, 300), 40);
    expect(m.ratio, greaterThan(0));
    final after = m.ratio;
    m.drag(const Offset(60, 320), const Offset(340, 320), 40);
    expect(m.ratio, greaterThan(after));
  });
}
