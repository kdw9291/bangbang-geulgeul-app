import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// T6 아트 전략 파일럿 — 지역 아트를 그리는 최소 구현.
///
/// **이 파일은 공수와 성능을 실측하기 위한 파일럿이다.** 10개 지역만 담고 있으며
/// 40개 랜드마크 전량이나 256개 카테고리 배정은 포함하지 않는다.
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

/// [art] 를 [target] 에 맞춰 그린다. [opacity] 로 전체 투명도를 조절한다.
void paintRegionArt(
  Canvas canvas,
  RegionArt art,
  Rect target, {
  double opacity = 1.0,
}) {
  if (opacity <= 0) return;
  canvas.save();
  canvas.translate(target.left, target.top);
  canvas.scale(target.width / 100, target.height / 100);

  for (final s in art.shapes) {
    Path p;
    if (s.circle case final c?) {
      p = Path()
        ..addOval(Rect.fromCircle(center: Offset(c.$1, c.$2), radius: c.$3));
    } else {
      p = parseSvgPath(s.d);
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

  ui.Picture obtain(RegionArt art, Rect target) {
    if (_picture == null ||
        !identical(_art, art) ||
        _target != target) {
      _picture?.dispose();
      final recorder = ui.PictureRecorder();
      paintRegionArt(Canvas(recorder), art, target);
      _picture = recorder.endRecording();
      _art = art;
      _target = target;
    }
    return _picture!;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _art = null;
    _target = null;
  }
}

// ---------------------------------------------------------------------------
// 파일럿 데이터 — 10개 지역
// ---------------------------------------------------------------------------

/// 3층 카테고리 아이콘. 랜드마크가 없는 지역이 재사용한다.
///
/// 원형은 8종이지만 그대로 8개 결과물로 반복하지 않는다 — S2 에서 시도 팔레트와
/// 배치를 지역 코드로 조합해 변형을 늘린다(`design/art-strategy.md` §3.2).
enum ArtCategory { mountain, sea, island, city, heritage, hotspring, river, field }

const _p = ArtPalette.paper;
const _a = ArtPalette.accent;
const _a2 = ArtPalette.accent2;

final Map<ArtCategory, RegionArt> kCategoryArt = {
  ArtCategory.mountain: const RegionArt('산', [
    ArtShape('M10 80 L38 34 L52 56 L64 38 L90 80 Z', fill: _p),
    ArtShape('M30 47 L38 34 L45 45', stroke: _a2),
  ]),
  ArtCategory.sea: const RegionArt('바다·해변', [
    ArtShape.circle(68, 28, 12, fill: _a),
    ArtShape('M10 62 C24 54 36 70 50 62 C64 54 76 70 90 62', stroke: _a2),
    ArtShape('M10 80 C24 72 36 88 50 80 C64 72 76 88 90 80', stroke: _a2),
  ]),
  ArtCategory.island: const RegionArt('섬', [
    ArtShape('M26 66 C30 44 44 32 56 32 C68 32 78 46 78 66 Z', fill: _p),
    ArtShape('M56 32 V16', stroke: _a2),
    ArtShape('M56 18 L74 24 L56 30 Z', fill: _a),
    ArtShape('M10 80 C26 72 38 88 54 80 C70 72 78 86 90 80', stroke: _a2),
  ]),
  ArtCategory.city: const RegionArt('도시', [
    ArtShape('M18 46 h24 v38 h-24 Z', fill: _p),
    ArtShape('M46 24 h22 v60 h-22 Z', fill: _p),
    ArtShape('M72 56 h16 v28 h-16 Z', fill: _p),
    ArtShape('M52 40 h10 M52 54 h10 M52 68 h10', stroke: _a),
    ArtShape('M12 84 h76'),
  ]),
  ArtCategory.heritage: const RegionArt('유적·한옥', [
    ArtShape('M22 84 V56 h56 v28', fill: _p),
    ArtShape('M14 56 L50 40 L86 56 Z', fill: _p, stroke: _a2),
    ArtShape('M44 84 V66 h12 v18', fill: _a),
    ArtShape('M12 84 h76'),
  ]),
  ArtCategory.hotspring: const RegionArt('온천', [
    ArtShape('M18 60 h64 v10 C82 80 74 88 64 88 H36 C26 88 18 80 18 70 Z',
        fill: _p),
    ArtShape('M36 44 C30 36 42 30 36 20', stroke: _a),
    ArtShape('M52 44 C46 36 58 30 52 20', stroke: _a),
    ArtShape('M68 44 C62 36 74 30 68 20', stroke: _a),
  ]),
  ArtCategory.river: const RegionArt('강·호수', [
    ArtShape('M20 20 C32 44 32 60 20 84', stroke: _a2),
    ArtShape('M80 20 C68 44 68 60 80 84', stroke: _a2),
    ArtShape('M40 40 C50 46 54 46 62 40', stroke: _a),
    ArtShape('M38 62 C48 68 52 68 60 62', stroke: _a),
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
  '47170': const RegionArt('하회마을', [
    ArtShape('M8 82 C28 70 36 94 58 80 C72 71 84 76 94 70', stroke: _a2),
    ArtShape('M16 50 C22 38 40 38 46 50 Z', fill: _p),
    ArtShape('M19 50 h24 v16 h-24 Z', fill: _p),
    ArtShape('M27 66 V56 h8 v10', fill: _a),
    ArtShape('M56 58 C60 49 74 49 78 58 Z', fill: _p),
    ArtShape('M58 58 h18 v12 h-18 Z', fill: _p),
  ]),

  // 50110 제주시 — 돌하르방 (조선 후기 석상)
  //
  // 장면 구성: 오름 능선과 현무암 밭담(배경) 앞에 돌하르방(핵심).
  // 밭담은 반복 패턴이라 좌우가 잘려도 제주로 읽힌다.
  //
  // 제주는 시군구가 2개뿐이라 랜드마크를 하나만 둔다(2026-08-13 사용자 결정).
  // 이전에 만든 한라산 아트는 이 결정으로 목록에서 빠졌다.
  '50110': const RegionArt('돌하르방', [
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
  '12150': const RegionArt('순천만 갈대밭', [
    ArtShape('M10 78 h80', stroke: _a2),
    ArtShape('M14 88 h72', stroke: _a2),
    ArtShape('M26 78 C24 58 28 44 30 34'),
    ArtShape('M44 78 C42 54 46 38 48 26'),
    ArtShape('M62 78 C60 60 64 46 66 36'),
    ArtShape('M78 78 C77 62 80 52 81 44'),
    ArtShape('M30 34 C24 28 22 22 24 18 C30 20 32 26 30 34 Z', fill: _a),
    ArtShape('M48 26 C42 20 40 14 42 10 C48 12 50 18 48 26 Z', fill: _a),
    ArtShape('M66 36 C60 30 58 24 60 20 C66 22 68 28 66 36 Z', fill: _a),
  ]),

  // 47940 울릉군 — 울릉도 (자연경관)
  '47940': const RegionArt('울릉도', [
    ArtShape('M6 74 L28 34 L38 50 L48 30 L70 74 Z', fill: _p),
    ArtShape('M72 74 L84 50 L94 74 Z', fill: _p),
    ArtShape('M28 34 L34 44', stroke: _a2),
    ArtShape.circle(76, 26, 9, fill: _a),
    ArtShape('M6 84 C18 78 30 90 42 84 C54 78 66 90 78 84 C86 80 90 82 94 84',
        stroke: _a2),
  ]),
};

/// 랜드마크가 없는 지역의 카테고리 배정. **파일럿 4개만 담고 있다.**
/// 256개 전량 배정은 T6 완료 조건 2번이다.
const Map<String, ArtCategory> kRegionCategory = {
  '11110': ArtCategory.city, // 서울 종로구
  '12770': ArtCategory.field, // 장흥군 — 세로 2.15배
  '28720': ArtCategory.island, // 옹진군 — 다도해 최악 (링 20)
  '26140': ArtCategory.sea, // 부산 서구 — 세로 3.73배
};

/// 지역 코드에 해당하는 아트를 고른다.
///
/// **상호 배타적 폴백 등급이다** — 랜드마크가 있으면 랜드마크, 없으면 카테고리,
/// 카테고리도 없으면 `null`(1층: 단색 + 지역명). 합성 레이어가 아니다.
RegionArt? artForRegion(String code) =>
    kLandmarkArt[code] ?? kCategoryArt[kRegionCategory[code]];
