import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 점 [p] 에서 선분 [a]–[b] 까지의 최단 거리.
///
/// 지역 판정(폴리곤 경계까지의 거리)과 긁기 진행률(붓이 지나간 자취까지의 거리)이
/// 같은 계산을 쓴다. 두 곳에서 따로 구현하면 한쪽만 고쳐질 위험이 있어 여기 모은다.
double distancePointToSegment(Offset p, Offset a, Offset b) =>
    _segmentDistance(p.dx, p.dy, a.dx, a.dy, b.dx, b.dy);

/// 좌표를 풀어서 받는 형태. 좌표 배열을 순회할 때 `Offset` 할당을 피한다.
double _segmentDistance(
    double px, double py, double ax, double ay, double bx, double by) {
  final vx = bx - ax, vy = by - ay;
  final wx = px - ax, wy = py - ay;
  final len2 = vx * vx + vy * vy;
  var t = len2 <= 0 ? 0.0 : (wx * vx + wy * vy) / len2;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final dx = px - (ax + t * vx), dy = py - (ay + t * vy);
  return math.sqrt(dx * dx + dy * dy);
}

/// 좌표 배열용 저수준 버전. 링 좌표 `[x0,y0,x1,y1,...]` 순회에 쓴다.
double distanceToSegmentRaw(
        double px, double py, double ax, double ay, double bx, double by) =>
    _segmentDistance(px, py, ax, ay, bx, by);
