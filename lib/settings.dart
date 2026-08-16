import 'dart:convert';

/// 앱 설정의 **순수 모델과 직렬화**. 파일 I/O 는 `settings_store.dart` 에 있다.
///
/// ## 수집 기록과 실패 정책이 다르다
///
/// `collection.dart` 는 읽을 수 없으면 **격리하고 쓰기를 막는다** — 사용자가 긁어서
/// 쌓은 기록이라 조용히 잃으면 안 된다. 설정은 다르다. 잃는 것이 **취향 하나**이므로
/// 손상되면 기본값으로 계속 쓴다. 같은 계약을 공유시키면 과적합이다(Codex 22회차).
///
/// ## 기기 로컬 전용
///
/// S3 서버 동기화 대상이 아니다. 바다 테마는 그 기기의 취향이라 다른 기기까지
/// 따라가면 오히려 이상하다. Android 자동 백업에서도 이 파일만 빼 둔다
/// (`data_extraction_rules.xml`) — `allowBackup=false` 로 전체를 막으면
/// **수집 기록까지 백업에서 빠진다.**

/// 설정 스키마 버전.
const int kSettingsVersion = 1;

/// 저장되지 않은 값이거나 모르는 값일 때 쓰는 바다.
const String kDefaultSeaName = 'cerulean';

/// 사용자가 고를 수 있는 바다. **`flat` 은 없다** — 성능 측정용
/// (`--dart-define=SEA=flat`)이라 설정 화면과 저장 양쪽에서 거부한다.
const List<String> kSelectableSeaNames = ['cerulean', 'sunset', 'deep'];

/// 앱 설정 하나.
class AppSettings {
  const AppSettings({this.seaName = kDefaultSeaName});

  /// 바다 팔레트 이름. **UI 테마 밝기도 여기서 따라온다.**
  final String seaName;

  static const AppSettings defaults = AppSettings();

  AppSettings withSea(String name) => AppSettings(seaName: name);

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.seaName == seaName;

  @override
  int get hashCode => seaName.hashCode;

  @override
  String toString() => 'AppSettings($seaName)';
}

String encodeSettings(AppSettings s) => jsonEncode({
      'version': kSettingsVersion,
      'seaName': s.seaName,
    });

/// 저장 문자열을 설정으로. **읽을 수 없으면 기본값을 돌려준다.**
///
/// 예외를 던지지 않는 것이 수집 기록과의 결정적인 차이다. 설정이 깨졌다고
/// 앱을 못 쓰게 만들 이유가 없다. 모르는 팔레트 이름도 기본값으로 떨어뜨린다 —
/// 상한을 올린 미래 버전이나 실험용 이름이 들어올 수 있다.
AppSettings decodeSettings(String raw) {
  final Object? root;
  try {
    root = jsonDecode(raw);
  } on FormatException {
    return AppSettings.defaults;
  }
  if (root is! Map) return AppSettings.defaults;

  final version = root['version'];
  // **더 새로운 버전이라도 막지 않는다.** 수집 기록과 달리 덮어써도 잃는 것이
  // 취향 하나다. 대신 모르는 필드는 읽지 않으므로 그 값은 기본값이 된다.
  if (version is! int || version < 1) return AppSettings.defaults;

  final sea = root['seaName'];
  if (sea is! String || !kSelectableSeaNames.contains(sea)) {
    return AppSettings.defaults;
  }
  return AppSettings(seaName: sea);
}
