import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/region_art.dart';

/// **M10 눈 확인용.** 카테고리 아트 8종을 팝업 카드 비율로 나란히 낸다.
///
/// 161곳이 이 여덟 그림을 나눠 쓴다 — 산 28곳, 바다 26곳, 들 32곳은 각각
/// **전부 같은 그림**이다(도시만 변형 60가지). 반복이 견딜 만한지 판단하려면
/// 실제로 나란히 놓고 봐야 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('카테고리 8종을 한 장에', () async {
    const cardW = 300.0, cardH = 150.0, gap = 12.0, labelH = 26.0;
    const cols = 2;
    final cats = ArtCategory.values;
    final rows = (cats.length + cols - 1) ~/ cols;
    final w = cols * cardW + (cols + 1) * gap;
    final h = rows * (cardH + labelH) + (rows + 1) * gap;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFF1F4F8));

    for (var i = 0; i < cats.length; i++) {
      final c = cats[i];
      final col = i % cols, row = i ~/ cols;
      final x = gap + col * (cardW + gap);
      final y = gap + row * (cardH + labelH + gap);
      final card = Rect.fromLTWH(x, y, cardW, cardH);

      canvas.save();
      canvas.clipRect(card);
      canvas.drawRect(card, Paint()..color = const Color(0xFF7C8AA0));
      final side = card.width > card.height ? card.width : card.height;
      paintRegionArt(
        canvas,
        kCategoryArt[c]!,
        Rect.fromCenter(center: card.center, width: side, height: side),
      );
      canvas.restore();

      final label = TextPainter(
        text: TextSpan(
          text: '${c.name}  ${_count[c]}곳',
          style: const TextStyle(color: Color(0xFF2B2118), fontSize: 15),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 2, y + cardH + 5));
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/category_art.png');
    await out.parent.create(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[PREVIEW] ${out.path}');
  });
}

/// 랜드마크가 없어 이 카테고리로 떨어지는 지역 수.
const Map<ArtCategory, int> _count = {
  ArtCategory.city: 69,
  ArtCategory.sea: 34,
  ArtCategory.field: 33,
  ArtCategory.mountain: 28,
  ArtCategory.river: 14,
  ArtCategory.island: 8,
  ArtCategory.heritage: 6,
  ArtCategory.hotspring: 3,
};
