import 'package:flutter_test/flutter_test.dart';

import 'package:mapscratch/hit_test.dart';
import 'package:mapscratch/island_layout.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';

/// M15 — 독도를 별도 긁기 단위로 추가한 것에 대한 회귀 검사.
///
/// 독도는 원본 GeoJSON 에 없어 모양과 위치를 `tool/map/merge_spec.py` 에서
/// **직접 만들어 넣는다.** 그래서 다른 지역과 달리 배치 규칙이 깨져도 데이터가
/// 스스로 알려주지 않는다 — 여기서 계약을 못 박는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dokdo = 'DK001';
  const ulleung = '47940';

  late MapData data;
  late Region d;
  late Region u;
  setUpAll(() async {
    data = await MapData.load();
    d = data.regions.firstWhere((r) => r.scratchUnitId == dokdo);
    u = data.regions.firstWhere((r) => r.scratchUnitId == ulleung);
  });

  group('긁기 단위', () {
    test('독도가 별도 단위로 있고 경상북도에 속한다', () {
      expect(d.name, '독도');
      expect(data.sidoNames[d.sido], '경상북도');
      // 울릉군을 대체한 것이 아니라 추가한 것이다.
      expect(u.name, '울릉군');
    });

    test('동도·서도 두 링으로 이루어진다', () {
      // 하나의 바위로 그리면 긁기 화면에서 아트와 모양이 어긋난다.
      expect(d.rings.length, 2);
    });
  });

  group('배치', () {
    test('지도 프레임을 넓히지 않는다 — 남한이 화면에서 작아지면 안 된다', () {
      // 전국 뷰 최소 지역이 이미 약 2px 다. 프레임이 넓어지면 그만큼 더 줄어
      // 탭도 인지도 어려워진다. 북한을 프레임 계산에서 뺀 것과 같은 이유다.
      //
      // 값을 하드코딩하는 것이 요점이다 — "현재 에셋과 같다" 로 검사하면
      // 배치 규칙이 깨져 프레임이 늘어난 에셋을 그대로 통과시킨다.
      expect(data.size.width, closeTo(489.4, 0.05));
      expect(data.size.height, closeTo(622.9, 0.05));
    });

    test('독도가 다른 어떤 지역보다도 오른쪽으로 나가지 않는다', () {
      // 프레임 폭을 정하는 것이 최동단이다. 독도가 그 자리를 뺏으면
      // 위 테스트가 깨지기 전에 여기서 원인이 드러난다.
      var east = double.negativeInfinity;
      for (final r in data.regions) {
        if (r.scratchUnitId == dokdo) continue;
        if (r.bounds.right > east) east = r.bounds.right;
      }
      expect(d.bounds.right, lessThanOrEqualTo(east + 0.05));
    });

    test('울릉도의 오른쪽 아래에 떨어져 있다', () {
      // 실제 독도는 울릉도 동남쪽 87.4km 다. 울릉군 자체를 이미 95km 당겨
      // 놓았으므로 거리는 압축하되 **방향은 지킨다.**
      expect(d.bounds.top, greaterThan(u.bounds.bottom),
          reason: '울릉도보다 아래에 있어야 한다');
      expect(d.bounds.center.dx, greaterThan(u.bounds.center.dx),
          reason: '울릉도 중심보다 오른쪽에 있어야 한다');
      // 붙어 보이면 울릉군의 부속 섬으로 오해한다.
      expect(d.bounds.top - u.bounds.bottom, greaterThan(1.5));
    });

    test('전국 뷰에서 보일 만큼 과장돼 있다', () {
      // 실제 0.187km² 는 전국 뷰에서 약 0.5px 라 그릴 수 없다.
      // 사용자 기준은 "약 6px" 이고, 지도 폭이 화면 폭에 맞춰지므로 1km 가
      // 약 0.74 logical px 다(360px 화면). 그래서 **8km** 로 잡았다 —
      // 처음 잡은 5km 는 실기기에서 약 3.3px 밖에 안 됐다.
      expect(d.bounds.width, closeTo(8.0, 0.2));
      expect(d.bounds.width, lessThan(u.bounds.width),
          reason: '울릉도보다 커지면 위계가 뒤집힌다');
    });
  });

  group('긁기·아트', () {
    test('탭하면 독도로 판정된다', () {
      // 작은 지역이라 판정이 되는지 확인해 둔다. 서도 안쪽 점을 쓴다.
      final tester = RegionHitTester(data.regions);
      final inside = d.rings.first;
      // 링 정점만으로는 경계 위라 불안정하다. 첫 링의 무게중심을 쓴다.
      var cx = 0.0, cy = 0.0;
      final n = inside.length ~/ 2;
      for (var i = 0; i < n; i++) {
        cx += inside[i * 2];
        cy += inside[i * 2 + 1];
      }
      final hit = tester.nearest(Offset(cx / n, cy / n), tolerance: 0.5);
      expect(hit?.scratchUnitId, dokdo);
    });

    test('링을 닫는 변 위에서도 독도로 판정된다', () {
      // 링을 닫지 않으면 마지막→첫 정점 변이 `distanceTo` 에서 빠져,
      // **경계선 위의 점조차 0.47km 떨어진 것으로** 나왔다. 작은 지역이라
      // 그 방향의 탭 허용 오차가 통째로 사라진다 (Codex 14회차 지적).
      final tester = RegionHitTester(data.regions);
      for (final ring in d.rings) {
        // 링을 **닫힌 폴리곤으로 보고** 모든 변의 중점을 검사한다.
        // 마지막 정점이 첫 정점의 반복이면 떼어 내고, 변을 `(i, (i+1) % n)`
        // 으로 돈다 — 그래야 링을 닫지 않았을 때 빠지는 변까지 대상이 된다.
        // 인덱스를 고정해 한 점만 보면 두 상태 중 한쪽에서 무의미해진다.
        var n = ring.length ~/ 2;
        if (ring[0] == ring[(n - 1) * 2] && ring[1] == ring[(n - 1) * 2 + 1]) {
          n -= 1;
        }
        for (var i = 0; i < n; i++) {
          final j = (i + 1) % n;
          final mx = (ring[i * 2] + ring[j * 2]) / 2;
          final my = (ring[i * 2 + 1] + ring[j * 2 + 1]) / 2;
          expect(d.distanceTo(Offset(mx, my)), lessThan(0.01),
              reason: '경계선 위의 점인데 거리가 나온다 (변 $i→$j)');
          expect(tester.nearest(Offset(mx, my), tolerance: 0.5)?.scratchUnitId,
              dokdo);
        }
      }
    });

    test('다도해 재배치 대상이 아니다', () {
      // 두 섬이 붙어 있어 육지 비율이 높다. 재배치가 걸리면 두 바위가
      // 화면에 억지로 채워져 독도로 보이지 않는다.
      expect(needsPacking(d.rings, d.bounds), isFalse);
    });

    test('카테고리 폴백이 아니라 전용 랜드마크 아트를 받는다', () {
      expect(kRegionCategory[dokdo], isNotNull, reason: '폴백도 있어야 한다');
      final art = kLandmarkArt[dokdo];
      expect(art, isNotNull);
      expect(art!.name, '독도');
      expect(artForRegion(dokdo), same(art),
          reason: '랜드마크가 카테고리보다 우선해야 한다');
      expect(kPlannedLandmarks, contains(dokdo));
    });
  });
}
