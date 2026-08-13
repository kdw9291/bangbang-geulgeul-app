import 'dart:math' as math;

import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter/foundation.dart';

import 'dart:ui' show Offset, Path, Rect;

import 'geometry.dart';
import 'map_data.dart';

/// 한 지역을 긁은 비율을 추적한다.
///
/// **위젯에서 분리한 순수 클래스다.** 화면 상태 안에 두면 테스트가 같은 계산을
/// 복제해서 검증하게 되고, 본체가 바뀌어도 테스트는 통과하는 구조가 된다.
/// 준비 비용이 큰 계산을 빌드 밖으로 옮기기 위해서도 분리가 필요하다.
class ScratchProgress {
  ScratchProgress._({
    required this.samples,
    required this.brush,
    required this.gridUsed,
    required this.reachedTarget,
  }) : _covered = List.filled(samples.length, false);

  /// 목표 표본 수. [maxGrid] 상한에 걸리면 이보다 적을 수 있으므로
  /// `min` 이 아니라 `target` 이다 — [reachedTarget] 로 달성 여부를 알린다.
  static const targetSamples = 300;

  /// 표본 격자 상한. 이 이상은 `Path.contains` 호출 비용이 화면 진입을 늦춘다.
  static const maxGrid = 220;

  /// 지역 내부에 깔린 표본점. **화면 좌표**다.
  final List<Offset> samples;

  /// 붓 반경 (화면 좌표 단위).
  final double brush;

  /// 실제로 사용한 격자 크기. 진단용.
  final int gridUsed;

  /// [targetSamples] 를 채웠는가. 상한에 걸려 미달이면 false.
  final bool reachedTarget;

  final List<bool> _covered;
  int _coveredCount = 0;
  Offset? _prev;

  int get sampleCount => samples.length;
  int get coveredCount => _coveredCount;

  /// 0.0 ~ 1.0. 표본이 없으면 0.
  double get ratio => samples.isEmpty ? 0 : _coveredCount / samples.length;

  /// 새 획을 시작한다. 이전 점과의 선분 연결을 끊는다.
  void startStroke() => _prev = null;

  /// 붓이 [p] 를 지났다고 기록한다.
  ///
  /// 직전 점이 있으면 **그 점과 [p] 를 잇는 선분**까지의 거리로 판정한다.
  /// 렌더는 두 점을 선으로 이어 지우므로 같은 기하를 써야 한다. 점만 보면
  /// 손가락이 빠를수록 같은 자취인데 진행률이 낮게 나온다.
  void addPoint(Offset p) {
    final prev = _prev;
    for (var i = 0; i < samples.length; i++) {
      if (_covered[i]) continue;
      final s = samples[i];
      final d =
          prev == null ? (s - p).distance : distancePointToSegment(s, prev, p);
      if (d <= brush) {
        _covered[i] = true;
        _coveredCount++;
      }
    }
    _prev = p;
  }

  /// [region] 을 [transform] 으로 화면에 옮겼을 때의 진행률 추적기를 만든다.
  ///
  /// 격자를 고정하면 육지가 bounds 의 1% 미만인 다도해에서 표본이 말라붙는다.
  /// 1차로 성기게 훑어 육지 비율을 구한 뒤 필요한 격자를 역산해 **한 번만 더**
  /// 훑는다. 전수 확대가 아니라 2회 통과라 비용이 예측 가능하다.
  ///
  /// **비용이 크다.** 위젯 빌드 중에 호출하지 말 것.
  static ScratchProgress forRegion(
    Region region,
    Matrix4 transform, {
    required double brush,
  }) {
    const pilot = 40;
    var samples = _collect(region.path, region.bounds, transform, pilot);
    var grid = pilot;

    if (samples.length < targetSamples) {
      const pilotCells = (pilot + 1) * (pilot + 1);
      final landRatio = samples.length / pilotCells;
      final needed = landRatio <= 0
          ? maxGrid
          : math.sqrt(targetSamples / landRatio).ceil();
      grid = needed.clamp(pilot + 1, maxGrid);
      samples = _collect(region.path, region.bounds, transform, grid);
    }

    return ScratchProgress._(
      samples: samples,
      brush: brush,
      gridUsed: grid,
      reachedTarget: samples.length >= targetSamples,
    );
  }

  static List<Offset> _collect(Path path, Rect b, Matrix4 m, int grid) {
    final out = <Offset>[];
    for (var i = 0; i <= grid; i++) {
      final x = b.left + b.width * i / grid;
      for (var j = 0; j <= grid; j++) {
        final p = Offset(x, b.top + b.height * j / grid);
        if (path.contains(p)) out.add(MatrixUtils.transformPoint(m, p));
      }
    }
    return out;
  }

  @visibleForTesting
  bool isCovered(int index) => _covered[index];
}
