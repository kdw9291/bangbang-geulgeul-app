import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/island_layout.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';

/// 다도해 재배치 프로토타입 미리보기.
///
/// 왼쪽은 현재 방식(bounds 를 화면에 맞춤), 오른쪽은 재배치다.
/// 산출물: `build/island_layout.png`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('다도해 4개를 현재 방식과 재배치로 나란히 그린다', () async {
    final data = await MapData.load();

    const targets = <String, String>{
      '28720': '옹진군',
      '12870': '신안군',
      '41273': '안산단원구',
      '12130': '여수시',
    };

    const cell = 340.0;
    const label = 30.0;
    final w = cell * 2;
    final h = (cell + label) * targets.length;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF15141B));

    var row = 0;
    final report = StringBuffer();

    for (final e in targets.entries) {
      final region = data.regions.firstWhere((r) => r.code == e.key);
      final oy = row * (cell + label);
      row++;

      // ---- 왼쪽: 현재 방식 ----
      _drawFitted(canvas, region.path, region.bounds, Offset(0, oy), cell,
          kSidoColors[region.sido], artForRegion(region.code));

      // ---- 오른쪽: 재배치 + 아트는 가장 큰 섬에만 ----
      final layout = packIslands(region.rings);
      final packed = buildPackedPath(layout);
      _drawFitted(canvas, packed, layout.bounds, Offset(cell, oy), cell,
          kSidoColors[region.sido], artForRegion(region.code),
          artClip: buildLargestIslandPath(layout));

      final before = _fill(region.rings, region.bounds);
      report.writeln('${e.value}: 육지비율 '
          '${(before * 100).toStringAsFixed(2)}% → '
          '${(layout.fillRatio * 100).toStringAsFixed(1)}% '
          '(${(layout.fillRatio / before).toStringAsFixed(1)}배) · '
          '링 ${region.rings.length}개 · 재배치 후 '
          '${layout.bounds.width.toStringAsFixed(0)}×'
          '${layout.bounds.height.toStringAsFixed(0)}');

      final tp = TextPainter(
        text: TextSpan(
          text: '${e.key}   before / after   '
              '${(before * 100).toStringAsFixed(2)}% -> '
              '${(layout.fillRatio * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
      tp.paint(canvas, Offset((w - tp.width) / 2, oy + cell + 4));
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/island_layout.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());

    debugPrint('[ISLAND] $report');
    debugPrint('[ISLAND] 저장 ${out.path}');
    expect(out.existsSync(), isTrue);
  });
}

double _fill(List<dynamic> rings, Rect b) {
  final area = b.width * b.height;
  if (area <= 0) return 0;
  var land = 0.0;
  for (final r in rings) {
    final n = r.length ~/ 2;
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      s += r[i * 2] * r[j * 2 + 1] - r[j * 2] * r[i * 2 + 1];
    }
    land += s.abs() / 2;
  }
  return land / area;
}

void _drawFitted(Canvas canvas, Path path, Rect bounds, Offset origin,
    double cell, Color color, RegionArt? art, {Path? artClip}) {
  const pad = 20.0;
  if (bounds.width <= 0 || bounds.height <= 0) return;
  final k = math.min(
      (cell - pad * 2) / bounds.width, (cell - pad * 2) / bounds.height);
  final m = Matrix4.identity()
    ..translateByDouble(origin.dx + cell / 2 - bounds.center.dx * k,
        origin.dy + cell / 2 - bounds.center.dy * k, 0, 1)
    ..scaleByDouble(k, k, 1, 1);
  final p = path.transform(m.storage);

  canvas.drawPath(p, Paint()..color = color);
  if (art != null) {
    // 아트를 놓을 자리. 다도해는 가장 큰 섬에만 놓는다.
    final clip = artClip == null ? p : artClip.transform(m.storage);
    canvas.save();
    canvas.clipPath(clip);
    paintRegionArt(canvas, art, artTargetFill(clip, clip.getBounds()));
    canvas.restore();
  }
  canvas.drawPath(
    p,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: .4),
  );
}
