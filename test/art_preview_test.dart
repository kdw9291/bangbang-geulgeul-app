import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/island_layout.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';

/// T6 파일럿 미리보기 — 아트를 **눈으로 보기 위한 도구다. 검사가 아니다.**
///
/// 단위 테스트가 다 통과해도 화면이 틀릴 수 있다는 걸 이 프로젝트는 이미 겪었다.
/// 시도 외곽선 색이 전부 어긋나 있었는데 테스트 8개와 analyze 가 모두 통과했고,
/// 실기기 캡처를 보고서야 발견했다. 아트에서도 같은 일이 있었다 — 단위 테스트
/// 24개가 통과한 상태에서 10개 중 4개가 깨져 있었다.
///
/// 위: 장면 구성 아트를 원본과 극단 크롭으로 본다.
/// 아래: 파일럿 10개 지역을 채택 배치(B)로 본다.
///
/// 산출물: `build/art_preview.png`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('장면 구성 아트와 파일럿 10개 지역을 PNG 로 그린다', () async {
    final data = await MapData.load();

    // 크롭 비율은 실제 지역에서 가져왔다. 부산 서구는 가로:세로 1:3.73 이라
    // 아트의 가운데 세로 띠만 보인다. 가로로 가장 긴 곳은 부안군 2.56:1 이다.
    // 랜드마크 6종과 카테고리 8종을 나눠서 본다.
    // 카테고리는 206개 이상이 재사용하므로 서로 구분되는지가 특히 중요하다.
    // 제작된 랜드마크 전부. 새로 만들 때마다 자동으로 들어온다.
    final landmarks = {
      for (final e in kLandmarkArt.entries) e.value.name: e.value,
    };
    final categories = {
      for (final c in ArtCategory.values) c.name: kCategoryArt[c]!,
    };
    const crops = ['원본', '세로 1:3.7', '가로 2.6:1'];

    const pilot = <String, String>{
      '47130': '경주시',
      '41115': '수원팔달구',
      '47170': '안동시',
      '50000': '제주도',
      '12150': '순천시',
      '47940': '울릉군',
      '11000': '서울',
      '12770': '장흥군',
      '28720': '옹진군',
      '26140': '부산서구',
    };

    const cell = 240.0;
    const label = 30.0;
    const regionCols = 5;
    final sceneCols = math.max(landmarks.length, categories.length);
    final cols = math.max(sceneCols, regionCols);
    // 랜드마크 3행(크롭) + 카테고리 3행(크롭) + 지역 2행
    final rows = crops.length * 2 + (pilot.length / regionCols).ceil();
    final w = cell * cols;
    final h = (cell + label) * rows;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF15141B));

    // ---- 장면 구성: 원본과 극단 크롭 ----
    var rowBase = 0;
    for (final group in [landmarks, categories]) {
      var j = 0;
      for (final crop in crops) {
        for (final e in group.entries) {
        final ox = (j % group.length) * cell;
        final oy = (rowBase + j ~/ group.length) * (cell + label);
        j++;

        const inset = 6.0;
        final full = Rect.fromLTWH(ox + inset, oy + inset, cell - inset * 2,
            cell - inset * 2);
        final window = switch (crop) {
          '세로 1:3.7' => Rect.fromCenter(
              center: full.center, width: full.width * 0.27, height: full.height),
          '가로 2.6:1' => Rect.fromCenter(
              center: full.center, width: full.width, height: full.height * 0.39),
          _ => full,
        };

        canvas.drawRect(window, Paint()..color = const Color(0xFF4E8ED9));
        canvas.save();
        canvas.clipRect(window);
        paintRegionArt(canvas, e.value, full);
        canvas.restore();
        canvas.drawRect(
          window,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: .35),
        );

        _label(canvas, '${group.keys.toList().indexOf(e.key) + 1}  $crop',
            ox, oy + cell, cell);
        }
      }
      rowBase += crops.length;
    }

    // ---- 파일럿 10개 지역: 채택 배치(B) ----
    var i = 0;
    for (final entry in pilot.entries) {
      final region = data.regions.firstWhere((r) => r.code == entry.key);
      final ox = (i % regionCols) * cell;
      final oy = (rowBase + i ~/ regionCols) * (cell + label);
      i++;

      // 긁기 화면과 같은 경로를 탄다 — 다도해는 섬을 모아 재배치한다.
      final layout = needsPacking(region.rings, region.bounds)
          ? packIslands(region.rings)
          : null;
      final shape = layout == null ? region.path : buildPackedPath(layout);
      final shapeBounds = layout == null ? region.bounds : layout.bounds;

      const pad = 20.0;
      final k = math.min((cell - pad * 2) / shapeBounds.width,
          (cell - pad * 2) / shapeBounds.height);
      final m = Matrix4.identity()
        ..translateByDouble(ox + cell / 2 - shapeBounds.center.dx * k,
            oy + cell / 2 - shapeBounds.center.dy * k, 0, 1)
        ..scaleByDouble(k, k, 1, 1);
      final path = shape.transform(m.storage);

      canvas.drawPath(path, Paint()..color = kSidoColors[region.sido]);

      final art = artForRegion(region.code);
      if (art != null) {
        // 다도해는 아트를 가장 큰 섬 하나에만 놓는다.
        final clip = layout == null
            ? path
            : buildLargestIslandPath(layout).transform(m.storage);
        canvas.save();
        canvas.clipPath(clip);
        paintRegionArt(canvas, art, artTargetFill(clip, clip.getBounds()));
        canvas.restore();
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: .35),
      );

      _label(canvas, '${entry.key}${layout == null ? "" : "  (재배치)"}', ox,
          oy + cell, cell);
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/art_preview.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[ART] 미리보기 저장 ${out.path} (${w.toInt()}×${h.toInt()})');

    expect(out.existsSync(), isTrue);
  });
}

/// 테스트 환경에는 한글 폰트가 없어 한글 라벨이 두부(□)로 나온다.
/// 미리보기 도구의 한계이지 제품 문제가 아니다. 숫자·코드로 식별한다.
void _label(Canvas canvas, String text, double ox, double oy, double cell) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: cell - 8);
  tp.paint(canvas, Offset(ox + (cell - tp.width) / 2, oy + 6));
}
