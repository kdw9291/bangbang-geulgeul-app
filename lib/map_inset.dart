/// M8 도심 확대 인셋. **순수 로직이라 위젯을 모른다.**
///
/// ## 왜 필요한가
///
/// 지도 폭이 화면 폭에 맞춰지므로 **1km ≈ 0.736 logical px**(360px 기준)다.
/// 부산 중구는 긴 변이 2.5km 라 화면에서 **1.8px**, 대구 중구는 2.6px 다.
/// 검색(M3)은 *접근*을 풀고 인셋은 *표시*를 푼다 — "부산 어디까지 갔더라" 를
/// 지도에서 보는 문제다.
///
/// ## 창을 절대 좌표로 박지 않는다
///
/// 에셋 생성기가 **전국 최솟값에서 원점을 다시 잡는다**(`make_asset.py` 의
/// `ox, oy = min(xs) - PAD`). 그래서 다른 지역의 최외곽 경계만 바뀌어도
/// 수도권·대구의 로컬 좌표가 통째로 이동한다. `Rect.fromLTRB(181.5, ...)` 같은
/// 상수는 지형이 그대로여도 깨진다(Codex 27회차).
///
/// 손으로 확정하는 것은 **[InsetDefinition.focusIds] 와 여유 거리**뿐이고,
/// 창은 런타임에 그 지역들의 bounds 합집합에서 만든다.
///
/// ## 크기로 대상을 고르지 않는다
///
/// 독도(`DK001`)는 실제 0.187km² 를 M15 에서 **일부러 폭 8km 로 과장해** 울릉군
/// 오른쪽에 놓은 단위다. 화면에서 5.9px 라 "작은 지역" 목록에 들어온다.
/// 크기 기준으로 자동 선별하면 독도가 딸려 들어가 그 배치 결정이 깨진다.
/// 그래서 `focusIds` 는 명시적 집합이고, 테스트가 세 인셋 모두에서 독도 부재를
/// 검사한다.
library;

import 'dart:ui';

import 'map_data.dart';

/// 인셋 하나의 정의.
class InsetDefinition {
  const InsetDefinition({
    required this.id,
    required this.label,
    required this.focusIds,
    this.paddingKm = 6,
  });

  /// 저장하지 않지만 테스트와 화면이 붙잡을 안정된 이름.
  final String id;

  final String label;

  /// **창을 결정하는 지역들.** 이 지역은 전부 창 안에 완전히 들어간다.
  /// 표시 대상은 이보다 넓다 — 창에 완전히 들어오는 지역이 모두 나온다.
  final Set<String> focusIds;

  /// 창 가장자리 여유(km).
  final double paddingKm;
}

/// 인셋 하나가 실제로 다루는 창과 지역 목록.
class ResolvedInset {
  const ResolvedInset({
    required this.definition,
    required this.window,
    required this.regions,
  });

  final InsetDefinition definition;

  /// 지도 좌표계의 창.
  final Rect window;

  /// **창에 완전히 들어오는 지역만.** 걸친 지역은 넣지 않는다 —
  /// 잘려 보이는데 눌리거나, 안 보이는데 눌리는 상태를 만들지 않기 위해서다
  /// (Codex 27회차). 보이는 것과 누를 수 있는 것이 같다.
  final List<Region> regions;

  String get id => definition.id;
  String get label => definition.label;
}

/// 앱이 쓰는 인셋 셋. **구역으로 정하지 크기로 정하지 않는다.**
const List<InsetDefinition> kInsetDefinitions = [
  InsetDefinition(
    id: 'capital',
    label: '수도권',
    // 8px 미만인 인천·경기 지역들. 서울은 통합 단위라 크지만 창 안에 들어온다.
    focusIds: {
      '28125', '28177', '28237', '28245', // 인천
      '41111', '41113', '41115', '41117', // 수원
      '41133', '41171', '41173', // 성남중원·안양
      '41192', '41194', '41196', // 부천
      '41210', '41287', '41290', '41310', // 광명·고양일산서·과천·구리
      '41370', '41410', '41595', '41597', // 오산·군포·화성병점·화성동탄
    },
  ),
  InsetDefinition(
    id: 'busan',
    label: '부산·울산',
    focusIds: {
      '26110', '26140', '26170', '26200', '26230', '26260',
      '26290', '26320', '26380', '26410', '26470', '26500', '26530',
      '31110', '31170', // 울산 중구·동구
    },
  ),
  InsetDefinition(
    id: 'daegu',
    label: '대구',
    // **군위군(`27720`)을 뺀 도심 8개다.** 넣으면 창이 61×92km 로 벌어져
    // 확대가 2.4배로 떨어지고 중구가 6.3px 이 된다 — 다시 8px 아래다.
    // 빼면 48.8×57.3km · 3.8배 · 10.1px 이다(Codex 27회차 실측 일치).
    focusIds: {
      '27110', '27140', '27170', '27200',
      '27230', '27260', '27290', '27710',
    },
  ),
];

/// [def] 의 창과 표시 지역을 [data] 에서 구한다.
///
/// `focusIds` 에 현재 데이터에 없는 ID 가 있으면 [StateError] 다. 조용히
/// 빠지면 창이 줄어 인셋이 엉뚱해진다 — 행정구역 개편을 사람이 보게 만든다.
ResolvedInset resolveInset(InsetDefinition def, MapData data) {
  final byId = {for (final r in data.regions) r.scratchUnitId: r};
  final missing = def.focusIds.where((id) => !byId.containsKey(id)).toList();
  if (missing.isNotEmpty) {
    throw StateError('인셋 ${def.id} 의 기준 지역이 없다: ${missing.join(", ")}');
  }

  var l = double.infinity, t = double.infinity;
  var r = -double.infinity, b = -double.infinity;
  for (final id in def.focusIds) {
    final bb = byId[id]!.bounds;
    if (bb.left < l) l = bb.left;
    if (bb.top < t) t = bb.top;
    if (bb.right > r) r = bb.right;
    if (bb.bottom > b) b = bb.bottom;
  }
  final p = def.paddingKm;
  final window = Rect.fromLTRB(l - p, t - p, r + p, b + p);

  final regions = [
    for (final region in data.regions)
      if (window.contains(region.bounds.topLeft) &&
          window.contains(region.bounds.bottomRight))
        region,
  ];
  return ResolvedInset(
    definition: def,
    window: window,
    regions: regions,
  );
}

/// 지도 좌표 ↔ 인셋 캔버스 좌표.
///
/// **레터박스까지 한 객체가 소유한다.** 창과 캔버스의 종횡비가 다르면 상하나
/// 좌우에 여백이 생기는데, 그리기는 중앙에 맞춰 놓고 탭 역변환만
/// `local / scale + window.topLeft` 로 하면 **모든 탭이 어긋난다**
/// (Codex 27회차). 배율·목적 사각형·정변환·역변환이 같은 곳에 있어야 한다.
class InsetTransform {
  const InsetTransform._(this.window, this.dest, this.scale);

  /// 지도 좌표계의 창.
  final Rect window;

  /// 캔버스 안에서 창이 실제로 차지하는 사각형. 나머지는 레터박스다.
  final Rect dest;

  /// 지도 1 단위당 캔버스 px. **등방이다** — 인셋은 확대일 뿐 왜곡이 아니다.
  final double scale;

  factory InsetTransform.fit(Rect window, Size canvas) {
    final s = _min(canvas.width / window.width, canvas.height / window.height);
    final w = window.width * s;
    final h = window.height * s;
    final dest = Rect.fromLTWH(
      (canvas.width - w) / 2,
      (canvas.height - h) / 2,
      w,
      h,
    );
    return InsetTransform._(window, dest, s);
  }

  static double _min(double a, double b) => a < b ? a : b;

  /// 지도 좌표 → 캔버스 좌표.
  Offset toCanvas(Offset map) => Offset(
        dest.left + (map.dx - window.left) * scale,
        dest.top + (map.dy - window.top) * scale,
      );

  /// 캔버스 좌표 → 지도 좌표. **레터박스를 누르면 `null` 이다.**
  Offset? toMap(Offset canvas) {
    if (!dest.contains(canvas)) return null;
    return Offset(
      window.left + (canvas.dx - dest.left) / scale,
      window.top + (canvas.dy - dest.top) / scale,
    );
  }

  /// 캔버스 픽셀 허용 오차를 지도 단위로 바꾼다.
  ///
  /// **본지도의 배율을 쓰면 안 된다.** 인셋은 `InteractiveViewer` 밖이라
  /// 확대와 무관한 자체 배율을 가진다(Codex 27회차).
  double mapUnitsPerPx(double px) => scale == 0 ? 0 : px / scale;
}
