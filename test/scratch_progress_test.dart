import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Matrix4, Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/scratch_progress.dart';

/// 긁기 화면과 **같은 변환**을 만든다. 화면 크기만 테스트에서 고정한다.
Matrix4 transformFor(Region r, Size size) {
  final b = r.bounds;
  const pad = 36.0;
  final k = math.min(
    (size.width - pad * 2) / b.width,
    (size.height - pad * 2) / b.height,
  );
  return Matrix4.identity()
    ..translateByDouble(
      size.width / 2 - b.center.dx * k,
      size.height / 2 - b.center.dy * k,
      0,
      1,
    )
    ..scaleByDouble(k, k, 1, 1);
}

const screen = Size(400, 600);
const brush = 26.0;

ScratchProgress make(Region r) =>
    ScratchProgress.forRegion(r, transformFor(r, screen), brush: brush);

/// 시작점에서 끝점까지 [steps] 개의 점으로 나눠 입력한다.
void drag(ScratchProgress p, Offset from, Offset to, int steps) {
  p.startStroke();
  for (var i = 0; i <= steps; i++) {
    p.addPoint(Offset.lerp(from, to, i / steps)!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  late Region jeju; // 크고 단순한 지역
  late Region ongjin; // 다도해 — 표본이 마르던 지역

  setUpAll(() async {
    data = await MapData.load();
    jeju = data.regions.firstWhere((r) => r.name == '제주특별자치도');
    ongjin = data.regions.firstWhere((r) => r.name == '옹진군');
  });

  // Codex 지적 #5 앞부분 회귀 방지.
  test('같은 자취면 입력 점 개수가 달라도 진행률이 같다', () {
    const from = Offset(60, 300);
    const to = Offset(340, 300);

    final coarse = make(jeju);
    drag(coarse, from, to, 2);
    final fine = make(jeju);
    drag(fine, from, to, 60);

    // ignore: avoid_print
    print('점 3개: ${(coarse.ratio * 100).toStringAsFixed(2)}% · '
        '점 61개: ${(fine.ratio * 100).toStringAsFixed(2)}%');

    expect(coarse.sampleCount, fine.sampleCount);
    expect(coarse.coveredCount, fine.coveredCount,
        reason: '선분 보간이면 이벤트 밀도와 무관해야 한다');
  });

  test('점 기준으로 세면 입력 밀도에 따라 결과가 달라진다 (회귀 대조)', () {
    // 매번 startStroke 를 불러 선분 연결을 끊으면 옛 "점 기준" 동작이 된다
    int countByPoints(Region r, Offset from, Offset to, int steps) {
      final p = make(r);
      for (var i = 0; i <= steps; i++) {
        p.startStroke();
        p.addPoint(Offset.lerp(from, to, i / steps)!);
      }
      return p.coveredCount;
    }

    const from = Offset(60, 300);
    const to = Offset(340, 300);
    final coarse = countByPoints(jeju, from, to, 2);
    final fine = countByPoints(jeju, from, to, 60);
    // ignore: avoid_print
    print('점 기준 — 점 3개: $coarse개 · 점 61개: $fine개');
    expect(coarse, lessThan(fine),
        reason: '점 기준은 성기면 덜 덮인다. 이 차이를 없애는 것이 선분 보간의 목적');
  });

  test('새 획을 시작하면 이전 획과 선으로 이어지지 않는다', () {
    // 도형 밖 좌표를 고르면 아무것도 안 덮여 검증이 무의미해진다.
    // 실제 표본에서 서로 가장 먼 두 점을 쓴다.
    final ref = make(jeju);
    final a = ref.samples.first;
    final b = ref.samples.last;
    expect((a - b).distance, greaterThan(brush * 3),
        reason: '두 점이 붓 반경보다 충분히 떨어져야 의미가 있다');

    final separated = make(jeju);
    separated.startStroke();
    separated.addPoint(a);
    final afterFirst = separated.coveredCount;
    separated.startStroke(); // 획을 끊는다
    separated.addPoint(b);
    final afterSecond = separated.coveredCount;

    final connected = make(jeju);
    connected.startStroke();
    connected.addPoint(a);
    connected.addPoint(b); // 같은 획 = 선으로 연결

    // ignore: avoid_print
    print('첫 점 $afterFirst개 · 획 분리 $afterSecond개 · '
        '획 연결 ${connected.coveredCount}개');

    expect(afterFirst, greaterThan(0), reason: '첫 점이 표본 위이므로 덮여야 한다');
    expect(afterSecond, greaterThan(afterFirst), reason: '두 번째 점도 덮인다');
    expect(afterSecond, lessThan(connected.coveredCount),
        reason: 'startStroke 후에는 이전 점과 이어지지 않아야 한다');
  });

  test('첫 점은 원형 붓으로 덮는다', () {
    final p = make(jeju);
    p.startStroke();
    p.addPoint(p.samples.first); // 확실히 도형 안인 좌표
    expect(p.coveredCount, greaterThan(0), reason: '단일 탭도 진행률에 반영돼야 한다');
  });

  // Codex 지적 #5 뒷부분 회귀 방지.
  test('다도해 지역도 표본이 충분히 확보된다', () {
    final p = make(ongjin);
    // ignore: avoid_print
    print('옹진군 표본 ${p.sampleCount}개 · 격자 ${p.gridUsed} · '
        '1점당 ${(100 / p.sampleCount).toStringAsFixed(2)}%');
    expect(p.sampleCount, greaterThanOrEqualTo(ScratchProgress.targetSamples),
        reason: '고정 41x41 격자에서는 15개뿐이었다');
    expect(p.reachedTarget, isTrue);
  });

  test('231개 지역 전부가 목표 표본 수를 만족한다', () {
    final short = <String, int>{};
    for (final r in data.regions) {
      final p = make(r);
      if (!p.reachedTarget) short[r.name] = p.sampleCount;
    }
    // ignore: avoid_print
    print('목표 미달 지역: ${short.length}개');
    if (short.isNotEmpty) {
      // ignore: avoid_print
      print('  $short');
    }
    expect(short, isEmpty);
  });

  // 아래 두 테스트는 **정밀 측정이 아니라 회귀 감지용**이다.
  // CI/로컬 부하에 따라 10배까지 튄다 (실측 26ms ~ 368ms). 실제 성능 판단은
  // 실기기 profile 측정으로 한다. 임계값은 "구조가 깨졌을 때만" 걸리도록 넉넉히 둔다.
  test('표본 수집이 구조적으로 폭주하지 않는다', () {
    final sw = Stopwatch()..start();
    final p = make(ongjin);
    sw.stop();
    // ignore: avoid_print
    print('옹진군 표본 수집 ${sw.elapsedMilliseconds}ms (${p.sampleCount}개, '
        '격자 ${p.gridUsed})');

    // 격자 상한이 지켜지는지가 본질이다. 시간은 보조 지표.
    expect(p.gridUsed, lessThanOrEqualTo(ScratchProgress.maxGrid));
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test('드래그 이벤트당 처리가 표본 수에 선형이고 폭주하지 않는다', () {
    Region worst = jeju;
    var worstN = 0;
    for (final r in [
      ongjin,
      jeju,
      data.regions.firstWhere((x) => x.name == '신안군')
    ]) {
      final n = make(r).sampleCount;
      if (n > worstN) {
        worstN = n;
        worst = r;
      }
    }

    final p = make(worst);
    const steps = 200;
    p.startStroke();
    final sw = Stopwatch()..start();
    for (var i = 0; i <= steps; i++) {
      p.addPoint(Offset.lerp(
          const Offset(50, 100), const Offset(350, 500), i / steps)!);
    }
    sw.stop();
    final perUs = sw.elapsedMicroseconds / (steps + 1);
    // ignore: avoid_print
    print('${worst.name} 표본 ${p.sampleCount}개 · 이벤트당 ${perUs.toStringAsFixed(1)}us');
    expect(perUs, lessThan(3000));
  });

  test('진행률은 0에서 시작해 긁을수록 오른다', () {
    final p = make(jeju);
    expect(p.ratio, 0);
    drag(p, const Offset(60, 300), const Offset(340, 300), 40);
    expect(p.ratio, greaterThan(0));
    final after = p.ratio;
    drag(p, const Offset(60, 320), const Offset(340, 320), 40);
    expect(p.ratio, greaterThan(after));
  });

  test('같은 자리를 다시 긁어도 진행률이 중복 계산되지 않는다', () {
    final p = make(jeju);
    drag(p, const Offset(60, 300), const Offset(340, 300), 40);
    final once = p.coveredCount;
    drag(p, const Offset(60, 300), const Offset(340, 300), 40);
    expect(p.coveredCount, once, reason: '이미 덮인 표본은 다시 세지 않는다');
  });
}
