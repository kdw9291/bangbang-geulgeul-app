import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';

/// T6 파일럿 미리보기 — 10개 지역을 긁기 화면과 같은 방식으로 그려 PNG 로 뽑는다.
///
/// **이건 검사가 아니라 눈으로 보기 위한 도구다.** 단위 테스트가 다 통과해도
/// 화면이 틀릴 수 있다는 걸 이 프로젝트는 이미 겪었다 — 시도 외곽선 색이 전부
/// 어긋나 있었는데 테스트 8개와 analyze 가 모두 통과했고, 실기기 캡처를 보고서야
/// 발견했다.
///
/// 아트 배치가 다도해(옹진군)나 세로로 긴 지역(부산 서구)에서 어떻게 되는지는
/// 수치로 판정할 수 없다. 그려서 봐야 한다.
///
/// 산출물: `build/art_preview.png`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('파일럿 10개 지역을 PNG 로 그린다', () async {
    final data = await MapData.load();

    // 파일럿 대상. `design/art-strategy.md` §3.7 의 구성을 따른다.
    const pilot = <String, String>{
      '47130': '경주시 · 첨성대',
      '41115': '수원팔달구 · 팔달문',
      '47170': '안동시 · 하회마을',
      '50110': '제주시 · 한라산',
      '12150': '순천시 · 순천만',
      '47940': '울릉군 · 울릉도',
      '11110': '종로구 · [도시]',
      '12770': '장흥군 · [들판]',
      '28720': '옹진군 · [섬]',
      '26140': '부산서구 · [바다]',
    };

    // 위: 장면 구성 3종을 원본과 극단 크롭으로 본다.
    // 아래: 파일럿 10개 지역을 채택 배치(B)로 본다.
    const cell = 300.0;
    const cols = 5;
    const label = 34.0;
    const sceneRows = 3; // 4종 × (원본·세로크롭·가로크롭) = 12칸 → 3행
    final rows = sceneRows + (pilot.length / cols).ceil();
    final w = cell * cols;
    final h = (cell + label) * rows;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF15141B));

    var i = 0;

    // ---- 장면 구성 3종: 원본과 극단 크롭 ----
    //
    // 크롭 비율은 실제 지역에서 가져왔다. 부산 서구는 가로:세로 1:3.73 이라
    // 아트의 가운데 세로 띠만 보이고, 서귀포시는 0.52 라 가로 띠만 보인다.
    // 핵심 모티프가 안전 영역 안에 있으면 두 경우 모두 살아남아야 한다.
    final scenes = <String, RegionArt>{
      '첨성대': kLandmarkArt['47130']!,
      '팔달문': kLandmarkArt['41115']!,
      '돌하르방': kLandmarkArt['50110']!,
      '들판(카테고리)': kCategoryArt[ArtCategory.field]!,
    };
    for (final crop in ['원본', '세로 1:3.7', '가로 3.7:1']) {
      for (final e in scenes.entries) {
        final ox = (i % cols) * cell;
        final oy = (i ~/ cols) * (cell + label);
        i++;

        canvas.save();
        canvas.translate(ox, oy);

        // 크롭 창. 아트는 항상 셀 전체를 채우고, 창 모양만 바뀐다.
        final window = switch (crop) {
          '세로 1:3.7' =>
            Rect.fromCenter(center: const Offset(150, 150), width: 78, height: 290),
          '가로 3.7:1' =>
            Rect.fromCenter(center: const Offset(150, 150), width: 290, height: 78),
          _ => const Rect.fromLTWH(5, 5, 290, 290),
        };

        canvas.drawRect(window, Paint()..color = const Color(0xFF4E8ED9));
        canvas.save();
        canvas.clipRect(window);
        paintRegionArt(
            canvas, e.value, const Rect.fromLTWH(5, 5, 290, 290));
        canvas.restore();
        canvas.drawRect(
          window,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: .35),
        );
        canvas.restore();

        final tp = TextPainter(
          text: TextSpan(
            text: '[$crop] ${scenes.keys.toList().indexOf(e.key) + 1}',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.3),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: cell - 8);
        tp.paint(canvas, Offset(ox + (cell - tp.width) / 2, oy + cell + 4));
      }
    }
    // 다음 행 머리로 넘긴다.
    i = ((i + cols - 1) ~/ cols) * cols;

    // ---- 파일럿 10개 지역: 채택 배치(B) ----
    for (final variant in ['B']) {
      for (final entry in pilot.entries) {
      final region = data.regions.firstWhere((r) => r.code == entry.key);
      final ox = (i % cols) * cell;
      final oy = (i ~/ cols) * (cell + label);
      i++;

      // 긁기 화면과 같은 변환: 지역을 셀에 맞춰 넣는다.
      final b = region.bounds;
      const pad = 24.0;
      final k = math.min((cell - pad * 2) / b.width, (cell - pad * 2) / b.height);
      final m = Matrix4.identity()
        ..translateByDouble(ox + cell / 2 - b.center.dx * k,
            oy + cell / 2 - b.center.dy * k, 0, 1)
        ..scaleByDouble(k, k, 1, 1);
      final path = region.path.transform(m.storage);

      // 밑색 → 아트(지역 모양으로 클리핑) → 테두리. `_ScratchPainter` 와 같은 순서다.
      canvas.drawPath(path, Paint()..color = kSidoColors[region.sido]);

      final focus = largestRingBounds(region.rings,
          scale: k, offset: Offset(m.storage[12], m.storage[13]));
      final target = variant == 'A'
          ? artTargetRectIn(path, focus)
          : artTargetFill(path, focus);

      final art = artForRegion(region.code);
      if (art != null) {
        canvas.save();
        canvas.clipPath(path);
        paintRegionArt(canvas, art, target);
        canvas.restore();
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: .35),
      );

      // 아트가 놓인 영역을 옅은 사각형으로 표시해 배치를 확인한다.
      canvas.drawRect(
        target,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x33FFD43B),
      );

      // 테스트 환경에는 한글 폰트가 없어 라벨이 두부(□)로 나온다.
      // 미리보기 도구의 한계이지 제품 문제가 아니다. 순서로 지역을 식별한다.
      final tp = TextPainter(
        text: TextSpan(
          text: '[$variant] ${entry.key}  ${art == null ? "no art" : ""}',
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, height: 1.3),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cell - 8);
      tp.paint(canvas, Offset(ox + (cell - tp.width) / 2, oy + cell + 4));
      }
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
