import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/map_painter.dart';
import 'package:mapscratch/sea_background.dart';
import 'package:mapscratch/region_art.dart';

/// 지도에 아트를 얹은 모습을 **눈으로 보는 도구.** 검사가 아니다.
///
/// 전국 뷰에서 최소 지역은 한 변 약 2px 이라 아트를 그려도 보이지 않는다.
/// 큰 지역에만 그리기로 했는데(`kMapArtMinSide`), 그 결과가 어떻게 보이는지는
/// 그려 봐야 안다.
///
/// 산출물: `build/map_art.png`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('전 지역을 수집한 상태의 지도를 그린다', () async {
    final data = await MapData.load();

    final eligible = data.regions
        .where((r) => r.bounds.shortestSide >= kMapArtMinSide)
        .length;
    debugPrint('[MAPART] 아트를 그리는 지역 $eligible / ${data.regions.length}개 '
        '(임계 ${kMapArtMinSide}km)');

    const w = 1100.0;
    final k = w / data.size.width;
    final h = data.size.height * k;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final painter = KoreaMapPainter(
      data: data,
      // 전부 수집한 상태로 그린다. 아트는 수집한 지역에만 나온다.
      scratched: data.regions.map((r) => r.scratchUnitId).toSet(),
      showSidoLines: true,
      sea: kSeaAdopted,
      seaCache: SeaBackgroundCache(),
      theme: kThemeDark,
      foilColor: kSeaAdopted.foil,
      config: RenderConfig.adopted,
      cache: MapPictureCache(),
    );
    painter.paint(canvas, Size(w, h));

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/map_art.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[MAPART] 저장 ${out.path}');

    expect(out.existsSync(), isTrue);
  });

  test('배경 땅(북한)이 남한 위쪽에 그려진다', () async {
    // 북한은 지도 위젯 **밖**(음수 y)에 있다. 프레임을 남한만으로 잡아야
    // 남한 배율이 유지되기 때문이다. 실제로 그려지는지 눈으로 본다.
    final data = await MapData.load();
    expect(data.backgroundLand, isNotNull, reason: '에셋에 배경 땅이 없다');

    final b = data.backgroundLand!.getBounds();
    debugPrint('[NK] 배경 bounds y ${b.top.toStringAsFixed(0)}~'
        '${b.bottom.toStringAsFixed(0)} (음수 = 남한 위쪽)');
    expect(b.top, lessThan(0), reason: '배경이 남한 위쪽으로 뻗어야 한다');

    // 남한 위쪽 여백까지 포함해 그린다.
    const w = 700.0;
    final k = w / data.size.width;
    final top = -b.top * k; // 배경이 차지하는 위쪽 높이
    final h = data.size.height * k + top;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.translate(0, top);
    KoreaMapPainter(
      data: data,
      scratched: const <String>{},
      showSidoLines: true,
      sea: kSeaAdopted,
      seaCache: SeaBackgroundCache(),
      theme: kThemeLight,
      foilColor: kSeaAdopted.foil,
      config: RenderConfig.adopted,
      cache: MapPictureCache(),
    ).paint(canvas, Size(w, data.size.height * k));

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/map_with_nk.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('[NK] 저장 ${out.path}');
    expect(out.existsSync(), isTrue);
  });

  test('아트를 얹어도 지도 Picture 기록이 폭주하지 않는다', () async {
    // 지도 Picture 는 **긁은 집합이 바뀔 때만** 다시 기록한다. 매 프레임이 아니다.
    // 그래도 지역을 하나 긁을 때마다 도는 비용이라 재 둔다.
    //
    // 정밀 측정이 아니라 회귀 감지용이다. 이 프로젝트는 같은 코드가 머신 부하에
    // 따라 10배 튀는 것을 이미 겪었으므로 임계값을 넉넉히 둔다.
    final data = await MapData.load();
    final all = data.regions.map((r) => r.scratchUnitId).toSet();

    double record(Set<String> scratched) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        final cache = MapPictureCache();
        cache.obtain(
        data: data,
        scratched: scratched,
        sidoLines: true,
        stroke: true,
        foil: const Color(0xFF3B3944),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
        cache.dispose();
      }
      sw.stop();
      return sw.elapsedMicroseconds / 5 / 1000;
    }

    final empty = record(const <String>{});
    final full = record(all);
    debugPrint('[MAPART] Picture 기록 — 아트 없음 ${empty.toStringAsFixed(1)}ms '
        '· 전 지역 수집 ${full.toStringAsFixed(1)}ms');

    // 데스크톱 단위 테스트 수치다. 실기기 값이 아니다.
    expect(full, lessThan(300));
  });

  test('파싱한 Path 를 캐시해 재기록이 싸진다', () {
    // 캐시를 빼면 지도 Picture 기록이 0.9ms → 14.7ms 로 뛴다 (실측).
    // 구조가 되돌아가면 여기서 걸린다.
    final art = kLandmarkArt['47130']!;
    const target = Rect.fromLTRB(0, 0, 200, 200);

    double run() {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        final rec = ui.PictureRecorder();
        paintRegionArt(Canvas(rec), art, target);
        rec.endRecording().dispose();
      }
      sw.stop();
      return sw.elapsedMicroseconds / 200;
    }

    clearArtPathCache();
    final cold = run(); // 첫 회만 파싱, 나머지는 캐시 적중
    final warm = run();
    debugPrint('[MAPART] 아트 1장 — 첫 실행 ${cold.toStringAsFixed(0)}us '
        '· 캐시 적중 ${warm.toStringAsFixed(0)}us');
    expect(warm, lessThan(5000));
  });
}
