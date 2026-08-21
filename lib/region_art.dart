import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'art_category.dart';
import 'region_category.g.dart';

export 'art_category.dart';

/// T6 아트 — 지역 아트를 그리는 구현.
///
/// **랜드마크 32개와 카테고리 8종이 전량 들어 있다.** 파일럿으로 시작했으나
/// 2026-08-14 에 제작이 끝났다 (37번째는 M15 로 신설한 독도).
/// **2026-08-20 광역시 통합으로 32개가 됐다** — 통합 지역은 랜드마크를 하나만
/// 가질 수 있어 대표를 남기고 다섯을 버렸다 (사용자 결정).
/// 배경과 결정 근거는 `design/art-strategy.md` 참고.
///
/// ## 왜 SVG `d` 문자열을 그대로 들고 있는가
///
/// 아트 원본은 SVG 로 만든다(`design/art-samples.html`). 그런데 Flutter 로 옮기면서
/// 좌표를 손으로 다시 쓰면 **같은 그림을 두 번 만드는 셈**이라 물량이 두 배가 되고,
/// 원본과 앱이 어긋나기 시작한다.
///
/// 그래서 `d` 문자열을 공유한다. SVG 에서 잘라 붙이면 그대로 동작하므로 이중 작업이 없다.
/// 대신 최소한의 파서가 필요하다 — [parseSvgPath] 는 `M L H V C S Q T Z` 만 지원한다.
/// 타원 호(`A`)는 지원하지 않으므로 원본에서 3차 베지어로 그린다.
///
/// `flutter_svg` 의존성을 넣지 않은 이유는 런타임 포맷을 실측으로 정하기 전에
/// 한쪽으로 굳히지 않기 위해서다. 파일럿 결과를 보고 결정한다.

/// 아트 팔레트. 3색 고정이라 지역이 늘어도 톤이 흔들리지 않는다.
class ArtPalette {
  const ArtPalette._();

  static const ink = Color(0xFF2B2118);
  static const paper = Color(0xFFFFFDF8);
  static const accent = Color(0xFFC9713A);
  static const accent2 = Color(0xFF4A7C6F);
}

/// 도형이 **잘려도 되는가**.
///
/// 배치 B(`artTargetFill`)는 아트를 지역보다 크게 놓고 지역 모양으로 잘라 비춘다.
/// 무엇이 보일지는 지역 모양에 달려 있으므로, 아트를 "오브젝트 하나"로 그리면
/// 잘렸을 때 무너진다 — 팔달문이 지붕만 남고 들판이 원만 남았던 것이 그 예다.
///
/// 그래서 두 층으로 나눈다.
enum ArtLayer {
  /// **핵심 모티프.** 무엇인지 알아보게 하는 부분이다.
  /// [kSafeArea] 안에 들어와야 한다 — 어떤 크롭에서도 살아남아야 하기 때문이다.
  core,

  /// **배경.** 잘리는 것을 전제한다. 화면을 채우고 분위기를 만든다.
  /// 반복되는 패턴(성벽·이랑·물결)이나 흩뿌림(별)이라 일부만 보여도 읽힌다.
  /// [kBleedArea] 까지 넘어가도 된다.
  background,
}

/// 핵심 모티프가 들어와야 하는 영역. 100×100 좌표계의 중앙 46×46.
///
/// 가장 불리한 지역이 기준이다. 부산 서구는 가로:세로가 1:3.73 이라
/// 아트의 가운데 세로 띠만 보인다.
const kSafeArea = Rect.fromLTRB(27, 27, 73, 73);

/// 배경이 넘어가도 되는 한계. 이보다 크면 그려도 화면에 못 들어온다.
const kBleedArea = Rect.fromLTRB(-25, -25, 125, 125);

/// 아트를 이루는 도형 하나.
///
/// SVG 의 `<path>` 와 `<circle>` 만 쓴다. `rect` 는 `d` 로 표현할 수 있어 따로 두지 않는다.
@immutable
class ArtShape {
  const ArtShape(
    this.d, {
    this.fill,
    this.stroke = ArtPalette.ink,
    this.strokeWidth = 5.0,
    this.layer = ArtLayer.core,
  }) : circle = null;

  /// 원. `d` 로도 그릴 수 있으나 호가 필요해 파서를 키우게 되므로 따로 둔다.
  const ArtShape.circle(
    double cx,
    double cy,
    double r, {
    this.fill,
    this.stroke = ArtPalette.ink,
    this.strokeWidth = 5.0,
    this.layer = ArtLayer.core,
  })  : d = '',
        circle = (cx, cy, r);

  final ArtLayer layer;

  /// SVG path 의 `d` 속성. 100×100 좌표계 기준이다.
  final String d;

  /// 원일 때의 (중심x, 중심y, 반지름).
  final (double, double, double)? circle;

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
}

/// 지역 하나에 대응하는 아트. 100×100 좌표계를 전제한다.
@immutable
class RegionArt {
  const RegionArt(this.name, this.shapes);

  /// 소재 이름. 권리 검토(provenance) 기록과 대응한다.
  final String name;
  final List<ArtShape> shapes;
}

// ---------------------------------------------------------------------------
// SVG path 파서
// ---------------------------------------------------------------------------

/// SVG `d` 문자열을 [Path] 로 바꾼다.
///
/// 지원: `M m L l H h V v C c S s Q q T t Z z`.
/// **미지원: `A`(타원 호).** 원본에서 3차 베지어로 대체한다.
/// 파일럿 범위이므로 잘못된 입력은 [FormatException] 으로 즉시 실패시킨다 —
/// 조용히 빈 Path 를 돌려주면 아트가 안 보이는 원인을 찾기 어렵다.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  var i = 0;

  var cur = Offset.zero; // 현재 점
  var start = Offset.zero; // 현재 서브패스 시작점
  Offset? lastCubicCtrl; // S 가 반사할 직전 3차 제어점
  Offset? lastQuadCtrl; // T 가 반사할 직전 2차 제어점
  var cmd = '';

  double num() {
    if (i >= tokens.length) {
      throw FormatException('SVG path: 인자가 부족하다 ($cmd)', d);
    }
    final t = tokens[i++];
    final v = double.tryParse(t);
    if (v == null) throw FormatException('SVG path: 숫자가 아니다 "$t"', d);
    return v;
  }

  bool moreArgs() =>
      i < tokens.length && double.tryParse(tokens[i]) != null;

  while (i < tokens.length) {
    final t = tokens[i];
    if (double.tryParse(t) == null) {
      cmd = t;
      i++;
    } else if (cmd.isEmpty) {
      throw FormatException('SVG path: 명령 없이 숫자로 시작한다', d);
    } else if (cmd == 'M') {
      cmd = 'L'; // 암묵적 반복은 lineto 다
    } else if (cmd == 'm') {
      cmd = 'l';
    }

    final rel = cmd.toLowerCase() == cmd;
    Offset pt(double x, double y) => rel ? cur + Offset(x, y) : Offset(x, y);

    switch (cmd.toUpperCase()) {
      case 'M':
        cur = pt(num(), num());
        path.moveTo(cur.dx, cur.dy);
        start = cur;
        lastCubicCtrl = lastQuadCtrl = null;
      case 'L':
        cur = pt(num(), num());
        path.lineTo(cur.dx, cur.dy);
        lastCubicCtrl = lastQuadCtrl = null;
      case 'H':
        final x = num();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
        lastCubicCtrl = lastQuadCtrl = null;
      case 'V':
        final y = num();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
        lastCubicCtrl = lastQuadCtrl = null;
      case 'C':
        final c1 = pt(num(), num());
        final c2 = pt(num(), num());
        final end = pt(num(), num());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cur = end;
        lastCubicCtrl = c2;
        lastQuadCtrl = null;
      case 'S':
        // 직전 3차 제어점을 현재 점 기준으로 반사한다.
        final c1 = lastCubicCtrl == null ? cur : cur * 2 - lastCubicCtrl;
        final c2 = pt(num(), num());
        final end = pt(num(), num());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cur = end;
        lastCubicCtrl = c2;
        lastQuadCtrl = null;
      case 'Q':
        final c = pt(num(), num());
        final end = pt(num(), num());
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        cur = end;
        lastQuadCtrl = c;
        lastCubicCtrl = null;
      case 'T':
        final c = lastQuadCtrl == null ? cur : cur * 2 - lastQuadCtrl;
        final end = pt(num(), num());
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        cur = end;
        lastQuadCtrl = c;
        lastCubicCtrl = null;
      case 'Z':
        path.close();
        cur = start;
        lastCubicCtrl = lastQuadCtrl = null;
        // Z 는 인자를 받지 않는다. 숫자가 이어지면 루프가 전진하지 못해
        // 무한 반복에 빠지므로 여기서 끊는다.
        if (moreArgs()) {
          throw FormatException('SVG path: Z 뒤에 인자가 올 수 없다', d);
        }
      default:
        throw FormatException('SVG path: 지원하지 않는 명령 "$cmd"', d);
    }
  }
  return path;
}

/// `d` 를 명령 문자와 숫자로 쪼갠다.
/// SVG 는 `10-20` 처럼 구분자 없이 붙여 쓸 수 있어 직접 훑는다.
List<String> _tokenize(String d) {
  final out = <String>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isNotEmpty) {
      out.add(buf.toString());
      buf.clear();
    }
  }

  for (var j = 0; j < d.length; j++) {
    final c = d[j];
    if (c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r') {
      flush();
    } else if (c == 'e' || c == 'E') {
      // 지수 표기(`1e-5`)의 e 는 명령 문자가 아니라 숫자의 일부다.
      // 숫자를 쓰던 중이면 이어 붙이고, 아니면 명령으로 본다.
      final prev = buf.isEmpty ? '' : buf.toString()[buf.length - 1];
      if (RegExp(r'[0-9.]').hasMatch(prev)) {
        buf.write(c);
      } else {
        flush();
        out.add(c);
      }
    } else if (RegExp(r'[A-Za-z]').hasMatch(c)) {
      flush();
      out.add(c);
    } else if (c == '-' || c == '+') {
      // 지수 표기(1e-5)의 부호가 아니면 새 숫자의 시작이다.
      final prev = buf.isEmpty ? '' : buf.toString()[buf.length - 1];
      if (prev == 'e' || prev == 'E') {
        buf.write(c);
      } else {
        flush();
        buf.write(c);
      }
    } else if (c == '.' && buf.toString().contains('.')) {
      // `.5.5` 처럼 소수점이 연달아 붙는 축약형
      flush();
      buf.write(c);
    } else {
      buf.write(c);
    }
  }
  flush();
  return out;
}

// ---------------------------------------------------------------------------
// 렌더링
// ---------------------------------------------------------------------------

/// [bounds] 안에 아트를 놓을 정사각형 영역을 고른다.
///
/// 100×100 좌표계라 정사각형이어야 비율이 유지된다.
///
/// **단순히 bounds 중심에 놓으면 안 된다.** 파일럿 렌더에서 10개 중 4개가 깨졌다 —
/// 제주시는 추자도 때문에 bounds 가 위로 늘어나 한라산이 바다에 놓였고, 옹진군은
/// 아트가 아예 안 보였으며, 부산 서구와 종로구는 경계 밖으로 나가 잘렸다.
/// 실제 배치에는 [artTargetRectIn] 을 쓴다. 이 함수는 그 기준선이자 테스트용이다.
Rect artTargetRect(Rect bounds, {double fraction = 0.52}) {
  final side = math.min(bounds.width, bounds.height) * fraction;
  return Rect.fromCenter(center: bounds.center, width: side, height: side);
}

/// 링의 실제 면적 (신발끈 공식). 부호는 버린다 — 감김 방향은 상관없다.
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

/// 링 여러 개 중 **면적이 가장 큰 것의 bounds** 를 고른다.
///
/// 다도해나 부속섬이 있는 지역은 전체 bounds 의 중앙이 바다다. 옹진군 bounds 는
/// 172×107km 인데 육지는 그 1% 미만이고, 제주시는 추자도가 본섬에서 50km 북쪽에 있다.
/// 아트는 **가장 큰 덩어리** 위에 놓아야 한다.
///
/// [rings] 는 지도 좌표계의 정점 배열이고 [scale]·[offset] 은 화면 변환이다.
/// 변환이 평행이동 + 균일 배율이므로 Rect 를 그대로 환산해도 정확하다.
Rect largestRingBounds(
  List<Float32List> rings, {
  required double scale,
  required Offset offset,
}) {
  var best = Rect.zero;
  var bestArea = -1.0;
  for (final ring in rings) {
    if (ring.length < 4) continue;
    var minX = ring[0], maxX = ring[0], minY = ring[1], maxY = ring[1];
    for (var i = 2; i < ring.length; i += 2) {
      final x = ring[i], y = ring[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    // **bounding box 넓이가 아니라 실제 폴리곤 면적으로 고른다.**
    // 가늘고 긴 섬은 bbox 가 커도 면적이 작다. 실측 결과 안산시단원구와
    // 신안군에서 두 기준의 선택이 갈렸다 (신안군: bbox 선택 48.31 vs 최대 79.82).
    final area = _ringArea(ring);
    if (area > bestArea) {
      bestArea = area;
      best = Rect.fromLTRB(minX, minY, maxX, maxY);
    }
  }
  if (bestArea < 0) return Rect.zero;
  return Rect.fromLTRB(
    best.left * scale + offset.dx,
    best.top * scale + offset.dy,
    best.right * scale + offset.dx,
    best.bottom * scale + offset.dy,
  );
}

/// 아트가 실제로 [path] 안에 들어가도록 배치를 정한다.
///
/// [focus] (보통 [largestRingBounds]) 중앙에서 시작해, 정사각형의 표본점이 모두
/// 지역 안에 들어올 때까지 줄인다. 들어맞는 크기를 못 찾으면 최소 크기로 돌려준다 —
/// 작게라도 보이는 편이 경계 밖으로 삐져나오는 것보다 낫다.
///
/// 비용은 레이아웃당 한 번이다. `Path.contains` 를 최대 [steps]×9 회 부르는데,
/// 최악인 옹진군 기준으로도 수 ms 수준이고 결과는 [RegionArtCache] 가 재사용한다.
Rect artTargetRectIn(
  Path path,
  Rect focus, {
  double fraction = 0.52,
  int steps = 10,
}) {
  if (focus.isEmpty) return artTargetRect(path.getBounds(), fraction: fraction);

  var side = math.min(focus.width, focus.height) * fraction;
  final center = focus.center;

  for (var i = 0; i < steps; i++) {
    final r = Rect.fromCenter(center: center, width: side, height: side);
    if (_fitsIn(path, r)) return r;
    side *= 0.82;
  }
  return Rect.fromCenter(center: center, width: side, height: side);
}

/// 아트를 지역 **전체 크기로 키워** 놓는 배치.
///
/// [artTargetRectIn] 은 아트를 지역 안에 넣으려고 줄이는데, 육지가 가늘거나
/// 흩어진 지역에서는 안 보일 만큼 작아진다(종로구·옹진군·부산 서구).
///
/// 이 방식은 반대로 간다 — 아트를 지역을 덮을 만큼 키우고 **지역 모양을 창처럼 써서**
/// 그 너머의 그림을 비춘다. 참조 상품이 셀 내부를 그림으로 채우는 방식과 같다.
/// 아트가 항상 크게 보이는 대신, 지역 모양에 따라 그림의 일부만 보인다.
///
/// 중심은 [focus](가장 큰 링)에 맞춘다. bounds 중심에 맞추면 다도해에서
/// 그림의 알맹이가 바다 쪽에 놓인다.
Rect artTargetFill(Path path, Rect focus, {double fraction = 0.95}) {
  final b = path.getBounds();
  if (b.isEmpty) return Rect.zero;
  final side = math.max(b.width, b.height) * fraction;
  final center = focus.isEmpty ? b.center : focus.center;
  return Rect.fromCenter(center: center, width: side, height: side);
}

/// 사각형의 모서리·변 중점·중심이 모두 [path] 안에 있는지 본다.
///
/// 9개 표본이라 오목한 경계를 완벽히 잡지는 못한다. 아트는 장식이므로
/// 약간 걸치는 것은 허용하고, 크게 삐져나오는 것만 막는 것이 목적이다.
bool _fitsIn(Path path, Rect r) {
  for (final p in [
    r.center,
    r.topLeft, r.topRight, r.bottomLeft, r.bottomRight,
    r.topCenter, r.bottomCenter, r.centerLeft, r.centerRight,
  ]) {
    if (!path.contains(p)) return false;
  }
  return true;
}

/// 파싱한 `Path` 를 `d` 문자열로 캐시한다.
///
/// 지도에 아트를 얹으면 한 번 기록할 때 146개 지역 × 도형 수만큼 파싱이 돈다.
/// 실측 결과 지도 Picture 기록이 0.9ms → 14.7ms 로 늘었고, 그 대부분이 파싱이었다.
/// `d` 는 상수 문자열이고 `Path` 는 그리기만 하므로 재사용해도 안전하다
/// (배경 이동은 `shift` 가 새 Path 를 만든다).
final Map<String, Path> _pathCache = {};

Path _pathFor(String d) => _pathCache.putIfAbsent(d, () => parseSvgPath(d));

/// 테스트에서 캐시 효과를 재기 위해 비운다.
@visibleForTesting
void clearArtPathCache() => _pathCache.clear();

/// [art] 를 [target] 에 맞춰 그린다. [opacity] 로 전체 투명도를 조절한다.
void paintRegionArt(
  Canvas canvas,
  RegionArt art,
  Rect target, {
  double opacity = 1.0,
  ArtVariant variant = ArtVariant.none,
}) {
  if (opacity <= 0) return;
  canvas.save();
  canvas.translate(target.left, target.top);
  canvas.scale(target.width / 100, target.height / 100);
  if (variant.mirror) {
    // 100×100 좌표계 한가운데를 축으로 뒤집는다.
    canvas.translate(100, 0);
    canvas.scale(-1, 1);
  }

  for (final s in art.shapes) {
    Path p;
    if (s.circle case final c?) {
      p = Path()
        ..addOval(Rect.fromCircle(center: Offset(c.$1, c.$2), radius: c.$3));
    } else {
      p = _pathFor(s.d);
    }
    // 배경만 옆으로 민다. 핵심 모티프를 밀면 안전 영역을 벗어난다.
    if (s.layer == ArtLayer.background && variant.bgShift != 0) {
      p = p.shift(Offset(variant.bgShift, 0));
    }

    if (s.fill case final f?) {
      canvas.drawPath(p, Paint()..color = f.withValues(alpha: f.a * opacity));
    }
    if (s.stroke case final st?) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = st.withValues(alpha: st.a * opacity),
      );
    }
  }
  canvas.restore();
}

/// 아트를 [ui.Picture] 로 한 번 기록해 재생만 하도록 캐시한다.
///
/// 긁기 화면은 **입력마다 전체를 다시 그린다**(`scratch_page.dart` 의 밑색·은박·획).
/// 아트를 매번 파싱하고 그리면 그 비용이 입력 프레임마다 얹힌다.
/// 지도 쪽 [MapPictureCache] 와 같은 이유, 같은 방식이다.
class RegionArtCache {
  ui.Picture? _picture;
  RegionArt? _art;
  Rect? _target;
  ArtVariant? _variant;

  ui.Picture obtain(RegionArt art, Rect target,
      {ArtVariant variant = ArtVariant.none}) {
    // **변형도 키에 넣어야 한다.** 빼면 좌우 반전만 다른 두 지역이
    // 같은 그림을 재생한다.
    if (_picture == null ||
        !identical(_art, art) ||
        _target != target ||
        _variant != variant) {
      _picture?.dispose();
      final recorder = ui.PictureRecorder();
      paintRegionArt(Canvas(recorder), art, target, variant: variant);
      _picture = recorder.endRecording();
      _art = art;
      _target = target;
      _variant = variant;
    }
    return _picture!;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _art = null;
    _target = null;
    _variant = null;
  }
}

// ---------------------------------------------------------------------------
// 파일럿 데이터 — 10개 지역
// ---------------------------------------------------------------------------

const _p = ArtPalette.paper;
const _a = ArtPalette.accent;
const _a2 = ArtPalette.accent2;

/// 도시 기본형. `kCityScenes[0]` 과 같다 — 아래 맵이 초기화될 때 이미 만들어져 있다.
final RegionArt _cityBase = _buildCityScene(0);

final Map<ArtCategory, RegionArt> kCategoryArt = {
  // 겹겹이 늘어선 먼 능선(배경) 앞에 앞산 두 봉우리(핵심).
  ArtCategory.mountain: const RegionArt('산', [
    ArtShape(
        'M-25 52 L-8 32 L8 50 L24 30 L42 52 L58 30 L76 52 L92 32 L110 50 '
        'L125 36 L125 62 L-25 62 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M27 70 L41 38 L55 70 Z M49 70 L60 46 L71 70 Z', fill: _p),
    ArtShape('M35 55 L41 38 L47 54', stroke: _a2),
  ]),

  // 물결과 해(배경) 앞에 조개 하나(핵심).
  // 파도만 그리면 '강·호수' 와 구분되지 않아 해변의 표지를 핵심에 둔다.
  ArtCategory.sea: const RegionArt('바다·해변', [
    ArtShape.circle(92, 22, 11,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 66 H125',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M-25 78 C-5 72 10 84 30 78 C50 72 65 84 85 78 C100 74 112 80 125 76',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 90 C-5 84 10 96 30 90 C50 84 65 96 85 90 C100 86 112 92 125 88',
        stroke: _a2, layer: ArtLayer.background),
    // 부챗살은 **아래 힌지에서 방사상으로** 퍼져야 조개로 읽힌다.
    // 세로줄로 그렸더니 수박처럼 보였다.
    ArtShape('M50 70 C32 66 26 50 30 40 C38 35 44 34 50 34 '
        'C56 34 62 35 70 40 C74 50 68 66 50 70 Z', fill: _p),
    ArtShape('M50 70 L36 42 M50 70 L43 37 M50 70 L50 35 '
        'M50 70 L57 37 M50 70 L64 42',
        stroke: _a2, strokeWidth: 3),
  ]),

  // 물결과 먼 섬(배경) 가운데 소나무 얹은 섬(핵심).
  ArtCategory.island: const RegionArt('섬', [
    ArtShape('M-22 60 L-12 48 L-2 60 Z M104 62 L114 46 L124 62 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 78 C-5 72 10 84 30 78 C50 72 65 84 85 78 C100 74 112 80 125 76',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 90 C-5 84 10 96 30 90 C50 84 65 96 85 90 C100 86 112 92 125 88',
        stroke: _a2, layer: ArtLayer.background),
    // 섬을 낮추고 소나무를 크게 잡는다. 나무가 작으면 봉분처럼 보인다.
    ArtShape('M28 70 C32 56 40 48 50 48 C60 48 68 56 72 70 Z', fill: _p),
    ArtShape('M50 48 V40'),
    ArtShape('M41 40 L50 27 L59 40 Z', fill: _a2),
  ]),

  // 뒤쪽 스카이라인(배경) 앞에 건물 세 동(핵심).
  // 도시는 반복이 가장 심해 **장면을 6종으로 만들어 지역 코드로 고른다**
  // (`kCityScenes`). 여기 있는 것은 그중 첫 번째와 같은 기본형이다.
  ArtCategory.city: _cityBase,

  // 기와담이 좌우로 이어지고(배경) 가운데 한옥 한 채(핵심).
  ArtCategory.heritage: const RegionArt('유적·한옥', [
    ArtShape('M-25 62 H125', stroke: _a2, layer: ArtLayer.background),
    ArtShape(
        'M-25 58 C-19 52 -13 52 -7 58 C-1 52 5 52 11 58 C17 52 23 52 29 58 '
        'C35 52 41 52 47 58 C53 52 59 52 65 58 C71 52 77 52 83 58 '
        'C89 52 95 52 101 58 C107 52 113 52 119 58 C121 56 123 55 125 55',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M-25 76 H125', layer: ArtLayer.background),
    ArtShape('M30 54 L50 42 L70 54 Z', fill: _p),
    ArtShape('M28 54 H72'),
    ArtShape('M36 54 h28 v16 h-28 Z', fill: _p),
    ArtShape('M45 70 V60 h10 v10', fill: _a),
    ArtShape('M50 42 V36', stroke: _a2),
  ]),

  // 바위 능선과 먼 김(배경) 앞에 탕과 김(핵심).
  ArtCategory.hotspring: const RegionArt('온천', [
    ArtShape('M-12 30 C-17 24 -7 18 -12 12 M14 26 C9 20 19 14 14 8 '
        'M86 28 C81 22 91 16 86 10 M112 24 C107 18 117 12 112 6',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape(
        'M-25 76 C-15 68 -5 68 5 76 C15 68 25 68 35 76 C45 68 55 68 65 76 '
        'C75 68 85 68 95 76 C105 68 115 68 125 76 L125 86 L-25 86 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M32 52 h36 v8 C68 66 61 72 50 72 C39 72 32 66 32 60 Z', fill: _p),
    ArtShape('M40 46 C35 40 45 34 40 28', stroke: _a),
    ArtShape('M50 46 C45 40 55 34 50 28', stroke: _a),
    ArtShape('M60 46 C55 40 65 34 60 28', stroke: _a),
  ]),

  // 물줄기와 건너편 능선(배경) 위에 아치 돌다리(핵심).
  //
  // 물결만 그리면 '바다' 와 구분되지 않는다. 강·호수의 표지는 **양안이 있다는 것**이고
  // 다리가 그걸 한눈에 보여준다. 징검다리를 먼저 그렸으나 돌 다섯 개가
  // 구름처럼 보여 교체했다.
  ArtCategory.river: const RegionArt('강·호수', [
    ArtShape('M-25 40 C-5 34 10 38 30 32 C50 26 70 36 125 30',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M-25 74 C0 68 25 80 50 74 C75 68 100 78 125 72',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 86 C0 80 25 92 50 86 C75 80 100 90 125 84',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M36 58 V70 M64 58 V70'),
    ArtShape('M36 58 C38 46 62 46 64 58'),
    ArtShape('M27 58 H73', strokeWidth: 6),
    ArtShape('M33 58 V52 M44 58 V52 M56 58 V52 M67 58 V52',
        stroke: _a2, strokeWidth: 3),
  ]),
  // 장면 구성: 논 이랑이 좌우로 반복되고(배경) 가운데 나무 한 그루(핵심).
  // 이랑은 반복 패턴이라 잘려도 "논밭"으로 읽힌다. B 배치에서 원만 남아
  // 무엇인지 알 수 없었던 것을 이 구조로 해결한다.
  //
  // 카테고리는 206개 이상이 재사용하므로 장면 구성 전환의 효과가 가장 크다.
  ArtCategory.field: const RegionArt('들판·농촌', [
    // 배경 — 능선과 논 이랑
    ArtShape('M-25 40 C-5 33 15 37 35 32 C55 27 75 36 125 30',
        stroke: _a2, strokeWidth: 4, layer: ArtLayer.background),
    ArtShape('M-25 72 C0 65 25 77 50 70 C75 63 100 74 125 68',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 86 C0 79 25 91 50 84 C75 77 100 88 125 82',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 100 C0 93 25 105 50 98 C75 91 100 102 125 96',
        stroke: _a2, layer: ArtLayer.background),
    // 핵심 — 나무 한 그루
    ArtShape('M50 72 V52'),
    ArtShape.circle(50, 42, 14, fill: _a),
  ]),
};

/// 3층 랜드마크. **문화재·자연경관만 쓴다.**
///
/// 저작권법 제35조 제2항은 공개 장소 건축저작물의 "판매 목적 복제" 를 예외로 두고 있고,
/// 이는 조달 방식과 무관하며 **스타일화로 회피되지 않는다.** 현대 건축물은 넣지 않는다.
/// 소재별 권리 검토는 `design/art-provenance.md` 참고.
final Map<String, RegionArt> kLandmarkArt = {
  // 11000 서울특별시 — 남산타워 (N서울타워)
  //
  // 장면 구성: 도시 스카이라인과 달(배경) 위로 솟은 타워(핵심).
  // 스카이라인은 톱니 반복이라 좌우가 잘려도 도시로 읽힌다.
  //
  // **⚠ 이 소재만 저작권 예외다.** 1971년 완공된 현대 건축물이라
  // 저작권법 제35조 제2항의 "판매의 목적으로 복제" 예외에 해당하고,
  // "N서울타워" 는 상표이기도 하다. **사용자가 위험을 알고 채택했다(2026-08-13).**
  // 근거와 조건은 `design/art-provenance.md` 참고 — 인앱결제 추가 전 법률 검토가 필요하다.
  //
  // 형태는 특정 사진을 보고 그리지 않고 일반적인 실루엣 인식과 자체 규격으로 그렸다.
  '11000': const RegionArt('남산타워', [
    // 배경 — 달과 도시 스카이라인
    ArtShape.circle(88, 24, 9,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape(
        'M-25 80 L-25 68 L-15 68 L-15 60 L-5 60 L-5 72 L5 72 L5 64 L15 64 '
        'L15 74 L25 74 L25 66 L35 66 L35 76 L45 76 L45 70 L55 70 L55 76 '
        'L65 76 L65 66 L75 66 L75 74 L85 74 L85 62 L95 62 L95 72 L105 72 '
        'L105 68 L115 68 L115 74 L125 74 L125 80 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 80 H125', layer: ArtLayer.background),
    // 핵심 — 타워
    ArtShape('M50 28 V37'),
    ArtShape('M45 45 L47 37 h6 L55 45 Z', fill: _p),
    ArtShape('M41 45 h18 v6 h-18 Z', fill: _p),
    ArtShape('M44 48 h12', stroke: _a, strokeWidth: 3),
    ArtShape('M46 51 L47 72 h6 L54 51 Z', fill: _p),
    ArtShape('M40 72 h20'),
  ]),

  // DK001 독도 — 동도·서도 (자연경관, 천연기념물 제336호)
  //
  // 장면 구성: 동해 일출과 갈매기, 물결(배경) 앞에 두 바위섬(핵심).
  // 물결은 좌우로 반복되는 띠라 잘려도 바다로 읽힌다.
  //
  // **핵심을 두 덩어리로 둔다.** 독도는 하나의 바위가 아니라 서도(높고 뾰족)와
  // 동도(낮고 평평) 두 섬이며, 지도 에셋의 링도 그렇게 둘로 만들었다
  // (`tool/map/merge_spec.py`). 하나로 그리면 긁기 화면에서 모양과 어긋난다.
  //
  // 뾰족한 삼각 기둥은 획이 내부를 먹으므로 윗면을 잘라 폭을 준다 —
  // 옹진군 두무진에서 같은 문제를 이미 겪었다.
  'DK001': const RegionArt('독도', [
    // 배경 — 해, 갈매기, 물결
    ArtShape.circle(78, 26, 11,
        fill: _a, stroke: null, layer: ArtLayer.background),
    // 갈매기는 y 30 아래에 둔다. 팝업 카드가 위아래를 크게 잘라내므로
    // 더 올리면 머리만 남아 새로 읽히지 않는다 (렌더해 보고 내렸다).
    ArtShape('M13 37 C16 33 20 33 23 37 M33 31 C36 27 40 27 43 31',
        strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M-25 82 C-5 76 10 88 30 82 C50 76 65 88 85 82 C100 78 112 84 125 80',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 94 C-5 88 10 100 30 94 C50 88 65 100 85 94 C100 90 112 96 125 92',
        stroke: _a2, layer: ArtLayer.background),
    // 핵심 — 서도(왼쪽, 뾰족하고 높다)와 동도(오른쪽, 낮고 윗면이 평평하다)
    //
    // 실루엣을 일부러 다르게 준다. 둘 다 봉우리로 그렸더니 백령도 두무진과
    // 구분되지 않는 "바다 위 바위" 로만 읽혔다. 동도의 평평한 윗면이 독도의
    // 실제 특징이자 유일한 식별 신호다.
    ArtShape('M29 70 L35 46 L41 42 L46 52 L48 70 Z', fill: _p),
    ArtShape('M54 70 L57 57 L70 55 L72 70 Z', fill: _p),
    ArtShape('M27 70 h46', stroke: _a2),
  ]),

  // 28710 강화군 — 강화 고인돌 (세계유산, 청동기)
  //
  // 장면 구성: 낮은 언덕과 억새(배경) 위 탁자식 고인돌(핵심).
  '28710': const RegionArt('강화 고인돌', [
    ArtShape('M-25 76 C0 70 20 72 40 68 C60 64 80 70 125 66 L125 96 L-25 96 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-16 68 C-18 60 -14 54 -16 48 M8 66 C6 58 10 52 8 46 '
        'M92 68 C90 60 94 54 92 48 M114 66 C112 58 116 52 114 46',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M28 46 L72 42 L70 57 L30 61 Z', fill: _p),
    ArtShape('M36 61 h10 v9 h-10 Z', fill: _p),
    ArtShape('M55 59 h10 v11 h-10 Z', fill: _p),
    ArtShape('M32 70 h36'),
  ]),

  // 28720 옹진군 — 백령도 두무진 (자연경관)
  //
  // 장면 구성: 바다 물결과 갈매기(배경) 앞에 기암 절벽 세 기둥(핵심).
  // 옹진군은 다도해라 긁기 화면에서 가장 큰 섬에만 아트가 놓인다.
  '28720': const RegionArt('백령도 두무진', [
    ArtShape('M10 22 C13 18 17 18 20 22 M78 26 C81 22 85 22 88 26',
        strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M-25 78 C-5 72 10 84 30 78 C50 72 65 84 85 78 C100 74 112 80 125 76',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 90 C-5 84 10 96 30 90 C50 84 65 96 85 90 C100 86 112 92 125 88',
        stroke: _a2, layer: ArtLayer.background),
    // 뾰족한 삼각형은 획이 내부를 먹는다. 윗면을 평평하게 잘라 폭을 준다.
    ArtShape('M28 70 L33 44 L39 44 L44 70 Z', fill: _p),
    ArtShape('M42 70 L47 34 L53 34 L58 70 Z', fill: _p),
    ArtShape('M56 70 L60 48 L66 48 L71 70 Z', fill: _p),
    ArtShape('M32 70 h40', stroke: _a2),
  ]),

  // 28000 통합 단위 · 대표 원소재: 계양구 — 계양산 (자연경관)
  //
  // 장면 구성: 도시 스카이라인(배경) 뒤로 솟은 산(핵심).
  // 도시 한가운데 있는 산이라는 성격을 배경으로 드러낸다.
  '28000': const RegionArt('계양산', [
    ArtShape(
        'M-25 84 L-25 74 L-13 74 L-13 68 L-1 68 L-1 78 L11 78 L11 70 L23 70 '
        'L23 80 L35 80 L35 72 L47 72 L47 78 L59 78 L59 70 L71 70 L71 80 '
        'L83 80 L83 72 L95 72 L95 78 L107 78 L107 70 L125 70 L125 84 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 84 H125', layer: ArtLayer.background),
    ArtShape('M28 70 L42 36 L52 52 L60 42 L72 70 Z', fill: _p),
    ArtShape('M36 52 L42 36 L47 47', stroke: _a2),
  ]),

  // 41670 여주시 — 세종대왕릉(영릉) (조선왕릉, 세계유산)
  //
  // 장면 구성: 소나무 숲 띠(배경) 앞에 봉분과 석물(핵심).
  '41670': const RegionArt('세종대왕릉', [
    ArtShape(
        'M-25 50 L-15 32 L-5 48 L5 34 L15 48 L25 33 L35 48 L45 34 L55 48 '
        'L65 33 L75 48 L85 35 L95 48 L105 34 L115 48 L125 36 L125 56 L-25 56 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 88 H125', layer: ArtLayer.background),
    ArtShape('M34 62 C34 45 66 45 66 62 Z', fill: _p),
    ArtShape('M32 62 h36'),
    ArtShape('M39 70 V63 h5 v7 Z', fill: _p),
    ArtShape('M56 70 V63 h5 v7 Z', fill: _p),
    ArtShape('M30 70 h40'),
  ]),

  // 41610 광주시 — 남한산성 (세계유산, 조선)
  //
  // 장면 구성: 능선을 따라 뻗는 성벽(배경) 가운데 성문(핵심).
  // 팔달문과 달리 **산성**이라는 성격을 능선 배경으로 구분한다.
  '41610': const RegionArt('남한산성', [
    ArtShape(
        'M-25 74 C-5 66 15 70 35 62 C50 56 62 58 75 64 C95 72 108 68 125 70 '
        'L125 96 L-25 96 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 64 C-5 56 15 60 35 52 C50 46 62 48 75 54 C95 62 108 58 125 60',
        stroke: _a2, strokeWidth: 4, layer: ArtLayer.background),
    ArtShape('M34 70 V56 h32 v14 Z', fill: _p),
    ArtShape('M36 56 v-5 h6 v5 M47 56 v-5 h6 v5 M58 56 v-5 h6 v5',
        stroke: _a2, strokeWidth: 3),
    ArtShape('M44 70 V63 C44 58 56 58 56 63 V70 Z', fill: _a),
  ]),

  // 41830 양평군 — 두물머리 (자연경관)
  //
  // 장면 구성: 두 물줄기가 만나는 흐름(배경) 앞에 느티나무(핵심).
  // 남한강과 북한강이 합쳐지는 곳이라는 이름의 뜻을 배경이 보여준다.
  '41830': const RegionArt('두물머리', [
    ArtShape('M-25 36 C0 46 20 56 44 64', stroke: _a2, layer: ArtLayer.background),
    ArtShape('M125 36 C100 46 80 56 56 64', stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 80 C0 74 25 86 50 80 C75 74 100 84 125 78',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 92 C0 86 25 98 50 92 C75 86 100 96 125 90',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M50 70 V52'),
    ArtShape.circle(50, 42, 14, fill: _a2),
    ArtShape('M40 70 h20'),
  ]),

  // 41820 가평군 — 자라섬·북한강 (자연경관)
  //
  // 장면 구성: 강 물결과 먼 산(배경) 가운데 강섬(핵심).
  // 바다 섬과 구분하려고 배경을 물결이 아니라 **강과 산**으로 둔다.
  '41820': const RegionArt('자라섬·북한강', [
    ArtShape('M-25 44 L-8 26 L8 42 L24 24 L40 44 L56 26 L72 44 L88 28 L104 42 '
        'L125 30 L125 52 L-25 52 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 78 C0 72 25 84 50 78 C75 72 100 82 125 76',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 90 C0 84 25 96 50 90 C75 84 100 94 125 88',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M30 68 C34 58 42 54 50 54 C58 54 66 58 70 68 Z', fill: _p),
    ArtShape('M42 54 V48'),
    ArtShape('M36 48 L42 37 L48 48 Z', fill: _a2),
    ArtShape('M59 54 V50'),
    ArtShape('M54 50 L59 41 L64 50 Z', fill: _a2),
  ]),

  // 51210 속초시 — 설악산 (국립공원, 자연경관)
  //
  // 장면 구성: 겹겹이 뻗은 능선(배경) 앞에 울산바위처럼 각진 암봉(핵심).
  // '산' 카테고리와 달리 **바위 봉우리**로 설악을 구분한다.
  '51210': const RegionArt('설악산', [
    ArtShape(
        'M-25 62 L-10 42 L4 60 L18 40 L34 60 L48 38 L62 60 L78 42 L92 60 '
        'L108 40 L125 58 L125 76 L-25 76 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M28 70 L36 44 L42 52 L48 32 L56 50 L62 40 L72 70 Z', fill: _p),
    ArtShape('M42 52 L48 32 L54 46', stroke: _a2),
  ]),

  // 51760 평창군 — 월정사 팔각구층석탑 (국보, 고려)
  //
  // 장면 구성: 전나무 숲길(배경) 가운데 구층석탑(핵심).
  '51760': const RegionArt('월정사 구층석탑', [
    ArtShape(
        'M-25 52 L-16 28 L-7 52 L4 30 L15 52 L26 29 L37 52 L63 52 L74 29 '
        'L85 52 L96 30 L107 52 L118 28 L125 44 L125 60 L-25 60 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 78 H125', layer: ArtLayer.background),
    // 층을 잘게 쌓으면 획이 내부를 먹어 검은 덩어리가 된다.
    // 층수를 줄이고 획을 얇게 해 각 층이 보이게 한다.
    ArtShape('M39 70 h22 v-7 h-22 Z', fill: _p, strokeWidth: 3),
    ArtShape('M41 63 h18 v-7 h-18 Z', fill: _p, strokeWidth: 3),
    ArtShape('M43 56 h14 v-7 h-14 Z', fill: _p, strokeWidth: 3),
    ArtShape('M45 49 h10 v-7 h-10 Z', fill: _p, strokeWidth: 3),
    ArtShape('M50 42 V34'),
    ArtShape.circle(50, 31, 3.5, fill: _a, stroke: null),
    ArtShape('M35 70 h30'),
  ]),

  // 43720 보은군 — 법주사 팔상전 (국보, 조선)
  //
  // 장면 구성: 속리산 능선(배경) 앞에 오층 목탑(핵심).
  // 층마다 처마가 뻗어 석탑(월정사)과 구분된다.
  '43720': const RegionArt('법주사 팔상전', [
    ArtShape('M-25 66 C-5 56 12 62 30 52 C45 44 58 46 72 54 C92 64 108 58 125 62 '
        'L125 88 L-25 88 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    // 지붕 사이가 좁은데 획이 굵으면 층이 붙어 검은 덩어리가 된다.
    ArtShape('M30 45 L50 33 L70 45 Z', fill: _p, strokeWidth: 3),
    ArtShape('M33 56 L50 46 L67 56 Z', fill: _p, strokeWidth: 3),
    ArtShape('M36 66 L50 57 L64 66 Z', fill: _p, strokeWidth: 3),
    ArtShape('M44 70 V64 h12 v6', fill: _a),
    ArtShape('M36 70 h28'),
  ]),

  // 43800 단양군 — 도담삼봉 (명승, 자연경관)
  //
  // 장면 구성: 남한강 물결(배경) 위에 솟은 세 봉우리(핵심).
  // 가운데가 높고 좌우가 낮은 실제 형태를 따른다.
  '43800': const RegionArt('도담삼봉', [
    ArtShape('M-25 74 C0 68 25 80 50 74 C75 68 100 78 125 72',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 86 C0 80 25 92 50 86 C75 80 100 90 125 84',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 98 C0 92 25 104 50 98 C75 92 100 102 125 96',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M30 70 C32 58 36 52 39 52 C42 52 46 58 48 70 Z', fill: _p),
    ArtShape('M42 70 C45 50 48 32 50 32 C52 32 55 50 58 70 Z', fill: _p),
    ArtShape('M52 70 C54 58 58 54 61 54 C64 54 68 60 70 70 Z', fill: _p),
  ]),

  // 44760 부여군 — 정림사지 오층석탑 (국보, 백제)
  //
  // 장면 구성: 백마강 물굽이와 절터 기단(배경) 가운데 오층석탑(핵심).
  // 백제 석탑은 지붕돌이 얇고 넓게 뻗는다 — 그 비례를 따른다.
  '44760': const RegionArt('정림사지 오층석탑', [
    ArtShape('M-25 80 C0 74 25 86 50 80 C75 74 100 84 125 78',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 66 H125', stroke: _a2, strokeWidth: 3,
        layer: ArtLayer.background),
    ArtShape('M-25 92 H125', layer: ArtLayer.background),
    // 층을 다섯 개 쌓으면 획이 내부를 먹어 검은 덩어리가 된다.
    // 층수를 줄이고 획을 얇게 하되, **얇고 넓은 지붕돌**이라는 백제 석탑의
    // 비례는 유지한다.
    ArtShape('M35 70 h30 v-7 h-30 Z', fill: _p, strokeWidth: 3),
    ArtShape('M32 63 h36 v-6 h-36 Z', fill: _p, strokeWidth: 3),
    ArtShape('M42 57 h16 v-7 h-16 Z', fill: _p, strokeWidth: 3),
    ArtShape('M34 50 h32 v-6 h-32 Z', fill: _p, strokeWidth: 3),
    ArtShape('M44 44 h12 v-6 h-12 Z', fill: _p, strokeWidth: 3),
    ArtShape('M50 38 V32'),
  ]),

  // 44150 공주시 — 공산성 (사적, 백제 왕도)
  //
  // 장면 구성: 금강 물줄기(배경) 위 언덕을 감싼 성벽과 누각(핵심).
  '44150': const RegionArt('공산성', [
    ArtShape('M-25 84 C0 78 25 90 50 84 C75 78 100 88 125 82',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 96 C0 90 25 102 50 96 C75 90 100 100 125 94',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 74 C-5 68 15 70 35 62 C50 56 62 58 75 64 C95 72 108 70 125 72 '
        'L125 84 L-25 84 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M30 68 C34 56 66 56 70 68 Z', fill: _p),
    ArtShape('M34 56 h32', strokeWidth: 4),
    ArtShape('M38 48 L50 40 L62 48 Z', fill: _p),
    ArtShape('M42 48 h16 v8 h-16 Z', fill: _p),
    ArtShape('M48 56 V50 h4 v6', fill: _a),
  ]),

  // 30000 통합 단위 · 대표 원소재: 유성구 — 계룡산 (국립공원, 자연경관)
  //
  // 장면 구성: 닭 볏처럼 이어진 능선(배경·핵심).
  // 이름 그대로 봉우리가 연달아 솟은 형태를 핵심에 둔다.
  '30000': const RegionArt('계룡산', [
    ArtShape('M-25 68 C-5 62 15 66 35 60 C50 55 62 57 75 62 C95 68 108 66 125 68 '
        'L125 88 L-25 88 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M28 70 L34 52 L39 60 L45 40 L51 58 L57 44 L63 60 L72 70 Z',
        fill: _p),
    ArtShape('M39 60 L45 40 L50 52', stroke: _a2),
  ]),

  // 36110 세종시 — 금강 굽이 (자연경관)
  //
  // 장면 구성: 강이 크게 휘도는 물굽이(핵심)와 양안 둔치(배경).
  // 도시 아이콘과 겹치지 않도록 건물을 넣지 않는다.
  // 강을 **선 두 개**로 그렸더니 마주보는 곡선이 X 자로 보였다.
  // 강은 면으로 그려야 물줄기로 읽힌다.
  '36110': const RegionArt('금강 굽이', [
    ArtShape('M-25 96 V54 C-12 50 0 54 12 50 V96 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M125 96 V54 C112 50 100 54 88 50 V96 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M0 50 C-2 42 2 36 0 30 M-16 52 C-18 44 -14 38 -16 32 '
        'M100 50 C98 42 102 36 100 30 M116 52 C114 44 118 38 116 32',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M30 26 C46 40 30 56 46 74 L62 74 C46 56 62 40 46 26 Z', fill: _p),
    ArtShape('M40 42 C44 46 48 46 52 42', stroke: _a2, strokeWidth: 3),
    ArtShape('M38 58 C42 62 46 62 50 58', stroke: _a2, strokeWidth: 3),
  ]),

  // 52190 남원시 — 광한루 (보물, 조선)
  //
  // 장면 구성: 연못과 오작교(배경) 앞에 누각(핵심).
  // 기둥 위에 올린 **누각**이라 지면에 붙은 한옥과 구분된다.
  '52190': const RegionArt('광한루', [
    ArtShape('M-25 84 C0 78 25 90 50 84 C75 78 100 88 125 82',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 78 C-12 70 -2 70 10 78 C22 70 32 70 44 78 C56 70 66 70 78 78 '
        'C90 70 100 70 112 78 C118 74 122 73 125 74',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M30 50 L50 38 L70 50 Z', fill: _p),
    ArtShape('M28 50 H72'),
    ArtShape('M34 50 h32 v10 h-32 Z', fill: _p),
    ArtShape('M36 60 V70 M46 60 V70 M56 60 V70 M64 60 V70', strokeWidth: 4),
    ArtShape('M30 70 h40'),
  ]),

  // 52800 부안군 — 채석강 (명승, 자연경관)
  //
  // 장면 구성: 바다 물결(배경) 앞에 책을 쌓은 듯한 층암 절벽(핵심).
  // 가로 층리가 반복이라 잘려도 절벽으로 읽힌다.
  '52800': const RegionArt('채석강', [
    ArtShape('M-25 82 C-5 76 10 88 30 82 C50 76 65 88 85 82 C100 78 112 84 125 80',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 94 C-5 88 10 100 30 94 C50 88 65 100 85 94 C100 90 112 96 125 92',
        stroke: _a2, layer: ArtLayer.background),
    // 반듯한 사각형은 절벽이 아니라 상자로 보인다. 윗면을 들쭉날쭉하게 둔다.
    ArtShape('M26 72 h46 V40 L62 36 L50 40 L38 35 L26 39 Z', fill: _p),
    ArtShape('M26 48 h46 M26 56 h46 M26 64 h46', stroke: _a2, strokeWidth: 3),
  ]),

  // 12210 동구(광주) — 무등산 (국립공원, 자연경관)
  //
  // 장면 구성: 도시 능선(배경) 위로 완만한 산과 주상절리 기둥(핵심).
  // 입석대·서석대의 **돌기둥**이 다른 산과 구분되는 표지다.
  '12210': const RegionArt('무등산', [
    ArtShape('M-25 74 C-5 68 15 72 35 66 C50 62 62 64 75 68 C95 74 108 72 125 74 '
        'L125 92 L-25 92 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M26 66 C34 46 66 46 74 66 Z', fill: _p),
    ArtShape('M38 66 V50 h5 v16 M47 66 V46 h5 v20 M56 66 V50 h5 v16',
        fill: _p),
    ArtShape('M28 70 h44'),
  ]),

  // 27000 통합 단위 · 대표 원소재: 동구(대구) — 팔공산 갓바위 (보물, 통일신라)
  //
  // 장면 구성: 팔공산 능선(배경) 앞에 갓 쓴 좌불(핵심).
  // 머리 위 **판석(갓)** 이 이름이자 표지다.
  '27000': const RegionArt('팔공산 갓바위', [
    ArtShape('M-25 70 C-5 62 15 66 35 58 C50 52 62 54 75 60 C95 68 108 66 125 68 '
        'L125 90 L-25 90 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    // **핵심을 안전 영역보다 더 안쪽으로 모았다** (2026-08-21).
    //
    // 광역시 통합으로 대구에 군위군이 붙어 도형이 세로로 길어지자, 좌불이
    // 좌우로 잘려 **흰 덩어리로만 보였다**(실기기 확인). 아트 사각형은 도형의
    // 긴 변 기준이라 좁은 허리에서 폭이 1.5배 넘친다.
    //
    // 배치 규칙을 고치는 안은 폐기했다 — 두 가지를 렌더해 봤는데 대구는 거의
    // 안 나아지고 서울 남산타워가 오히려 잘렸다. **갓바위 아트는 대구에서만
    // 쓰므로 여기만 줄이면 다른 지역에 영향이 없다.**
    ArtShape('M38 38 h24 v4 h-24 Z', fill: _p),
    ArtShape('M45 42 C45 35 55 35 55 42 Z', fill: _p),
    ArtShape('M40 65 C40 51 45 45 50 45 C55 45 60 51 60 65 Z', fill: _p),
    ArtShape('M46 52 h8', stroke: _a, strokeWidth: 3),
    ArtShape('M37 65 h26'),
  ]),

  // 48220 통영시 — 한려수도 (자연경관)
  //
  // 장면 구성: 겹겹이 늘어선 섬 실루엣(배경) 앞에 돛단배(핵심).
  // 통영은 다도해라 긁기 화면에서 가장 큰 섬에만 아트가 놓인다.
  '48220': const RegionArt('한려수도', [
    ArtShape('M-25 58 C-12 46 2 46 14 58 C26 48 38 48 50 58 C62 48 74 48 86 58 '
        'C98 48 110 48 125 58 L125 72 L-25 72 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 84 C0 78 25 90 50 84 C75 78 100 88 125 82',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M50 66 V30'),
    ArtShape('M50 32 L68 58 H50 Z', fill: _p),
    ArtShape('M50 38 L34 58 H50 Z', fill: _p),
    ArtShape('M34 66 C38 72 62 72 66 66 Z', fill: _p),
  ]),

  // 48890 합천군 — 해인사 장경판전 (국보·세계유산, 조선)
  //
  // 장면 구성: 가야산 능선(배경) 앞에 살창이 늘어선 판전(핵심).
  // **격자 살창**이 이 건물의 표지라 일반 한옥과 구분된다.
  '48890': const RegionArt('해인사 장경판전', [
    ArtShape('M-25 68 C-5 60 15 64 35 56 C50 50 62 52 75 58 C95 66 108 64 125 66 '
        'L125 88 L-25 88 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M28 48 L50 38 L72 48 Z', fill: _p),
    ArtShape('M32 48 h36 v22 h-36 Z', fill: _p),
    ArtShape('M37 53 h6 v12 h-6 Z M47 53 h6 v12 h-6 Z M57 53 h6 v12 h-6 Z',
        fill: _a2),
    ArtShape('M28 70 h44'),
  ]),

  // 48170 진주시 — 진주성 촉석루 (문화재, 조선)
  //
  // 장면 구성: 남강 물줄기(배경) 위 절벽에 선 누각(핵심).
  // 광한루와 달리 **성벽 위**에 있다는 점이 다르다.
  '48170': const RegionArt('진주성 촉석루', [
    ArtShape('M-25 86 C0 80 25 92 50 86 C75 80 100 90 125 84',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 96 C0 90 25 102 50 96 C75 90 100 100 125 94',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 80 H125', strokeWidth: 4, layer: ArtLayer.background),
    ArtShape('M30 44 L50 32 L70 44 Z', fill: _p),
    ArtShape('M28 44 H72'),
    ArtShape('M34 44 h32 v10 h-32 Z', fill: _p),
    ArtShape('M36 54 V64 M46 54 V64 M56 54 V64 M64 54 V64', strokeWidth: 4),
    ArtShape('M30 64 h40 v8 h-40 Z', fill: _p),
  ]),

  // 26000 통합 단위 · 대표 원소재: 해운대구 — 해운대 해변 (자연경관)
  //
  // 장면 구성: 파도와 해(배경) 앞에 파라솔(핵심).
  // '바다·해변' 카테고리는 조개라 겹치지 않는다.
  '26000': const RegionArt('해운대 해변', [
    ArtShape.circle(90, 24, 10,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 76 C-5 70 10 82 30 76 C50 70 65 82 85 76 C100 72 112 78 125 74',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 88 C-5 82 10 94 30 88 C50 82 65 94 85 88 C100 84 112 90 125 86',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 66 H125', stroke: _a2, strokeWidth: 3,
        layer: ArtLayer.background),
    ArtShape('M50 70 V44'),
    ArtShape('M30 44 C34 32 66 32 70 44 Z', fill: _p),
    ArtShape('M40 38 C42 34 58 34 60 38', stroke: _a, strokeWidth: 3),
    ArtShape('M40 70 h20'),
  ]),

  // 31000 통합 단위 · 대표 원소재: 울주군 — 반구대 암각화 (국보, 선사)
  //
  // 장면 구성: 절벽면(배경) 위에 새겨진 고래와 사람(핵심).
  // 바위그림이라는 성격을 살려 **선각 실루엣**으로 그린다.
  '31000': const RegionArt('반구대 암각화', [
    // 암벽면. 가로 결을 넣지 않으면 그냥 배경색으로 보인다.
    ArtShape('M-25 22 H125 V80 H-25 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 34 H125 M-25 48 H125 M-25 62 H125 M-25 74 H125',
        strokeWidth: 2, layer: ArtLayer.background),
    ArtShape('M-25 90 C0 84 25 96 50 90 C75 84 100 94 125 88',
        stroke: _a2, layer: ArtLayer.background),
    // 새긴 고래. 사람 형상을 함께 넣었더니 다리가 고래에 붙은 것처럼 보여 뺐다.
    ArtShape('M31 52 C37 43 57 43 64 50 C68 54 68 57 64 59 C57 65 37 63 31 55 Z',
        fill: _p),
    ArtShape('M64 50 L70 44 L70 60 L64 59', fill: _p),
    ArtShape.circle(40, 51, 2.4, fill: ArtPalette.ink, stroke: null),
  ]),

  // 47130 경주시 — 첨성대 (국보, 7세기)
  //
  // 장면 구성: 별이 흩뿌려진 밤하늘(배경) 위에 첨성대(핵심).
  // 천문대라는 성격이 배경으로 드러나고, 별은 흩뿌림이라 일부만 보여도 읽힌다.
  '47130': const RegionArt('첨성대', [
    // 배경 — 언덕과 별
    ArtShape('M-25 88 C0 76 24 92 50 84 C76 76 100 90 125 82 L125 125 L-25 125 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(10, 16, 3,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(31, 8, 2.5,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(74, 13, 3,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(92, 30, 2.5,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(16, 44, 2.5,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(88, 60, 2.5,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape.circle(6, 70, 2,
        fill: _a, stroke: null, layer: ArtLayer.background),
    // 핵심 — 첨성대
    ArtShape('M38 71 C36 53 40 39 50 32 C60 39 64 53 62 71 Z', fill: _p),
    ArtShape('M46 50 h8 v8 h-8 Z', fill: _a),
    ArtShape('M42 32 h16', stroke: _a2),
    ArtShape('M45 28 h10'),
    ArtShape('M34 71 h32'),
  ]),

  // 41115 수원시팔달구 — 수원화성 팔달문 (사적, 18세기)
  //
  // 장면 구성: 성벽이 좌우로 뻗고(배경) 가운데 문루(핵심).
  // 여장(성벽 위 凸 모양)이 반복이라 좌우가 잘려도 "성곽"으로 읽힌다.
  // B 배치에서 지붕만 남아 알아보기 어려웠던 것을 이 구조로 해결한다.
  '41115': const RegionArt('수원화성 팔달문', [
    // 배경 — 좌우로 뻗는 성벽과 여장
    ArtShape('M-25 62 H32 V76 H-25 Z', fill: _p, layer: ArtLayer.background),
    ArtShape('M68 62 H125 V76 H68 Z', fill: _p, layer: ArtLayer.background),
    ArtShape(
        'M-20 62 v-7 h7 v7 M-6 62 v-7 h7 v7 M8 62 v-7 h7 v7 M22 62 v-7 h7 v7',
        stroke: _a2, strokeWidth: 4, layer: ArtLayer.background),
    ArtShape(
        'M71 62 v-7 h7 v7 M85 62 v-7 h7 v7 M99 62 v-7 h7 v7 M113 62 v-7 h7 v7',
        stroke: _a2, strokeWidth: 4, layer: ArtLayer.background),
    ArtShape('M-25 76 H125', layer: ArtLayer.background),
    // 핵심 — 문루
    ArtShape('M36 72 V57 h28 v15', fill: _p),
    ArtShape('M44 72 V64 C44 58 56 58 56 64 V72 Z', fill: _a),
    ArtShape('M30 57 L50 47 L70 57 Z', fill: _p),
    ArtShape('M37 47 L50 40 L63 47', fill: _p, stroke: _a2),
    ArtShape('M50 40 V34', stroke: _a2),
  ]),

  // 47170 안동시 — 하회마을 (세계유산, 조선)
  //
  // 장면 구성: 마을을 휘감는 물돌이와 솔숲(배경) 앞에 초가 한 채(핵심).
  // 하회(河回)라는 이름 자체가 물이 돌아 흐른다는 뜻이라 물굽이가 배경으로 맞다.
  // 솔숲은 삼각형 반복이라 좌우가 잘려도 읽힌다.
  '47170': const RegionArt('하회마을', [
    // 배경 — 솔숲 띠와 물돌이
    //
    // 나무를 하나씩 떼어 그렸더니 삼각형과 줄기가 분리돼 **화살표처럼** 보였다.
    // 톱니 모양으로 이어 붙인 띠가 숲으로 읽힌다.
    ArtShape(
        'M-25 46 L-15 26 L-5 44 L5 28 L15 44 L25 30 L35 44 L45 27 L55 44 '
        'L65 30 L75 44 L85 27 L95 44 L105 30 L115 44 L125 30 L125 52 L-25 52 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 78 C5 62 30 92 55 76 C78 62 100 80 125 70',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 90 C5 74 30 104 55 88 C78 74 100 92 125 82',
        stroke: _a2, layer: ArtLayer.background),
    // 핵심 — 초가 한 채
    ArtShape('M36 52 C40 40 60 40 64 52 Z', fill: _p),
    ArtShape('M38 52 h24 v18 h-24 Z', fill: _p),
    ArtShape('M45 70 V60 h10 v10', fill: _a),
  ]),

  // 50000 제주특별자치도 — 돌하르방 (조선 후기 석상)
  //
  // 2026-08-14 통합으로 코드가 50110(제주시) → 50000(제주 전체) 이 됐다.
  //
  // 장면 구성: 오름 능선과 현무암 밭담(배경) 앞에 돌하르방(핵심).
  // 밭담은 반복 패턴이라 좌우가 잘려도 제주로 읽힌다.
  //
  // 제주는 시군구가 2개뿐이라 랜드마크를 하나만 둔다(2026-08-13 사용자 결정).
  // 이전에 만든 한라산 아트는 이 결정으로 목록에서 빠졌다.
  '50000': const RegionArt('돌하르방', [
    // 배경 — 오름 능선과 밭담
    ArtShape('M-25 40 C-5 32 12 36 30 30 C48 24 64 34 125 28',
        stroke: _a2, strokeWidth: 4, layer: ArtLayer.background),
    ArtShape('M-25 82 H125', stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 92 H125', stroke: _a2, layer: ArtLayer.background),
    ArtShape(
        'M-18 82 V92 M-2 82 V92 M14 82 V92 M30 82 V92 M46 82 V92 '
        'M62 82 V92 M78 82 V92 M94 82 V92 M110 82 V92',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    // 핵심 — 돌하르방
    ArtShape('M39 45 C40 34 44 29 50 29 C56 29 60 34 61 45 Z', fill: _p),
    ArtShape('M40 45 C38 58 41 70 42 72 H58 C59 70 62 58 60 45 Z', fill: _p),
    ArtShape.circle(45, 52, 3.2, fill: ArtPalette.ink, stroke: null),
    ArtShape.circle(55, 52, 3.2, fill: ArtPalette.ink, stroke: null),
    ArtShape('M50 55 v6'),
    ArtShape('M44 66 h5 M51 66 h5', stroke: _a, strokeWidth: 4),
  ]),

  // 12150 순천시 — 순천만 갈대밭 (습지, 자연경관)
  //
  // 장면 구성: 갯벌 물길과 철새(배경) 사이에 갈대 세 포기(핵심).
  // 물길은 구불구불한 곡선 반복이라 잘려도 갯벌로 읽힌다.
  // 이전 구성은 갈대가 좌우로 넓게 퍼져 있어 잘리면 줄기만 남았다.
  '12150': const RegionArt('순천만 갈대밭', [
    // 배경 — 갯벌 물길과 철새
    ArtShape('M-25 66 C0 60 25 72 50 66 C75 60 100 70 125 64',
        stroke: _a2, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('M-25 78 C0 70 25 86 50 78 C75 70 100 84 125 76',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 90 C0 82 25 98 50 90 C75 82 100 96 125 88',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M8 20 C11 16 15 16 18 20 M28 13 C31 9 35 9 38 13 '
        'M84 22 C87 18 91 18 94 22 M104 15 C107 11 111 11 114 15',
        strokeWidth: 3, layer: ArtLayer.background),
    // 핵심 — 갈대 세 포기
    ArtShape('M41 72 C39 58 43 48 45 42'),
    ArtShape('M45 42 C40 37 38 32 40 29 C45 31 47 36 45 42 Z', fill: _a),
    ArtShape('M50 72 C48 56 52 44 54 38'),
    ArtShape('M54 38 C49 33 47 30 49 27 C54 29 56 33 54 38 Z', fill: _a),
    ArtShape('M60 72 C59 58 62 48 63 43'),
    ArtShape('M63 43 C58 38 56 34 58 31 C63 33 65 38 63 43 Z', fill: _a),
  ]),

  // 47940 울릉군 — 울릉도 (자연경관)
  //
  // 장면 구성: 바다 물결과 해, 멀리 부속 섬(배경) 가운데 울릉도 본섬(핵심).
  // 물결은 반복이라 잘려도 바다로 읽힌다.
  //
  // 참고: 울릉군 링은 1개이고 **독도를 포함하지 않는다** — 원본 GeoJSON 에도 없다.
  // 2026-08-14 M15 로 독도를 **별도 긁기 단위 `DK001`** 로 신설해 이 어긋남은
  // 해소됐다. 여기 배경의 먼 섬은 특정 섬이 아니라 동해 원경이다.
  '47940': const RegionArt('울릉도', [
    // 배경 — 해, 먼 섬, 물결
    ArtShape.circle(88, 24, 12,
        fill: _a, stroke: null, layer: ArtLayer.background),
    ArtShape('M-20 62 L-10 46 L0 62 Z M100 64 L112 44 L124 64 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    ArtShape('M-25 80 C-5 74 10 86 30 80 C50 74 65 86 85 80 C100 76 112 82 125 78',
        stroke: _a2, layer: ArtLayer.background),
    ArtShape('M-25 92 C-5 86 10 98 30 92 C50 86 65 98 85 92 C100 88 112 94 125 90',
        stroke: _a2, layer: ArtLayer.background),
    // 핵심 — 울릉도 본섬
    ArtShape('M30 70 L42 40 L50 52 L58 34 L70 70 Z', fill: _p),
    ArtShape('M38 52 L42 40 L46 48', stroke: _a2),
  ]),
};

// ---------------------------------------------------------------------------
// 장면 변형
// ---------------------------------------------------------------------------

/// 같은 카테고리가 반복될 때 그림을 흩뜨리는 변형.
///
/// 도시로 배정된 지역이 76개다. 배정은 맞지만 장면이 하나뿐이면 **같은 그림을
/// 24번 보게 된다.** 카테고리를 억지로 흩뜨리면 배정이 틀려지므로,
/// 카테고리는 그대로 두고 **장면 쪽에 변화를 준다** (2026-08-13 사용자 결정).
///
/// **난수를 쓰지 않는다.** 지역 코드에서 결정론적으로 뽑으므로 같은 지역은
/// 언제나 같은 그림이다. 앱을 다시 켰다고 서울 강남이 다른 모습이면 안 된다.
@immutable
class ArtVariant {
  const ArtVariant(this.mirror, this.bgShift, this.layout);

  /// 변형 없음. 랜드마크는 지역마다 그림이 달라 변형이 필요 없다.
  static const none = ArtVariant(false, 0, 0);

  /// 좌우 반전.
  final bool mirror;

  /// 배경만 좌우로 미는 양. 핵심 모티프는 움직이지 않는다 —
  /// 안전 영역을 벗어나면 잘렸을 때 알아볼 수 없게 되기 때문이다.
  final double bgShift;

  /// 카테고리별 배치 번호. 도시는 건물 높이 조합을 고른다.
  final int layout;

  /// 지역 코드에서 뽑는다.
  ///
  /// `String.hashCode` 는 실행마다 달라질 수 있어 쓰지 않는다.
  /// FNV-1a 로 직접 계산해 빌드·기기와 무관하게 같은 값이 나오게 한다.
  factory ArtVariant.forCode(String code, {int layouts = kCityLayoutCount}) {
    var h = 0x811c9dc5;
    for (var i = 0; i < code.length; i++) {
      h = ((h ^ code.codeUnitAt(i)) * 0x01000193) & 0xFFFFFFFF;
    }
    return ArtVariant(
      (h & 1) == 1,
      ((h >> 1) % 5 - 2) * 7.0, // -14, -7, 0, 7, 14
      (h >> 4) % layouts,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArtVariant &&
      other.mirror == mirror &&
      other.bgShift == bgShift &&
      other.layout == layout;

  @override
  int get hashCode => Object.hash(mirror, bgShift, layout);

  @override
  String toString() => 'ArtVariant($mirror, $bgShift, $layout)';
}

/// 도시 장면의 건물 높이 조합. 세 동의 지붕 y 좌표다 (작을수록 높다).
///
/// 모두 안전 영역(27~73) 안이라 어떤 크롭에서도 살아남는다.
const _cityTops = [
  [46.0, 36.0, 52.0],
  [40.0, 52.0, 44.0],
  [52.0, 42.0, 48.0],
  [44.0, 34.0, 50.0],
  [38.0, 48.0, 40.0],
  [50.0, 40.0, 46.0],
];

const kCityLayoutCount = 6;

RegionArt _buildCityScene(int layout) {
  final t = _cityTops[layout];
  String bar(double x, double top) =>
      'M$x 70 V$top h10 v${(70 - top).toStringAsFixed(0)} Z';
  // 가운데 동에 창을 세 줄 넣는다. 지붕이 낮으면 줄 수를 줄여 밖으로 안 나가게 한다.
  final wy = <double>[];
  for (var y = t[1] + 8; y < 68; y += 8) {
    wy.add(y);
  }
  return RegionArt('도시', [
    const ArtShape(
        'M-25 70 L-25 54 L-13 54 L-13 44 L-1 44 L-1 60 L11 60 L11 48 L23 48 '
        'L23 64 L35 64 L35 52 L47 52 L47 42 L59 42 L59 58 L71 58 L71 46 '
        'L83 46 L83 62 L95 62 L95 50 L107 50 L107 66 L125 66 L125 70 Z',
        fill: _a2, stroke: null, layer: ArtLayer.background),
    const ArtShape('M-25 70 H125', layer: ArtLayer.background),
    // 지면선 아래가 비어 보여 도로를 깐다. 중앙선 점선이 반복이라
    // 좌우가 잘려도 길로 읽힌다.
    const ArtShape('M-25 88 H125', stroke: _a2, layer: ArtLayer.background),
    const ArtShape(
        'M-16 88 h10 M4 88 h10 M24 88 h10 M44 88 h10 M64 88 h10 '
        'M84 88 h10 M104 88 h10',
        stroke: _a, strokeWidth: 3, layer: ArtLayer.background),
    ArtShape('${bar(36, t[0])} ${bar(48, t[1])} ${bar(60, t[2])}', fill: _p),
    ArtShape(wy.map((y) => 'M51 $y h4').join(' '),
        stroke: _a, strokeWidth: 3),
  ]);
}

/// 도시 장면 6종. 좌우 반전(×2)·배경 이동(×5)과 조합하면 60가지가 나온다.
/// 도시 지역들을 서로 다르게 보여주기에 충분하다.
final List<RegionArt> kCityScenes =
    List.generate(kCityLayoutCount, _buildCityScene);

/// `Region.scratchUnitId` 에 해당하는 아트를 고른다.
///
/// **상호 배타적 폴백 등급이다** — 랜드마크가 있으면 랜드마크, 없으면 카테고리,
/// 카테고리도 없으면 `null`(1층: 단색 + 지역명). 합성 레이어가 아니다.
///
/// 카테고리 배정 **193개**는 `region_category.g.dart` 에 있고
/// `tool/category/make_category_map.py` 가 만든다. 배정 근거는
/// `design/category-assignment.md` 참고.
RegionArt? artForRegion(String code) {
  final landmark = kLandmarkArt[code];
  if (landmark != null) return landmark;
  final cat = kRegionCategory[code];
  if (cat == null) return null;
  // 도시는 반복이 가장 심해 장면 자체를 코드에 따라 고른다.
  if (cat == ArtCategory.city) {
    return kCityScenes[ArtVariant.forCode(code).layout];
  }
  return kCategoryArt[cat];
}

/// 이 지역 아트에 적용할 변형.
///
/// 랜드마크는 지역마다 그림이 다르므로 변형하지 않는다 — 첨성대를 좌우로
/// 뒤집을 이유가 없다.
ArtVariant artVariantFor(String code) =>
    kLandmarkArt.containsKey(code) ? ArtVariant.none : ArtVariant.forCode(code);
