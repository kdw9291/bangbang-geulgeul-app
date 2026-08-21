/// 앱 정보와 **지도 데이터 출처 표시**.
///
/// 출처 표시는 취향이 아니라 **CC BY 4.0 의무**다. 빠지면 라이선스 위반이라
/// 출시할 수 없다.
library;

/// 앱 버전. `pubspec.yaml` 의 `version:` 과 **일치해야 한다.**
///
/// `package_info_plus` 를 넣는 대신 상수로 두고 테스트가 `pubspec.yaml` 과
/// 대조한다(`app_info_test.dart`). 카테고리 생성물에 쓰는 freshness 검사와 같은 방식이다.
///
/// **전제**: 릴리스 버전을 `pubspec.yaml` 만으로 정한다. `flutter build` 에
/// `--build-name`·`--build-number` 를 주거나 flavor 를 도입하면 이 상수가
/// 실제 APK 와 어긋나므로 그때는 `package_info_plus` 로 바꾼다(Codex 22회차).
const String kAppVersionName = '1.0.0';
const String kAppBuildNumber = '1';

String get appVersionLabel => '$kAppVersionName ($kAppBuildNumber)';

/// 지도 데이터 출처. **CC BY 4.0 이 요구하는 항목을 전부 담는다.**
///
/// | 요구 | 어디에 |
/// |---|---|
/// | 저작자 표시 | `vuski/admdongkor` |
/// | 라이선스 명시와 링크 | CC BY 4.0 + URL |
/// | 자료 링크 | 배포본 URL |
/// | **변경 고지** | 아래 "적용한 변경" — 처음 초안에서 빠뜨렸다 |
const String kMapAttributionBody =
    '지도 경계 데이터는 통계청 SGIS 행정동 경계(공공누리 제1유형)를 '
    'vuski/admdongkor 가 수정·배포한 ver20260701 을 기반으로 합니다. '
    '해당 배포본은 Creative Commons Attribution 4.0 International '
    '(CC BY 4.0) 라이선스를 따릅니다.';

/// **변경 고지.** CC BY 4.0 은 자료를 고쳤으면 고쳤다고 밝히기를 요구한다.
const String kMapAttributionChanges =
    '방방긁긁은 앱에 맞게 다음을 적용했습니다 — 시군구·시도 단위 병합, '
    '4% 좌표 단순화, 화면 좌표 투영, 서울특별시·제주특별자치도와 '
    '부산·대구·대전·울산광역시의 단일 단위 통합, '
    '인천광역시의 강화군·옹진군을 제외한 단일 단위 통합, '
    '독도 단위 신설과 크기 조정.';

const String kMapDistributionUrl =
    'https://github.com/vuski/admdongkor/tree/master/ver20260701';
const String kMapLicenseUrl = 'https://creativecommons.org/licenses/by/4.0/';
const String kMapSourceUrl = 'https://sgis.kostat.go.kr/';
