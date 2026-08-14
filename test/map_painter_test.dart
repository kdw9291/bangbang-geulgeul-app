import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/map_painter.dart';
import 'package:mapscratch/sea_background.dart';

/// Codex 검토 High #2 회귀 방지.
///
/// painter 가 호출부의 Set 을 그대로 들고 있으므로, 호출부가 같은 인스턴스를
/// 제자리에서 수정하면 이전/새 painter 가 같은 객체를 보게 되어 길이 비교가
/// 무의미해진다. 내용 비교로 바뀌었는지 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;

  setUpAll(() async {
    data = await MapData.load();
  });

  KoreaMapPainter painter(Set<String> scratched, {MapPictureCache? cache}) =>
      KoreaMapPainter(
        data: data,
        scratched: scratched,
        showSidoLines: true,
        sea: kSeaAdopted,
        seaCache: SeaBackgroundCache(),
      theme: kThemeDark,
        foilColor: kSeaAdopted.foil,
        config: RenderConfig.adopted,
        cache: cache ?? MapPictureCache(),
      );

  test('바다 팔레트가 바뀌면 다시 그린다', () {
    // 배경은 지도 Picture 캐시 밖이라, 팔레트 변경을 여기서 잡지 못하면
    // 설정에서 테마를 바꿔도 화면이 그대로다.
    //
    // **팔레트만 다르게 두고 나머지 입력은 전부 같게 한다.** 처음에는 서로
    // 다른 두 채택 팔레트를 썼는데, 이름도 foil 도 달라서 `old.sea` 비교를
    // 통째로 지워도 `old.foilColor` 가 대신 참이 되어 테스트가 통과했다.
    // 이름과 foil 을 맞추고 base/blob 만 바꿔야 이 경로가 고립된다.
    const p1 = SeaPalette(
      name: 'fixture',
      brightness: Brightness.dark,
      base: Color(0xFF102030),
      foil: Color(0xFF445566),
      blobs: [SeaBlob(Offset(0.5, 0.5), 0.5, Color(0xFF778899))],
    );
    const p2 = SeaPalette(
      name: 'fixture', // 이름 같음
      brightness: Brightness.dark,
      base: Color(0xFFAABBCC), // base 와 blob 만 다르다
      foil: Color(0xFF445566), // foil 같음
      blobs: [SeaBlob(Offset(0.2, 0.2), 0.3, Color(0xFF334455))],
    );

    final base = <String>{};
    final cache = MapPictureCache();
    final seaCache = SeaBackgroundCache();

    KoreaMapPainter make(SeaPalette sea) => KoreaMapPainter(
          data: data,
          scratched: base,
          showSidoLines: true,
          sea: sea,
          seaCache: seaCache,
          theme: kThemeDark,
          foilColor: p1.foil,
          config: RenderConfig.adopted,
          cache: cache,
        );

    expect(make(p2).shouldRepaint(make(p1)), isTrue,
        reason: '팔레트 내용이 다르면 다시 그려야 한다');
    expect(make(p1).shouldRepaint(make(p1)), isFalse,
        reason: '같은 팔레트면 다시 그릴 이유가 없다');
  });

  test('선택 강조색이 바뀌면 다시 그린다', () {
    // 테마를 바꿔도 선택 외곽선이 옛 색으로 남으면, 밝은 배경에서 선택한
    // 지역이 보이지 않는다.
    final base = <String>{};
    final cache = MapPictureCache();
    final seaCache = SeaBackgroundCache();
    KoreaMapPainter make(AppTheme t) => KoreaMapPainter(
          data: data,
          scratched: base,
          showSidoLines: true,
          sea: kSeaAdopted,
          seaCache: seaCache,
          theme: t,
          foilColor: kSeaAdopted.foil,
          config: RenderConfig.adopted,
          cache: cache,
        );
    expect(make(kThemeLight).shouldRepaint(make(kThemeDark)), isTrue);
    expect(make(kThemeDark).shouldRepaint(make(kThemeDark)), isFalse);
  });

  test('긁은 지역이 늘면 다시 그린다', () {
    final a = painter(const <String>{});
    final b = painter({data.regions.first.scratchUnitId});
    expect(b.shouldRepaint(a), isTrue);
  });

  test('개수가 같아도 내용이 다르면 다시 그린다', () {
    final a = painter({data.regions[0].scratchUnitId});
    final b = painter({data.regions[1].scratchUnitId});
    expect(b.shouldRepaint(a), isTrue);
  });

  test('내용이 같으면 다시 그리지 않는다', () {
    final codes = {data.regions[0].scratchUnitId, data.regions[5].scratchUnitId};
    final a = painter({...codes});
    final b = painter({...codes});
    expect(b.shouldRepaint(a), isFalse);
  });

  test('선택 지역이 바뀌면 다시 그린다', () {
    final base = <String>{};
    final a = painter(base);
    final b = KoreaMapPainter(
      data: data,
      scratched: base,
      showSidoLines: true,
      sea: kSeaAdopted,
      seaCache: SeaBackgroundCache(),
      theme: kThemeDark,
      foilColor: kSeaAdopted.foil,
      config: RenderConfig.adopted,
      cache: MapPictureCache(),
      selected: data.regions.first,
    );
    expect(b.shouldRepaint(a), isTrue);
  });

  // 앱이 문서상 채택안과 다른 설정으로 실행되던 회귀를 막는다.
  test('앱 기본 설정은 Picture 캐시 + 획 이다', () {
    expect(RenderConfig.adopted.mode, RenderMode.picture);
    expect(RenderConfig.adopted.strokes, isTrue);
    expect(RenderConfig.adopted.label, 'Picture+획');
  });

  test('설정이 바뀌면 다시 그린다', () {
    final base = <String>{};
    final withStroke = painter(base);
    final noStroke = KoreaMapPainter(
      data: data,
      scratched: base,
      showSidoLines: true,
      sea: kSeaAdopted,
      seaCache: SeaBackgroundCache(),
      theme: kThemeDark,
      foilColor: kSeaAdopted.foil,
      config: const RenderConfig(RenderMode.picture, strokes: false),
      cache: MapPictureCache(),
    );
    expect(noStroke.shouldRepaint(withStroke), isTrue,
        reason: '획 표시가 달라지면 다시 그려야 한다');
  });

  test('배경 땅 색만 달라도 다시 기록한다', () {
    // 테마 전체를 바꾸는 테스트는 선택선 색도 함께 달라져, 배경색 비교를
    // 실수로 지워도 통과한다. 이 경로만 고립해서 본다 (Codex 13회차 지적).
    final cache = MapPictureCache();
    ui.Picture make(Color bg, Color stroke) => cache.obtain(
          data: data,
          scratched: const <String>{},
          sidoLines: true,
          stroke: true,
          foil: const Color(0xFF474553),
          bgLand: bg,
          bgLandStroke: stroke,
        );

    final a = make(const Color(0xFF111111), const Color(0xFF222222));
    final b = make(const Color(0xFF999999), const Color(0xFF222222));
    expect(identical(a, b), isFalse, reason: '배경 채움색이 바뀌면 다시 기록해야 한다');

    final c = make(const Color(0xFF999999), const Color(0xFF888888));
    expect(identical(b, c), isFalse, reason: '배경 경계색이 바뀌면 다시 기록해야 한다');

    final d = make(const Color(0xFF999999), const Color(0xFF888888));
    expect(identical(c, d), isTrue, reason: '같으면 재사용해야 한다');
    cache.dispose();
  });

  test('Picture 캐시는 획 표시가 바뀌면 다시 기록한다', () {
    final cache = MapPictureCache();
    final withStroke = cache.obtain(
        data: data,
        scratched: const <String>{},
        sidoLines: true,
        stroke: true,
        foil: const Color(0xFF474553),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
    final noStroke = cache.obtain(
        data: data,
        scratched: const <String>{},
        sidoLines: true,
        stroke: false,
        foil: const Color(0xFF474553),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
    expect(identical(withStroke, noStroke), isFalse);
    cache.dispose();
  });

  test('Picture 캐시는 긁은 내용이 바뀌면 다시 기록한다', () {
    final cache = MapPictureCache();
    final first = cache.obtain(
        data: data,
        scratched: const <String>{},
        sidoLines: true,
        stroke: false,
        foil: const Color(0xFF474553),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
    final same = cache.obtain(
        data: data,
        scratched: const <String>{},
        sidoLines: true,
        stroke: false,
        foil: const Color(0xFF474553),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
    expect(identical(first, same), isTrue, reason: '같은 상태면 재사용해야 한다');

    final changed = cache.obtain(
        data: data,
        scratched: {data.regions.first.scratchUnitId},
        sidoLines: true,
        stroke: false,
        foil: const Color(0xFF474553),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
    expect(identical(first, changed), isFalse, reason: '내용이 바뀌면 새로 기록해야 한다');

    // 개수가 같고 내용만 다른 경우도 구분해야 한다
    final other = cache.obtain(
        data: data,
        scratched: {data.regions[1].scratchUnitId},
        sidoLines: true,
        stroke: false,
        foil: const Color(0xFF474553),
        bgLand: kThemeDark.backgroundLand,
        bgLandStroke: kThemeDark.backgroundLandStroke);
    expect(identical(changed, other), isFalse);

    cache.dispose();
  });
}
