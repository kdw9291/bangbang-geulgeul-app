import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_painter.dart';

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
        seaColor: const Color(0xFF16303D),
        foilColor: const Color(0xFF474553),
        config: RenderConfig.adopted,
        cache: cache ?? MapPictureCache(),
      );

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
      seaColor: const Color(0xFF16303D),
      foilColor: const Color(0xFF474553),
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
      seaColor: const Color(0xFF16303D),
      foilColor: const Color(0xFF474553),
      config: const RenderConfig(RenderMode.picture, strokes: false),
      cache: MapPictureCache(),
    );
    expect(noStroke.shouldRepaint(withStroke), isTrue,
        reason: '획 표시가 달라지면 다시 그려야 한다');
  });

  test('Picture 캐시는 획 표시가 바뀌면 다시 기록한다', () {
    final cache = MapPictureCache();
    final withStroke = cache.obtain(
        data, const <String>{}, true, true, const Color(0xFF474553));
    final noStroke = cache.obtain(
        data, const <String>{}, true, false, const Color(0xFF474553));
    expect(identical(withStroke, noStroke), isFalse);
    cache.dispose();
  });

  test('Picture 캐시는 긁은 내용이 바뀌면 다시 기록한다', () {
    final cache = MapPictureCache();
    final first = cache.obtain(
        data, const <String>{}, true, false, const Color(0xFF474553));
    final same = cache.obtain(
        data, const <String>{}, true, false, const Color(0xFF474553));
    expect(identical(first, same), isTrue, reason: '같은 상태면 재사용해야 한다');

    final changed = cache.obtain(data, {data.regions.first.scratchUnitId}, true, false,
        const Color(0xFF474553));
    expect(identical(first, changed), isFalse, reason: '내용이 바뀌면 새로 기록해야 한다');

    // 개수가 같고 내용만 다른 경우도 구분해야 한다
    final other = cache.obtain(data, {data.regions[1].scratchUnitId}, true, false,
        const Color(0xFF474553));
    expect(identical(changed, other), isFalse);

    cache.dispose();
  });
}
