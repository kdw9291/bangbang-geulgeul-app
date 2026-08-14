import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_painter.dart';
import 'package:mapscratch/sea_background.dart';

/// 바다 배경 후보를 **눈으로 고르는 도구.** 검사가 아니다.
///
/// 색은 취향이라 수치로 판정할 수 없다. 그리고 이 프로젝트는 단위 테스트가
/// 전부 통과한 상태에서 화면이 틀린 일을 여러 번 겪었다 — 반드시 렌더해서 본다.
///
/// 산출물:
/// - `build/sea_candidates.png` 후보 3종 × (수집 전 / 절반 수집)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('바다 배경 후보를 지도에 얹어 나란히 그린다', () async {
    final data = await MapData.load();

    // 절반 수집 상태. 배경이 밝아지면 은박(미수집)이 묻히는지 보려면
    // 두 상태가 한 화면에 있어야 한다.
    final half = <String>{};
    for (var i = 0; i < data.regions.length; i += 2) {
      half.add(data.regions[i].scratchUnitId);
    }

    const cellW = 460.0;
    final k = cellW / data.size.width;
    final cellH = data.size.height * k;
    const label = 34.0;
    const pad = 16.0;

    final cols = kSeaPalettes.length;
    final w = pad + (cellW + pad) * cols;
    final h = pad + label + (cellH + pad + label) * 2;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF23222A));

    void text(String s, double x, double y, {double size = 15}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
              color: Colors.white, fontSize: size, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }

    for (var row = 0; row < 2; row++) {
      final scratched = row == 0 ? const <String>{} : half;
      final rowY = pad + label + (cellH + pad + label) * row;

      for (var col = 0; col < cols; col++) {
        final p = kSeaPalettes[col];
        final x = pad + (cellW + pad) * col;

        text('${p.name}  ${row == 0 ? "수집 전" : "절반 수집"}', x, rowY - label + 8);

        canvas.save();
        canvas.translate(x, rowY);
        canvas.clipRect(Rect.fromLTWH(0, 0, cellW, cellH));
        KoreaMapPainter(
          data: data,
          scratched: scratched,
          showSidoLines: true,
          sea: p,
          seaCache: SeaBackgroundCache(),
          foilColor: p.foil,
          config: RenderConfig.adopted,
          cache: MapPictureCache(),
        ).paint(canvas, Size(cellW, cellH));
        canvas.restore();
      }
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/sea_candidates.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[SEA] 저장 ${out.path} (${w.toInt()}×${h.toInt()})');

    expect(out.existsSync(), isTrue);
  });

  test('배경 Picture 캐시가 같은 크기에서 재기록하지 않는다', () {
    // 배경은 지도 캐시 밖이라 매 프레임 경로다. 캐시가 깨지면 프레임마다
    // 셰이더 5개를 새로 만들게 된다.
    final cache = SeaBackgroundCache();
    const size = Size(1080, 1374);

    final a = cache.obtain(size, kSeaAdopted);
    final b = cache.obtain(size, kSeaAdopted);
    expect(identical(a, b), isTrue, reason: '같은 크기·팔레트면 재사용해야 한다');

    final c = cache.obtain(const Size(720, 916), kSeaAdopted);
    expect(identical(a, c), isFalse, reason: '크기가 바뀌면 다시 기록해야 한다');

    final d = cache.obtain(const Size(720, 916), kSeaSunset);
    expect(identical(c, d), isFalse, reason: '팔레트가 바뀌면 다시 기록해야 한다');

    cache.dispose();
  });

  test('이름이 같아도 내용이 다르면 캐시가 재사용하지 않는다', () {
    // 처음 구현은 `SeaPalette ==` 가 name 만 비교해, 이름이 같고 내용이 다른
    // 팔레트를 넣으면 **캐시가 옛 그림을 계속 재생하고 리페인트도 하지 않았다.**
    // Picture 캐시 키에 해시를 썼다가 고친 것과 같은 유형이다.
    const a = SeaPalette(
      name: 'same-name',
      base: Color(0xFF112233),
      foil: Color(0xFF445566),
      blobs: [SeaBlob(Offset(0.5, 0.5), 0.5, Color(0xFF778899))],
    );
    const b = SeaPalette(
      name: 'same-name', // 이름만 같고 색이 전부 다르다
      base: Color(0xFFAABBCC),
      foil: Color(0xFFDDEEFF),
      blobs: [SeaBlob(Offset(0.2, 0.2), 0.3, Color(0xFF102030))],
    );

    expect(a == b, isFalse, reason: '이름이 같아도 내용이 다르면 다른 팔레트다');

    final cache = SeaBackgroundCache();
    const size = Size(400, 500);
    final pa = cache.obtain(size, a);
    final pb = cache.obtain(size, b);
    expect(identical(pa, pb), isFalse, reason: '내용이 다르면 다시 기록해야 한다');
    cache.dispose();
  });

  test('배경 기록 비용이 폭주하지 않는다', () {
    // **재는 것은 기록 비용이지 재생 비용이 아니다.** `ui.Picture` 는 픽셀이
    // 아니라 그리기 명령 묶음이라, 래스터 캐시가 적중하지 않으면 GPU 는 여전히
    // gradient 를 실행한다. 프레임 비용은 실기기 `--profile` 로만 판단한다.
    //
    // 정밀 측정이 아니라 회귀 감지용이다. 이 프로젝트는 같은 코드가 머신
    // 부하에 따라 10배 튀는 것을 이미 겪었으므로 임계값을 넉넉히 둔다.
    const size = Size(1080, 1374);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      final rec = ui.PictureRecorder();
      paintSea(Canvas(rec), size, kSeaAdopted);
      rec.endRecording().dispose();
    }
    sw.stop();
    final ms = sw.elapsedMicroseconds / 20 / 1000;
    debugPrint('[SEA] 배경 1회 기록 ${ms.toStringAsFixed(2)}ms');
    expect(ms, lessThan(50));
  });

  test('모든 후보가 blob 을 가지고 이름이 유일하다', () {
    // 이름은 더 이상 캐시 키가 아니다 (`==` 는 identity 다). 그래도 설정 화면에
    // 저장한 선택을 이름으로 되살릴 계획이라, 겹치면 어느 팔레트인지 알 수 없다.
    final names = kSeaPalettes.map((p) => p.name).toSet();
    expect(names.length, kSeaPalettes.length, reason: '팔레트 이름이 겹친다');
    for (final p in kSeaPalettes) {
      expect(p.blobs, isNotEmpty, reason: '${p.name} 에 blob 이 없다 — 단색이 된다');
    }
    expect(kSeaPalettes.contains(kSeaAdopted), isTrue,
        reason: '채택안이 후보 목록에 있어야 미리보기에서 함께 검토된다');
    expect(kSeaPalettes.contains(kSeaFlat), isFalse,
        reason: '측정 전용 단색은 설정 화면에 노출하지 않는다');
  });

  test('이름으로 찾으면 항상 같은 상수를 돌려준다', () {
    // 동등성이 identity 라, 매번 새 인스턴스를 만들면 캐시가 계속 miss 된다.
    // 설정 화면이 저장된 선택을 되살릴 때 이 계약이 깨지면 배경이 매 프레임
    // 다시 기록된다.
    for (final p in [...kSeaPalettes, kSeaFlat]) {
      expect(identical(seaPaletteByName(p.name), p), isTrue,
          reason: '${p.name} 이 기존 상수가 아니다');
    }
    expect(identical(seaPaletteByName('없는이름'), kSeaCerulean), isTrue,
        reason: '알 수 없는 이름은 기본값으로 떨어져야 한다');
  });
}
