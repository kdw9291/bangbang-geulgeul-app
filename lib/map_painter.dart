import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import 'map_data.dart';

/// 렌더 방식 — **어떻게 그리는가**만 나타낸다.
///
/// 초기 구현은 획 표시 여부까지 이 열거형에 섞어 놓았다. 그 결과 채택안인
/// [picture] 는 구조적으로 획을 그릴 수 없었고, 정작 실제로 쓸 조합(Picture + 획)은
/// 한 번도 측정되지 않았다. 두 축을 [RenderConfig] 로 분리했다.
enum RenderMode {
  /// 매 프레임 256개 Path 를 직접 그린다 (최초 구현).
  direct,

  /// 지도를 ui.Picture 로 한 번 기록해두고 매 프레임 재생만 한다.
  picture,

  /// Picture + RepaintBoundary. 레이어를 텍스처로 캐시한다.
  pictureBoundary;

  String get label => switch (this) {
        RenderMode.direct => '직접',
        RenderMode.picture => 'Picture',
        RenderMode.pictureBoundary => 'Picture+경계',
      };

  bool get usesPicture =>
      this == RenderMode.picture || this == RenderMode.pictureBoundary;
}

/// 렌더 방식과 셀 구분 획 표시를 함께 나타내는 설정.
///
/// 흰 실선은 셀 경계를 구분하는 데 필요하므로 제품에서는 켠 상태가 기본이다.
@immutable
class RenderConfig {
  const RenderConfig(this.mode, {this.strokes = true});

  /// 앱이 실제로 쓰는 설정. 문서상 채택안과 일치해야 한다.
  static const adopted = RenderConfig(RenderMode.picture);

  final RenderMode mode;
  final bool strokes;

  String get label => '${mode.label}${strokes ? '+획' : ''}';
  bool get usesPicture => mode.usesPicture;

  @override
  bool operator ==(Object other) =>
      other is RenderConfig && other.mode == mode && other.strokes == strokes;

  @override
  int get hashCode => Object.hash(mode, strokes);

  @override
  String toString() => label;
}

void _paintMap(
  Canvas canvas,
  MapData data,
  Set<String> scratched,
  bool sidoLines,
  bool stroke,
  Color foil,
) {
  final fill = Paint()..style = PaintingStyle.fill;
  final hair = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.4
    ..color = Colors.white.withValues(alpha: 0.55);

  for (final r in data.regions) {
    fill.color = scratched.contains(r.code) ? kSidoColors[r.sido] : foil;
    canvas.drawPath(r.path, fill);
    if (stroke) canvas.drawPath(r.path, hair);
  }

  if (sidoLines) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    // 배열 순서가 아니라 각 항목의 sido 인덱스로 색을 고른다.
    // 순서를 그대로 색 인덱스로 쓰면 시도별 색이 전부 어긋난다.
    for (final l in data.sidoLines) {
      line.color = kSidoColors[l.sido].withValues(alpha: 0.9);
      canvas.drawPath(l.path, line);
    }
  }
}

/// 지도 지오메트리는 변하지 않는다. 바뀌는 것은 긁힌 지역의 색뿐이므로
/// 그 조합이 같은 동안에는 기록해 둔 Picture 를 재생하기만 하면 된다.
///
/// 캐시 키로 해시를 쓰지 않는다. `Object.hash*` 는 충돌 없는 식별자가 아니라,
/// 충돌하면 다른 상태의 그림을 계속 재생하게 된다. 확률은 낮지만 원인을
/// 추적하기 극히 어려운 종류의 버그다. 마지막 입력을 스냅샷으로 들고 비교한다.
class MapPictureCache {
  ui.Picture? _picture;
  MapData? _data;
  Set<String>? _scratched;
  bool? _sidoLines;
  bool? _stroke;
  Color? _foil;

  ui.Picture obtain(
    MapData data,
    Set<String> scratched,
    bool sidoLines,
    bool stroke,
    Color foil,
  ) {
    final stale = _picture == null ||
        !identical(_data, data) ||
        _sidoLines != sidoLines ||
        _stroke != stroke ||
        _foil != foil ||
        !setEquals(_scratched, scratched);

    if (stale) {
      _picture?.dispose();
      final recorder = ui.PictureRecorder();
      _paintMap(Canvas(recorder), data, scratched, sidoLines, stroke, foil);
      _picture = recorder.endRecording();
      _data = data;
      _scratched = Set.unmodifiable(scratched);
      _sidoLines = sidoLines;
      _stroke = stroke;
      _foil = foil;
    }
    return _picture!;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _data = null;
    _scratched = null;
    _sidoLines = null;
    _stroke = null;
    _foil = null;
  }
}

class KoreaMapPainter extends CustomPainter {
  KoreaMapPainter({
    required this.data,
    required this.scratched,
    required this.showSidoLines,
    required this.seaColor,
    required this.foilColor,
    required this.config,
    required this.cache,
    this.selected,
  });

  final MapData data;
  final Set<String> scratched;
  final bool showSidoLines;
  final Color seaColor;
  final Color foilColor;
  final RenderConfig config;
  final MapPictureCache cache;

  /// T4 지역 판정으로 선택된 지역. Picture 캐시를 무효화하지 않도록
  /// 캐시된 그림 위에 따로 덧그린다.
  final Region? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = seaColor);
    canvas.save();
    canvas.scale(size.width / data.size.width);

    if (config.usesPicture) {
      canvas.drawPicture(cache.obtain(
          data, scratched, showSidoLines, config.strokes, foilColor));
    } else {
      _paintMap(
          canvas, data, scratched, showSidoLines, config.strokes, foilColor);
    }

    final sel = selected;
    if (sel != null) {
      canvas.drawPath(
        sel.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFFFFD43B),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(KoreaMapPainter old) =>
      !identical(old.data, data) ||
      old.config != config ||
      old.showSidoLines != showSidoLines ||
      old.seaColor != seaColor ||
      old.foilColor != foilColor ||
      old.selected?.code != selected?.code ||
      // 내용으로 비교해야 한다. 길이 비교는 두 가지로 실패한다 —
      // 길이가 같고 내용만 다른 경우를 놓치고, 호출부가 같은 Set 인스턴스를
      // 제자리에서 수정하면 old 와 new 가 같은 객체라 길이마저 항상 같다.
      !setEquals(old.scratched, scratched);
}
