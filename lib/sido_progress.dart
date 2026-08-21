import 'map_data.dart';

/// 시도 하나의 수집 진행률.
///
/// 팝업이 "이 지역 하나" 를 넘어 **다음 목표**를 보여주기 위한 값이다.
/// 193번 반복되는 고정 문구만 두면 수집 앱으로서 심심하다.
class SidoProgress {
  const SidoProgress({
    required this.sidoName,
    required this.collected,
    required this.total,
  });

  final String sidoName;
  final int collected;
  final int total;

  int get remaining => total - collected;
  bool get complete => total > 0 && collected == total;

  /// 0~1. 지역이 없으면 0 이다 — 0 나눗셈을 만들지 않는다.
  double get ratio => total == 0 ? 0 : collected / total;

  @override
  String toString() => '$sidoName $collected/$total';
}

/// 전체와 시도 16개를 **한 번에** 구한 요약.
///
/// 기록 화면이 쓴다. 시도마다 [sidoProgressOf] 를 부르면 193개를 16번 훑는데,
/// 비용보다 **모집단 규칙이 두 곳으로 갈라지는 것**이 문제다(Codex 25회차).
/// 전체 수집 수도 여기서 나온 시도별 합이라 서로 어긋날 수 없다.
class CollectionSummary {
  const CollectionSummary({
    required this.collected,
    required this.total,
    required this.sidos,
  });

  /// **카탈로그를 훑어 센 값이다.** 넘겨받은 집합의 크기가 아니다 —
  /// 그것을 쓰면 알 수 없는 ID 까지 세어 194/193 이 된다(M1 계약).
  final int collected;
  final int total;

  /// `data.sidoNames` 와 **같은 순서**다. 달성률로 재정렬하지 않는다 —
  /// 긁을 때마다 행이 움직이면 "그 줄이 거기 있었다" 는 기억이 깨진다.
  final List<SidoProgress> sidos;

  int get remaining => total - collected;
  double get ratio => total == 0 ? 0 : collected / total;
  bool get complete => total > 0 && collected == total;
}

/// 전체와 시도별 진행률을 한 번의 순회로 구한다.
CollectionSummary collectionSummaryOf(MapData data, Set<String> scratched) {
  final n = data.sidoNames.length;
  final collected = List<int>.filled(n, 0);
  final total = List<int>.filled(n, 0);
  var all = 0;
  for (final r in data.regions) {
    total[r.sido]++;
    if (scratched.contains(r.scratchUnitId)) {
      collected[r.sido]++;
      all++;
    }
  }
  return CollectionSummary(
    collected: all,
    total: data.regions.length,
    sidos: [
      for (var i = 0; i < n; i++)
        SidoProgress(
          sidoName: data.sidoNames[i],
          collected: collected[i],
          total: total[i],
        ),
    ],
  );
}

/// [sidoIndex] 시도의 진행률.
///
/// **통합 단위는 1/1 이 된다.** 서울·제주는 시도 전체가 긁기 단위 하나여서,
/// 한 번 긁으면 그 시도가 끝난다(2026-08-14 통합 결정의 알려진 결과).
/// 그래서 화면은 분수만 보여주지 말고 완료 여부를 따로 말해야 한다.
SidoProgress sidoProgressOf(
  MapData data,
  Set<String> scratched,
  int sidoIndex,
) {
  var collected = 0;
  var total = 0;
  for (final r in data.regions) {
    if (r.sido != sidoIndex) continue;
    total++;
    if (scratched.contains(r.scratchUnitId)) collected++;
  }
  return SidoProgress(
    sidoName: data.sidoNames[sidoIndex],
    collected: collected,
    total: total,
  );
}
