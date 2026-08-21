import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';

/// 193개 카테고리 배정을 **전국 지도 위에서 눈으로 보는 도구.** 검사가 아니다.
///
/// 표로만 보면 이상한 배정을 못 잡는다. 인접 지역과 견줘 봐야
/// "여기만 왜 혼자 바다지?" 같은 것이 드러난다.
///
/// 카테고리마다 색을 달리해 칠하고, 색 옆에 개수를 적는다.
/// 산출물: `build/category_map.png`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('카테고리 배정을 전국 지도에 칠한다', () async {
    final data = await MapData.load();

    const colors = {
      ArtCategory.mountain: Color(0xFF4A7C6F),
      ArtCategory.sea: Color(0xFF4E8ED9),
      ArtCategory.island: Color(0xFF7B5EA7),
      ArtCategory.city: Color(0xFF8A7D6D),
      ArtCategory.heritage: Color(0xFFC9713A),
      ArtCategory.hotspring: Color(0xFFD94F70),
      ArtCategory.river: Color(0xFF3FA9C9),
      ArtCategory.field: Color(0xFF9BBF4A),
    };

    const w = 1100.0;
    final k = w / data.size.width;
    final mapH = data.size.height * k;
    const legend = 210.0;
    final h = mapH + legend;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF15141B));

    canvas.save();
    canvas.scale(k);
    final counts = <ArtCategory, int>{};
    for (final r in data.regions) {
      final cat = kRegionCategory[r.scratchUnitId]!;
      counts[cat] = (counts[cat] ?? 0) + 1;
      canvas.drawPath(r.path, Paint()..color = colors[cat]!);
      canvas.drawPath(
        r.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = Colors.white.withValues(alpha: .45),
      );
    }
    canvas.restore();

    // 범례 — 색과 개수. 한글 폰트가 없어 enum 이름(영문)을 쓴다.
    var i = 0;
    for (final c in ArtCategory.values) {
      final x = 30.0 + (i % 4) * 265;
      final y = mapH + 30 + (i ~/ 4) * 44;
      i++;
      canvas.drawRect(
          Rect.fromLTWH(x, y, 28, 28), Paint()..color = colors[c]!);
      final tp = TextPainter(
        text: TextSpan(
          text: '  ${c.name}  ${counts[c] ?? 0}',
          style: const TextStyle(color: Colors.white70, fontSize: 20),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 34, y + 3));
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/category_map.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[CAT] 저장 ${out.path} · ${math.min(counts.length, 8)}종 사용');

    expect(out.existsSync(), isTrue);
  });

  test('도시 장면 변형 25개를 나란히 그린다', () async {
    // 변형이 실제로 눈에 띄는지 본다. 수치로 구분된다고 사람 눈에도
    // 다르게 보이는 건 아니다.
    final seoul = kRegionCategory.entries
        .where((e) => e.value == ArtCategory.city)
        .map((e) => e.key)
        .take(25)
        .toList();

    const cell = 200.0;
    const cols = 5;
    const label = 26.0;
    final rows = (seoul.length / cols).ceil();
    final w = cell * cols;
    final h = (cell + label) * rows;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF15141B));

    for (var i = 0; i < seoul.length; i++) {
      final code = seoul[i];
      final ox = (i % cols) * cell;
      final oy = (i ~/ cols) * (cell + label);
      final art = artForRegion(code)!;
      final v = artVariantFor(code);

      final box = Rect.fromLTWH(ox + 6, oy + 6, cell - 12, cell - 12);
      canvas.drawRect(box, Paint()..color = const Color(0xFF4E8ED9));
      canvas.save();
      canvas.clipRect(box);
      paintRegionArt(canvas, art, box, variant: v);
      canvas.restore();

      final tp = TextPainter(
        text: TextSpan(
          text: '$code  L${v.layout}${v.mirror ? " M" : ""} '
              '${v.bgShift.toStringAsFixed(0)}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ox + (cell - tp.width) / 2, oy + cell + 4));
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/city_variants.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[CAT] 저장 ${out.path}');
    expect(out.existsSync(), isTrue);
  });
}
