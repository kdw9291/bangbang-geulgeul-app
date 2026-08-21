/// M7 달성 메달. **순수 로직이라 위젯을 모른다.**
///
/// ## 메달은 지금 "현재 상태에서 계산되는 배지" 다
///
/// 저장 스키마에 메달을 넣지 않았다(2026-08-18 사용자 결정). 수집 수에서 매번
/// 계산하므로 [CollectionSnapshot] 이 그대로면 결과도 그대로다.
///
/// **받아들인 위험**: 행정구역 개편으로 긁기 단위가 현재 카탈로그 밖으로 밀려나면
/// 수집 수가 줄어 **이미 받은 메달이 다시 잠길 수 있다.** M1 의 "알 수 없는 ID 는
/// 보존하되 표시·달성률에서 제외" 계약을 따른 결과다. 영구 훈장으로 만들려면
/// 메달 ID 와 획득 시각을 저장해야 하고 스키마 v2 와 마이그레이션이 따라온다 —
/// **S3 서버 연동에서 서버 스키마를 짜며 함께 설계한다.**
///
/// ## 임계치에 총 개수를 넣지 않는다
///
/// 사용자가 정한 값은 `20 · 50 · 100 · 150 · 전국 완주` 다(2026-08-18).
/// 마지막 것의 의미는 **숫자 193 이 아니라 "지금 있는 것을 다 모았다"** 이므로
/// 상수로 박지 않고 [MedalSet.of] 가 카탈로그 크기에서 만든다. 행정구역 개편으로
/// 193 이 바뀌어도 마지막 메달은 계속 "전국 완주" 를 뜻한다.
/// 실제로 2026-08-20 광역시 통합에서 232 → 193 이 됐고 이 코드는 그대로였다.
library;

import 'map_data.dart';

/// 개수로 정의되는 고정 메달의 임계치. **전국 완주는 여기 없다.**
const List<int> kFixedMedalThresholds = [20, 50, 100, 150];

/// 메달 하나.
class Medal {
  const Medal({
    required this.id,
    required this.label,
    required this.threshold,
    required this.nationwide,
  });

  /// 저장하지 않지만 테스트와 화면이 붙잡을 안정된 이름이다.
  /// **임계치 숫자를 id 로 쓰지 않는다** — 총 개수가 바뀌면 흔들린다.
  final String id;

  final String label;

  /// 이 개수 이상이면 획득. 전국 완주는 카탈로그 크기와 같다.
  final int threshold;

  /// 전국 완주 메달인가. 판정 방식이 다르다 — 아래 [MedalSet.achieved] 참고.
  final bool nationwide;
}

/// 카탈로그 크기에 맞춰 만든 메달 **최대 다섯**.
///
/// 총 개수가 고정 임계치와 같거나 작으면 그만큼 줄어든다 — 총 150 이면
/// `150곳` 과 `전국 완주` 가 같은 값이라 하나로 합쳐 넷이 된다.
class MedalSet {
  const MedalSet(this.medals, this.total);

  /// 임계치 오름차순.
  final List<Medal> medals;

  /// 현재 카탈로그의 긁기 단위 수. 전국 완주 판정의 분모다.
  final int total;

  /// [data] 의 지역 수에서 만든다.
  factory MedalSet.of(MapData data) => MedalSet.forTotal(data.regions.length);

  factory MedalSet.forTotal(int total) {
    final list = <Medal>[
      for (final t in kFixedMedalThresholds)
        if (t < total)
          Medal(id: 'count$t', label: '$t곳', threshold: t, nationwide: false),
      Medal(
        id: 'nationwide',
        label: '전국 완주',
        threshold: total,
        nationwide: true,
      ),
    ];
    return MedalSet(list, total);
  }

  /// [collected] 로 획득 여부를 판정한다.
  ///
  /// 고정 메달은 `>=` 다. 전국 완주만 **`== total` 로 못박는다** — `>=` 로 두면
  /// 모집단을 잘못 세어 수집 수가 총 개수를 넘는 버그가 "완주" 로 보여 가려진다.
  /// 알 수 없는 ID 를 섞어 세던 실수가 실제로 있었다(M6 갤러리).
  bool achieved(Medal m, int collected) =>
      m.nationwide ? total > 0 && collected == total : collected >= m.threshold;

  /// 아직 못 받은 첫 메달. **다 받았으면 `null` 이다.**
  ///
  /// `remaining = 0` 을 돌려주면 화면이 "0곳 남았어요" 라고 쓴다.
  Medal? nextAfter(int collected) {
    for (final m in medals) {
      if (!achieved(m, collected)) return m;
    }
    return null;
  }

  /// [collected] 기준으로 받은 메달 수.
  int achievedCount(int collected) =>
      medals.where((m) => achieved(m, collected)).length;
}
