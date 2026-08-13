/// 다도해 지역의 긁기 화면 배치 — **섬을 모아 재배치한다.**
///
/// ## 왜 필요한가
///
/// 긁기 화면은 지역 `bounds` 를 화면에 맞춘다. 대부분의 지역은 이걸로 충분하지만,
/// 섬이 널리 흩어진 지역은 bounds 가 육지보다 압도적으로 커서 **화면의 대부분이 바다**가 된다.
///
/// | 지역 | 육지 / bounds | 링 수 |
/// |---|---|---|
/// | 옹진군 | **0.93%** | 20 |
/// | 신안군 | 5.44% | 42 |
/// | 안산시단원구 | 8.31% | 3 |
/// | 여수시 | 9.11% | 17 |
///
/// 사용자는 빈 바다를 긁게 되고, 아트도 파편으로만 보인다.
///
/// ## 왜 "가장 큰 섬만 확대" 로는 안 되는가
///
/// 가장 큰 섬이 육지 전체에서 차지하는 비중을 재보면 옹진군 31.9%, 신안군 **10.5%**,
/// 안산시단원구 54.7% 다. 그 섬만 화면에 담으면 **아무리 긁어도 자동 완성 임계치 65% 에
/// 도달할 수 없다.** 측정으로 폐기한 안이다.
///
/// ## 무엇을 하는가
///
/// 링들을 선반(shelf) 방식으로 빈틈없이 모아 붙인다. 섬 사이의 바다를 걷어내므로
/// 같은 화면에서 육지가 훨씬 커진다. **섬끼리의 상대 크기는 유지한다** — 작은 섬을
/// 따로 키우면 어느 섬이 큰지에 대한 감각이 깨진다.
///
/// 지리적 위치는 왜곡된다. 긁기 화면은 **지역 하나를 손에 쥔 전용 화면**이고 지도가 아니므로
/// 허용 가능한 왜곡이라고 본다. 지도 화면은 실제 경계를 그대로 쓴다.
/// (이 프로젝트는 지도에서조차 울릉군을 동해 안쪽으로 95km 당겨 배치한 전례가 있다.)
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 링 하나를 어디로 옮길지.
@immutable
class IslandPlacement {
  const IslandPlacement(this.ring, this.offset);

  /// 원본 링 (지도 좌표계).
  final Float32List ring;

  /// 원본 위치에서 더할 이동량. 배율은 바꾸지 않는다.
  final Offset offset;
}

/// 재배치 결과.
@immutable
class IslandLayout {
  const IslandLayout(this.placements, this.bounds, this.fillRatio);

  final List<IslandPlacement> placements;

  /// 재배치 후 전체를 감싸는 영역. 긁기 화면은 이걸 화면에 맞춘다.
  final Rect bounds;

  /// 재배치 후 육지 면적 / [bounds] 면적. 개선 폭을 재는 값이다.
  final double fillRatio;
}

Rect _ringBounds(Float32List r) {
  var minX = r[0], maxX = r[0], minY = r[1], maxY = r[1];
  for (var i = 2; i < r.length; i += 2) {
    final x = r[i], y = r[i + 1];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _ringArea(Float32List r) {
  final n = r.length ~/ 2;
  if (n < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    s += r[i * 2] * r[j * 2 + 1] - r[j * 2] * r[i * 2 + 1];
  }
  return s.abs() / 2;
}

/// 링들을 모아 붙인 배치를 만든다.
///
/// [gap] 은 섬 사이 여백이다. 0 이면 섬이 붙어 보여 경계가 흐려진다.
/// 링 bbox 대각선 중앙값에 비례해 정하는 편이 크기에 무관하게 자연스럽다.
IslandLayout packIslands(List<Float32List> rings, {double gapRatio = 0.06}) {
  final items = rings.where((r) => r.length >= 6).toList()
    ..sort((a, b) => _ringBounds(b).height.compareTo(_ringBounds(a).height));

  if (items.isEmpty) {
    return const IslandLayout([], Rect.zero, 0);
  }
  if (items.length == 1) {
    final b = _ringBounds(items.first);
    return IslandLayout(
      [IslandPlacement(items.first, Offset.zero)],
      b,
      b.width * b.height <= 0 ? 0 : _ringArea(items.first) / (b.width * b.height),
    );
  }

  final boxes = [for (final r in items) _ringBounds(r)];
  final totalArea = boxes.fold(0.0, (s, b) => s + b.width * b.height);
  final gap = math.sqrt(totalArea / items.length) * gapRatio;

  // 선반 폭 후보를 훑어 가장 정사각형에 가까운 결과를 고른다.
  // 정사각형이어야 화면 비율과 무관하게 잘 들어간다.
  List<IslandPlacement>? best;
  Rect bestBounds = Rect.zero;
  var bestScore = double.infinity;

  final widest = boxes.map((b) => b.width).reduce(math.max);
  for (var step = 1; step <= 24; step++) {
    final shelfWidth = math.max(widest, math.sqrt(totalArea) * (0.4 + step * 0.12));

    final placements = <IslandPlacement>[];
    var cursorX = 0.0, cursorY = 0.0, shelfHeight = 0.0, usedWidth = 0.0;

    for (var i = 0; i < items.length; i++) {
      final b = boxes[i];
      if (cursorX > 0 && cursorX + b.width > shelfWidth) {
        cursorY += shelfHeight + gap;
        cursorX = 0;
        shelfHeight = 0;
      }
      placements.add(IslandPlacement(
        items[i],
        Offset(cursorX - b.left, cursorY - b.top),
      ));
      cursorX += b.width + gap;
      usedWidth = math.max(usedWidth, cursorX - gap);
      shelfHeight = math.max(shelfHeight, b.height);
    }
    final totalHeight = cursorY + shelfHeight;
    if (usedWidth <= 0 || totalHeight <= 0) continue;

    final score = (usedWidth / totalHeight - 1).abs();
    if (score < bestScore) {
      bestScore = score;
      best = placements;
      bestBounds = Rect.fromLTWH(0, 0, usedWidth, totalHeight);
    }
  }

  final placements = best ?? const <IslandPlacement>[];
  final land = items.fold(0.0, (s, r) => s + _ringArea(r));
  final area = bestBounds.width * bestBounds.height;
  return IslandLayout(placements, bestBounds, area <= 0 ? 0 : land / area);
}

/// 재배치를 적용한 [Path] 를 만든다.
///
/// 원본 링을 옮기기만 하므로 섬 하나하나의 모양과 크기는 그대로다.
Path buildPackedPath(IslandLayout layout) {
  final path = Path();
  for (final p in layout.placements) {
    final r = p.ring;
    path.moveTo(r[0] + p.offset.dx, r[1] + p.offset.dy);
    for (var i = 2; i < r.length; i += 2) {
      path.lineTo(r[i] + p.offset.dx, r[i + 1] + p.offset.dy);
    }
    path.close();
  }
  return path;
}

/// 재배치 결과에서 **가장 큰 섬 하나**의 [Path] 를 만든다.
///
/// 다도해는 아트를 지역 전체에 걸쳐 놓으면 섬마다 파편으로 잘려 무엇인지 알 수 없다.
/// 재배치 프로토타입에서 옹진군이 그렇게 나왔다 — 주황 조각과 흰 덩어리로만 보였다.
/// **아트는 가장 큰 섬 하나에만 놓는다.** 나머지 섬은 단색으로 둔다.
Path buildLargestIslandPath(IslandLayout layout) {
  if (layout.placements.isEmpty) return Path();
  var best = layout.placements.first;
  var bestArea = _ringArea(best.ring);
  for (final p in layout.placements.skip(1)) {
    final a = _ringArea(p.ring);
    if (a > bestArea) {
      bestArea = a;
      best = p;
    }
  }
  final path = Path();
  final r = best.ring;
  path.moveTo(r[0] + best.offset.dx, r[1] + best.offset.dy);
  for (var i = 2; i < r.length; i += 2) {
    path.lineTo(r[i] + best.offset.dx, r[i + 1] + best.offset.dy);
  }
  return path..close();
}

/// 이 지역에 재배치가 필요한가.
///
/// 육지가 bounds 의 [threshold] 미만이면 화면 대부분이 바다가 된다.
/// 실측 기준 10% 미만은 옹진군·신안군·안산시단원구·여수시 4개다.
/// 완도군(12.6%)·통영시(16.1%)가 그다음이라 임계치를 조금 올리면 대상이 늘어난다.
bool needsPacking(List<Float32List> rings, Rect bounds, {double threshold = 0.10}) {
  if (rings.length < 2) return false;
  final area = bounds.width * bounds.height;
  if (area <= 0) return false;
  final land = rings.fold(0.0, (s, r) => s + _ringArea(r));
  return land / area < threshold;
}
