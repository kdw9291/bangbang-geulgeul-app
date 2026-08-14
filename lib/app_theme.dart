import 'package:flutter/material.dart';

/// 앱 색 토큰 — 라이트/다크 두 벌.
///
/// 하드코딩된 색을 여기로 모았다. 바다 배경 기본값이 밝은 계열(cerulean)로
/// 정해지면서 **지도만 밝고 팝업·통계바·긁기 화면은 어두운** 부조화가 생겼다.
///
/// ## 무엇이 여기 없는가
///
/// - **시도 색**(`kSidoColors`)과 **바다 팔레트**는 테마 토큰이 아니다.
///   수집 현황을 나타내는 **데이터 색**이라 테마가 바뀌어도 같아야 한다
/// - **아트 3색**(먹·주황·청록)도 아니다. 아트 규격이 고정색을 강제한다
@immutable
class AppTheme {
  const AppTheme({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onSurfaceFaint,
    required this.onSurfaceGhost,
    required this.foilLight,
    required this.foilDark,
    required this.good,
    required this.bad,
    required this.selectionOuter,
    required this.selectionInner,
  });

  final Brightness brightness;

  /// 화면 바탕 (Scaffold).
  final Color background;

  /// 팝업 시트·통계바처럼 바탕 위에 얹히는 면.
  final Color surface;

  /// 면 위에 한 단계 더 얹히는 것 (버튼 배경 등).
  final Color surfaceVariant;

  final Color onSurface;
  final Color onSurfaceMuted;
  final Color onSurfaceFaint;

  /// 아주 흐린 보조 표시 (팝업의 `?` 등).
  final Color onSurfaceGhost;

  /// 은박 결 그라데이션의 밝은 쪽과 어두운 쪽.
  ///
  /// 은박은 **긁기 전 내용을 가리는 것**이라 테마와 무관하게 은색이어야 하지만,
  /// 밝은 테마에서 어두운 은박을 쓰면 화면에서 홀로 튄다. 톤을 맞춘다.
  final Color foilLight;
  final Color foilDark;

  /// 디버그 통계바의 좋음/나쁨 표시.
  final Color good;
  final Color bad;

  /// 지도에서 선택한 지역 외곽선 — **두 겹으로 그린다.**
  ///
  /// 단일 강조색으로는 시도 16색과 바다 3종을 모두 커버할 수 없다. 실측하니
  /// 라이트 후보 `#E8890C` 는 강원 `#E8833A` 와 **1.04:1**, 경기와 1.03:1 로
  /// 사실상 보이지 않았다. 다크의 기존 노랑 `#FFD43B` 도 제주와 1.34:1 이라
  /// **원래부터 같은 결함이 있었다.**
  ///
  /// 굵은 [selectionOuter] 위에 얇은 [selectionInner] 를 겹치면 배경이 밝든
  /// 어둡든 둘 중 하나가 반드시 대비를 만든다 — 19개 배경 전부에서 최소
  /// **4.56:1** 을 보장한다 (직접 계산).
  final Color selectionOuter;
  final Color selectionInner;
}

/// 다크 — 기존 앱 색을 그대로 옮겼다.
///
/// 접근성 때문에 바꾼 것은 `onSurfaceGhost` 하나뿐이다 (`0x3D` → `0x5A`).
/// 시트 손잡이가 2.14:1 로 UI 기준 3:1 에 미달했다.
const kThemeDark = AppTheme(
  brightness: Brightness.dark,
  background: Color(0xFF141319),
  surface: Color(0xFF1D1C25),
  surfaceVariant: Color(0xFF2A2833),
  onSurface: Color(0xFFFFFFFF),
  onSurfaceMuted: Color(0xB3FFFFFF), // white70
  // 다크 faint 는 **기존 값을 유지한다.** 배경 대비 6.02:1 로 이미 기준을
  // 넘었는데 0xB8 로 올렸더니 muted(9.42:1)보다 강해져 **위계가 뒤집혔다**
  // (Codex 12회차 재검토 지적). ghost 만 손잡이 3:1 을 맞추려고 올린다.
  onSurfaceFaint: Color(0x8AFFFFFF),
  onSurfaceGhost: Color(0x5AFFFFFF),
  foilLight: Color(0xFF5A5766),
  foilDark: Color(0xFF3B3944),
  good: Color(0xFF69DB7C),
  bad: Color(0xFFFF8787),
  selectionOuter: Color(0xFF15181D),
  selectionInner: Color(0xFFFFFFFF),
);

/// 라이트 — 밝은 바다 팔레트와 함께 쓴다.
///
/// `onSurfaceFaint`·`onSurfaceGhost` 는 실측 대비로 정했다. 처음 값
/// (`0x99`/`0x44`)은 각각 4.23:1 · 1.75:1 로 WCAG AA(일반 4.5:1,
/// 큰 글자·UI 3:1)에 미달했다.
const kThemeLight = AppTheme(
  brightness: Brightness.light,
  background: Color(0xFFF1F6FA),
  surface: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFE3EDF4),
  onSurface: Color(0xFF16212E),
  onSurfaceMuted: Color(0xCC16212E),
  onSurfaceFaint: Color(0xA816212E),
  onSurfaceGhost: Color(0x7A16212E),
  foilLight: Color(0xFFD3DCE5),
  foilDark: Color(0xFFAAB7C4),
  good: Color(0xFF2B8A3E),
  bad: Color(0xFFD9480F),
  selectionOuter: Color(0xFFFFFFFF),
  selectionInner: Color(0xFF15181D),
);

/// 바다 팔레트에 대응하는 앱 테마.
///
/// `main.dart` 와 테스트가 **같은 함수**를 쓴다. 각자 계산하면 한쪽만 뒤집혀도
/// 테스트가 잡지 못한다 (Codex 12회차 지적).
AppTheme themeForSea(Brightness brightness) =>
    brightness == Brightness.light ? kThemeLight : kThemeDark;

/// 위젯 트리에 현재 테마를 흘린다.
///
/// 긁기 화면은 `Navigator.push` 로 열리지만 같은 트리 아래라 그대로 상속받는다.
class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final AppTheme theme;

  /// 조상에 [AppThemeScope] 가 없으면 **실패한다.**
  ///
  /// 처음에는 다크로 조용히 떨어지게 두었는데, 그러면 Scope 를 빠뜨린 화면이
  /// "밝은 바다 + 다크 UI" 로 잘못 그려져도 아무도 모른다. 누락은 복구할 상황이
  /// 아니라 프로그래밍 오류다 (Codex 12회차 지적).
  static AppTheme of(BuildContext context) {
    final t = maybeOf(context);
    assert(t != null, 'AppThemeScope 가 조상에 없다. MaterialApp.builder 를 확인할 것.');
    if (t == null) {
      throw FlutterError('AppThemeScope 가 조상에 없다 — 테마 색을 결정할 수 없다.');
    }
    return t;
  }

  /// Scope 가 없을 수 있는 곳에서만 쓴다. 테스트가 위젯을 떼어 올릴 때 등.
  static AppTheme? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppThemeScope>()
      ?.theme;

  @override
  bool updateShouldNotify(AppThemeScope old) => old.theme != theme;
}
