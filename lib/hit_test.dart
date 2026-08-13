import 'dart:ui';

import 'map_data.dart';

/// 터치한 좌표가 어느 시군구인지 판정한다.
///
/// 좌표는 **지도 좌표계**(에셋에 저장된 km 단위 평면 좌표)여야 한다.
/// 화면 좌표에서의 변환과 허용 오차 환산은 호출하는 쪽 책임이다.
class RegionHitTester {
  RegionHitTester(List<Region> regions)
      // 경계가 맞닿은 지점은 두 지역 모두 contains 가 참일 수 있다.
      // 작은 지역을 먼저 보게 정렬해 두면 그런 지점에서 작은 쪽이 선택된다.
      // 도심 구처럼 긁기 어려운 지역이 손해 보지 않게 하려는 것.
      : _regions = [...regions]..sort(
          (a, b) => _boundsArea(a.bounds).compareTo(_boundsArea(b.bounds)),
        );

  final List<Region> _regions;

  static double _boundsArea(Rect r) => r.width * r.height;

  /// 정확히 그 지역 안에 있는 경우만 반환한다. 바다를 찍으면 null.
  Region? exact(Offset p) {
    for (final r in _regions) {
      if (!r.bounds.contains(p)) continue;
      if (r.path.contains(p)) return r;
    }
    return null;
  }

  /// [exact] 가 실패하면 [tolerance](지도 좌표 단위 = km) 안에서 폴리곤까지
  /// **실제 거리**가 가장 가까운 지역을 찾는다.
  ///
  /// 손가락은 뭉툭하고 해안선 지역은 가늘다. 정확히 안쪽을 찍어야만 인정하면
  /// 섬이나 좁은 해안 시군구는 긁기가 지나치게 어려워진다. 단순화된 경계
  /// 때문에 생기는 이웃 간 미세한 틈도 이걸로 메워진다.
  ///
  /// **bounds 까지의 거리를 쓰면 안 된다.** 옹진군 bounds 는 172×107km 라
  /// 폴리곤에서 30km 넘게 떨어진 먼 바다도 "거리 0"이 되어 삼켜버린다.
  /// bounds 는 후보를 걸러내는 용도로만 쓴다.
  Region? nearest(Offset p, {required double tolerance}) {
    final hit = exact(p);
    if (hit != null) return hit;
    if (tolerance <= 0) return null;

    Region? best;
    var bestDist = double.infinity;
    for (final r in _regions) {
      // 1차 필터: 허용 오차만큼 부풀린 bounds 밖이면 폴리곤도 그 밖이다.
      if (!_withinInflatedBounds(r.bounds, p, tolerance)) continue;
      final d = r.distanceTo(p);
      if (d > tolerance || d >= bestDist) continue;
      bestDist = d;
      best = r;
    }
    return best;
  }

  /// `Rect.inflate().contains()` 를 쓰지 않는 이유:
  /// `Rect.contains` 는 왼쪽·위 경계는 포함하지만 **오른쪽·아래 경계는 제외**한다.
  /// 실제 거리가 정확히 tolerance 인 점이 오른쪽/아래에 있으면 아래 판정
  /// (`d > tolerance` 면 탈락)은 통과시키는데 1차 필터가 먼저 걸러내 버려,
  /// 방향에 따라 계약이 달라진다. 네 방향 모두 포함으로 맞춘다.
  static bool _withinInflatedBounds(Rect b, Offset p, double t) =>
      p.dx >= b.left - t &&
      p.dx <= b.right + t &&
      p.dy >= b.top - t &&
      p.dy <= b.bottom + t;
}

/// 화면 픽셀 기준 탭 허용 반경.
///
/// 손가락 굵기는 지도 배율과 무관하므로 허용 오차도 화면 기준이어야 한다.
/// 고정 km 로 두면 확대할수록 실제 손가락 대비 허용 범위가 넓어져,
/// 확대해서 정밀하게 찍으려는 사용자가 오히려 옆 지역을 집게 된다.
const double kTapTolerancePx = 12.0;

/// 화면 픽셀 허용 반경을 지도 좌표 단위로 환산한다.
///
/// - [tolerancePx] 화면상 허용 반경(논리 픽셀)
/// - [mapUnitsPerWidgetPx] 지도 위젯 1px 당 지도 좌표 단위 (`지도폭 / 위젯폭`)
/// - [viewerScale] InteractiveViewer 의 현재 배율. 확대하면 화면 1px 이
///   차지하는 지도 거리가 줄어든다.
double tapToleranceInMapUnits({
  required double mapUnitsPerWidgetPx,
  required double viewerScale,
  double tolerancePx = kTapTolerancePx,
}) {
  final s = viewerScale <= 0 ? 1.0 : viewerScale;
  return tolerancePx * mapUnitsPerWidgetPx / s;
}
