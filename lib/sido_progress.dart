import 'map_data.dart';

/// 시도 하나의 수집 진행률.
///
/// 팝업이 "이 지역 하나" 를 넘어 **다음 목표**를 보여주기 위한 값이다.
/// 232번 반복되는 고정 문구만 두면 수집 앱으로서 심심하다.
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
