import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_inset.dart';
import 'package:mapscratch/map_inset_panel.dart';

/// M8 인셋의 **순수 로직**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  ResolvedInset byId(String id) => resolveInset(
        kInsetDefinitions.firstWhere((d) => d.id == id),
        data,
      );

  /// 본지도에서 1km 가 몇 logical px 인지(폭 360 기준).
  double mainPxPerKm() => 360.0 / data.size.width;

  double longSide(Rect b) =>
      b.width > b.height ? b.width : b.height;

  group('창 구성', () {
    test('세 인셋이 있다', () {
      expect(kInsetDefinitions.map((d) => d.id).toList(),
          ['capital', 'busan', 'daegu']);
    });

    test('기준 지역이 전부 창 안에 완전히 들어간다', () {
      for (final def in kInsetDefinitions) {
        final r = resolveInset(def, data);
        final ids = r.regions.map((e) => e.scratchUnitId).toSet();
        for (final f in def.focusIds) {
          expect(ids, contains(f),
              reason: '${def.id} 의 기준 $f 가 창 밖이다');
        }
      }
    });

    test('기준 ID 가 데이터에 없으면 조용히 넘어가지 않는다', () {
      // 행정구역 개편으로 ID 가 사라지면 창이 줄어 인셋이 엉뚱해진다.
      const bad = InsetDefinition(
        id: 'x',
        label: 'x',
        focusIds: {'27110', '99999'},
      );
      expect(() => resolveInset(bad, data), throwsStateError);
    });
  });

  group('멤버십 — 독도가 들어오면 안 된다', () {
    test('세 인셋 어디에도 독도가 없다', () {
      // 독도는 실제 0.187km² 를 폭 8km 로 과장한 단위라 "작은 지역" 목록에
      // 들어온다. 크기로 대상을 고르면 딸려 들어가 M15 의 배치가 깨진다.
      for (final def in kInsetDefinitions) {
        final ids = resolveInset(def, data).regions
            .map((e) => e.scratchUnitId)
            .toSet();
        expect(ids, isNot(contains('DK001')), reason: def.id);
      }
    });

    test('멤버 집합을 정확히 고정한다', () {
      // **개수만 세지 않는다.** 새 지역이 창에 들어오거나 빠지면 사람이 보게
      // 한다 — 조용히 달라지면 인셋이 다른 것을 보여주게 된다(Codex 27회차).
      expect(byId('daegu').regions.map((e) => e.scratchUnitId).toSet(), {
        '27110', '27140', '27170', '27200',
        '27230', '27260', '27290', '27710',
      });
      // **개수만 세면 안 된다.** 한 지역이 빠지고 다른 지역이 들어와 개수가
      // 같으면 조용히 통과한다(Codex 28회차).
      // **경남 양산시(`48330`)가 들어온다.** 창에 완전히 들어오면 시도가
      // 달라도 넣는다 — 창은 지리적이지 행정적이지 않다.
      expect(byId('busan').regions.map((e) => e.scratchUnitId).toSet(), {
        '26110', '26140', '26170', '26200', '26230', '26260', '26290',
        '26320', '26350', '26380', '26410', '26470', '26500', '26530',
        '26710', '31110', '31140', '31170', '48330',
      });
      // 수도권도 **전부 적는다.** 개수와 대표 몇 개만 보면 하나가 빠지고
      // 다른 하나가 들어와도 통과한다(Codex 28회차).
      expect(byId('capital').regions.map((e) => e.scratchUnitId).toSet(), {
        '11000', '28125', '28177', '28185', '28200', '28237',
        '28245', '28275', '28290', '41111', '41113', '41115',
        '41117', '41131', '41133', '41135', '41171', '41173',
        '41192', '41194', '41196', '41210', '41271', '41281',
        '41285', '41287', '41290', '41310', '41370', '41390',
        '41410', '41430', '41463', '41465', '41593', '41595',
        '41597',
      });
    });

    test('대구에 군위군이 없다', () {
      // 넣으면 창이 61×92km 로 벌어져 중구가 다시 8px 아래가 된다.
      final ids =
          byId('daegu').regions.map((e) => e.scratchUnitId).toSet();
      expect(ids, isNot(contains('27720')));
    });

    test('창에 걸치기만 하는 지역은 넣지 않는다', () {
      // 보이는 것과 누를 수 있는 것이 같아야 한다.
      for (final def in kInsetDefinitions) {
        final r = resolveInset(def, data);
        for (final region in r.regions) {
          expect(r.window.contains(region.bounds.topLeft), isTrue,
              reason: '${region.name} 이 창을 벗어난다');
          expect(r.window.contains(region.bounds.bottomRight), isTrue,
              reason: '${region.name} 이 창을 벗어난다');
        }
      }
    });
  });

  group('확대 효과', () {
    test('가장 작은 지역이 본지도보다 확실히 커진다', () {
      // 인셋이 푸는 문제가 이것이다. 확대가 1배 이하면 존재 이유가 없다.
      // **실제 UI 와 같은 크기로 잰다.** 다른 크기로 재면 검증이 화면과
      // 무관해진다(Codex 28회차).
      const canvas = kInsetCanvasSize;
      for (final def in kInsetDefinitions) {
        final r = resolveInset(def, data);
        final t = InsetTransform.fit(r.window, canvas);
        final smallest = r.regions
            .map((e) => longSide(e.bounds))
            .reduce((a, b) => a < b ? a : b);
        final before = smallest * mainPxPerKm();
        final after = smallest * t.scale;
        expect(after, greaterThan(before * 2),
            reason: '${def.id}: ${before.toStringAsFixed(1)}px → '
                '${after.toStringAsFixed(1)}px 밖에 안 커졌다');
        expect(after, greaterThan(6),
            reason: '${def.id}: 확대 후에도 ${after.toStringAsFixed(1)}px 이다');
      }
    });
  });

  group('좌표 변환', () {
    const canvas = kInsetCanvasSize;

    test('왕복하면 제자리로 온다', () {
      final r = byId('daegu');
      final t = InsetTransform.fit(r.window, canvas);
      for (final region in r.regions) {
        final c = region.bounds.center;
        final back = t.toMap(t.toCanvas(c));
        expect(back, isNotNull, reason: region.name);
        expect((back!.dx - c.dx).abs(), lessThan(0.01), reason: region.name);
        expect((back.dy - c.dy).abs(), lessThan(0.01), reason: region.name);
      }
    });

    test('창 모서리가 목적 사각형 모서리로 간다', () {
      final r = byId('busan');
      final t = InsetTransform.fit(r.window, canvas);
      final tl = t.toCanvas(r.window.topLeft);
      final br = t.toCanvas(r.window.bottomRight);
      expect((tl - t.dest.topLeft).distance, lessThan(0.01));
      expect((br - t.dest.bottomRight).distance, lessThan(0.01));
    });

    test('레터박스를 누르면 null 이다 — 가로 여백', () {
      // 그리기는 중앙에 맞춰 놓고 역변환만 단순히 나누면 **모든 탭이 어긋난다**
      // (Codex 27회차). 여백을 눌렀다는 것을 변환이 알아야 한다.
      //
      // 세 창은 모두 세로로 길어서, 납작한 캔버스에서는 **좌우**에 여백이 생긴다.
      final r = byId('daegu');
      final t = InsetTransform.fit(r.window, const Size(300, 60));
      expect(t.dest.width, lessThan(300));
      expect(t.dest.height, closeTo(60, 0.01));
      expect(t.toMap(const Offset(3, 30)), isNull, reason: '왼쪽 여백');
      expect(t.toMap(const Offset(297, 30)), isNull, reason: '오른쪽 여백');
      expect(t.toMap(t.dest.center), isNotNull);
    });

    test('레터박스를 누르면 null 이다 — 세로 여백', () {
      final r = byId('daegu');
      final t = InsetTransform.fit(r.window, const Size(160, 400));
      expect(t.dest.height, lessThan(400));
      expect(t.dest.width, closeTo(160, 0.01));
      expect(t.toMap(const Offset(80, 3)), isNull, reason: '위쪽 여백');
      expect(t.toMap(const Offset(80, 397)), isNull, reason: '아래쪽 여백');
      expect(t.toMap(t.dest.center), isNotNull);
    });

    test('배율은 등방이다', () {
      // 인셋은 확대일 뿐 왜곡이 아니다. 가로세로를 따로 늘리면 지형이 뭉개진다.
      final r = byId('capital');
      final t = InsetTransform.fit(r.window, const Size(300, 60));
      final a = t.toCanvas(r.window.topLeft);
      final b = t.toCanvas(r.window.topLeft + const Offset(10, 10));
      expect((b.dx - a.dx - (b.dy - a.dy)).abs(), lessThan(0.01));
    });

    test('허용 오차를 인셋 배율로 환산한다', () {
      // 본지도 배율을 쓰면 인셋에서 손가락 굵기가 달라진다.
      final r = byId('daegu');
      final t = InsetTransform.fit(r.window, canvas);
      expect(t.mapUnitsPerPx(12), closeTo(12 / t.scale, 1e-9));
      expect(t.mapUnitsPerPx(12), lessThan(12 / mainPxPerKm()),
          reason: '인셋이 확대인데 허용 오차가 본지도보다 넓다');
    });
  });
}
