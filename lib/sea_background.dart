import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 바다 배경 — 단색 대신 **동글동글한 유기적 그라데이션**을 깐다.
///
/// 참조는 `sample_image/바다색.png` 의 시안~세룰리안 계열 색상계다.
/// 단색(`#16303D`)은 칙칙하고 지도를 어둡게 눌렀다.
///
/// ## 왜 blob 을 겹치는가
///
/// 선형 그라데이션은 방향이 보여 "배경지" 처럼 읽힌다. 중심이 서로 다른 원형
/// 그라데이션을 부드럽게 겹치면 경계가 사라지고 물감이 번진 느낌이 남는다.
/// 참조 이미지가 정확히 그 형태다.
///
/// ## 성능 — 무엇이 줄고 무엇이 안 줄어드는가
///
/// 배경은 지도 Picture 캐시 **밖**이라 매 프레임 경로에 있다. [SeaBackgroundCache]
/// 가 크기·팔레트별로 `ui.Picture` 를 기록해 두어 **셰이더 객체 생성과 Dart 쪽
/// 기록 비용**을 프레임에서 걷어낸다.
///
/// **래스터 비용까지 사라지는 것은 아니다.** `ui.Picture` 는 픽셀 이미지가 아니라
/// 그리기 명령 묶음이라, 래스터 캐시가 적중하지 않으면 GPU 는 여전히 radial
/// gradient 여섯 개를 실행하고 합성한다 (Codex 11회차 지적).
///
/// 단위 테스트가 재는 것은 **기록 비용**이며 재생 비용의 근거가 아니다.
/// 실제 판단은 실기기 `--profile` 의 래스터 시간으로 한다.
@immutable
class SeaBlob {
  const SeaBlob(this.center, this.radius, this.color, {this.opacity = 1.0});

  /// 화면 기준 상대 좌표 (0~1). 화면 밖으로 넘겨도 된다 — 잘린 원이
  /// 오히려 유기적으로 보인다.
  final Offset center;

  /// 짧은 변 기준 상대 반지름.
  final double radius;

  final Color color;
  final double opacity;
}

@immutable
class SeaPalette {
  const SeaPalette({
    required this.name,
    required this.base,
    required this.blobs,
    required this.foil,
    required this.brightness,
  });

  final String name;

  /// 이 바다와 함께 쓸 앱 UI 톤.
  ///
  /// 바다만 밝히고 나머지를 어둡게 두면 팝업을 열 때마다 밝은 지도 위에 검은
  /// 시트가 덮여 따로 논다. **바다를 고르면 UI 톤이 따라온다** — 설정 항목이
  /// 하나로 유지되고 조합이 어긋날 수 없다.
  final Brightness brightness;

  /// blob 이 닿지 않는 구석까지 채우는 바탕색.
  final Color base;

  final List<SeaBlob> blobs;

  /// 이 배경 위에서 쓸 은박(미수집) 색. 배경이 밝아지면 은박도 함께
  /// 조정해야 대비가 유지된다.
  ///
  /// 셀 구분 획은 팔레트에 두지 않는다 — 획은 배경이 아니라 **셀 위**에
  /// 그려지므로 배경색과 무관하다.
  final Color foil;

  // `==` 를 **오버라이드하지 않는다.** 기본 identity 비교를 쓴다.
  //
  // 처음에는 `name` 만 비교했는데, 이 값이 [SeaBackgroundCache] 의 캐시 키이자
  // `KoreaMapPainter.shouldRepaint` 의 판단 근거다. 이름이 같고 내용이 다른
  // 팔레트를 넣으면 **리페인트도 안 하고 캐시가 옛 그림을 계속 재생해** 새 배경이
  // 영영 화면에 나오지 않는다 (Codex 11회차 지적).
  //
  // Picture 캐시 키에 해시를 썼다가 고친 것(1회차 Low #11)과 같은 유형이다 —
  // **불완전한 값을 캐시 식별자로 삼으면 다른 그림을 재생하게 된다.**
  // 팔레트는 canonical `const` 상수 몇 개뿐이라 identity 로 충분하고,
  // 값이 같은 별개 인스턴스를 miss 로 처리하는 쪽이 안전한 방향이다.
}

/// 후보 A — **세룰리안 바다.** 사용자가 고른 기본값 (2026-08-14).
///
/// 두 번의 실패를 거친 값이다. 처음 `#2E86B8` 계열은 **경상·부산의 파란 시도
/// 색이 바다와 섞였고**, 채도를 낮추자 대비가 살아났다. 배경이 셀 색과 경쟁하면
/// 수집 현황이 안 읽힌다.
///
/// 은박(`#56657C`)은 밝은 배경에서도 미수집 지역이 묻히지 않을 만큼 눌렀다.
/// 더 밝은 시안 안(`#EAF6FC` 바탕)도 만들어 봤으나 **서해안 섬들이 바다에
/// 사라져** 폐기했다.
const kSeaCerulean = SeaPalette(
  name: 'cerulean',
  brightness: Brightness.light,
  base: Color(0xFF7FC4DE),
  foil: Color(0xFF56657C),
  blobs: [
    SeaBlob(Offset(0.40, 0.32), 0.70, Color(0xFF9BD6E8)),
    SeaBlob(Offset(0.84, 0.16), 0.44, Color(0xFFC2E8F2)),
    SeaBlob(Offset(0.10, 0.66), 0.52, Color(0xFF6DB6D4)),
    SeaBlob(Offset(0.58, 0.92), 0.50, Color(0xFFA9B9E4)),
    SeaBlob(Offset(0.94, 0.70), 0.38, Color(0xFF8FD2E2)),
    SeaBlob(Offset(0.22, 0.08), 0.28, Color(0xFFD8CCEE)),
  ],
);

/// 후보 B — **노을 바다.** A 와 색상 축이 완전히 갈린다.
///
/// 밝기가 아니라 **색상**을 갈라야 후보가 구분된다는 것을 렌더로 확인했다.
/// 밝기만 다른 안들은 나란히 놓으면 사용자가 차이를 느끼지 못했다.
///
/// 파란 계열을 피했으므로 파란 시도 색과도 경쟁하지 않는다.
const kSeaSunset = SeaPalette(
  name: 'sunset',
  brightness: Brightness.light,
  base: Color(0xFFFDEEE4),
  foil: Color(0xFF8A7382),
  blobs: [
    SeaBlob(Offset(0.42, 0.36), 0.70, Color(0xFFF7B7A8)),
    SeaBlob(Offset(0.82, 0.14), 0.44, Color(0xFFFAD6B0)),
    SeaBlob(Offset(0.10, 0.62), 0.50, Color(0xFFE9A0BE)),
    SeaBlob(Offset(0.56, 0.92), 0.52, Color(0xFFC9A6E0)),
    SeaBlob(Offset(0.94, 0.74), 0.40, Color(0xFFF3C0D2)),
    SeaBlob(Offset(0.22, 0.08), 0.28, Color(0xFFFFD9A8)),
  ],
);

/// 후보 C — **깊은 바다.** 기존 어두운 테마를 유지하되 단색만 걷어낸다.
///
/// blob 대비를 키워 덩어리가 보이게 했다. 처음 값은 차이가 작아 단색과
/// 구분되지 않았다.
const kSeaDeep = SeaPalette(
  name: 'deep',
  brightness: Brightness.dark,
  base: Color(0xFF0C2A38),
  foil: Color(0xFF474553),
  blobs: [
    SeaBlob(Offset(0.42, 0.34), 0.70, Color(0xFF1A6884)),
    SeaBlob(Offset(0.82, 0.16), 0.44, Color(0xFF2A8CA0)),
    SeaBlob(Offset(0.10, 0.64), 0.52, Color(0xFF0E3E5C)),
    SeaBlob(Offset(0.58, 0.92), 0.50, Color(0xFF1E4C7A)),
    SeaBlob(Offset(0.94, 0.72), 0.38, Color(0xFF2FA0B4)),
    SeaBlob(Offset(0.22, 0.08), 0.28, Color(0xFF3A4E86)),
  ],
);

/// **성능 비교 전용 — 설정 화면에 노출하지 않는다.**
///
/// blob 이 없어 `base` 만 칠하는 사실상 단색 배경이다. 그라데이션 도입 전과
/// 후를 **같은 바이너리에서 변수 하나만 바꿔 교대 실행**해 비교하려고 둔다.
/// 순차 실행 비교는 기기 온도와 실행 편차가 섞여 근거가 약하다 — 이 프로젝트는
/// 래스터 차이를 잘못된 원인에 귀속했다가 철회한 전례가 있다.
const kSeaFlat = SeaPalette(
  name: 'flat',
  brightness: Brightness.dark,
  base: Color(0xFF16303D), // 그라데이션 도입 전 단색
  foil: Color(0xFF474553),
  blobs: [],
);

/// 설정 화면에 보여줄 순서. 사용자가 여기서 고른다.
///
/// [kSeaFlat] 은 측정 전용이라 넣지 않는다.
const kSeaPalettes = [kSeaCerulean, kSeaSunset, kSeaDeep];

/// 이름으로 팔레트를 찾는다. 측정용 `--dart-define=SEA=flat` 과
/// 나중에 설정 화면이 저장한 선택을 되살릴 때 쓴다.
///
/// **반드시 기존 상수를 돌려준다.** 매번 새 `SeaPalette` 를 만들면 동등성이
/// identity 라 캐시가 계속 miss 된다.
SeaPalette seaPaletteByName(String name) => switch (name) {
      'flat' => kSeaFlat,
      'sunset' => kSeaSunset,
      'deep' => kSeaDeep,
      _ => kSeaCerulean,
    };

/// 기본값. **2026-08-14 사용자가 세룰리안을 골랐다.**
///
/// 밝은 계열이라 [SeaPalette.brightness] 가 `light` 이고, 앱 UI 도 함께
/// 라이트 테마로 간다 (`app_theme.dart`).
const kSeaAdopted = kSeaCerulean;

/// [palette] 를 [size] 에 그린다.
///
/// blob 은 중심에서 가장자리로 갈수록 투명해진다. `stops` 를 0 → 1 로 두고
/// 알파만 떨어뜨리면 원 경계가 보이지 않는다.
void paintSea(Canvas canvas, Size size, SeaPalette palette) {
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = palette.base);

  // 반지름 기준을 짧은 변으로 둔다. 긴 변을 쓰면 세로로 긴 화면에서
  // blob 이 좌우로 넘쳐 단색처럼 보인다.
  final unit = size.shortestSide;

  for (final b in palette.blobs) {
    final center = Offset(b.center.dx * size.width, b.center.dy * size.height);
    final r = b.radius * unit;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          b.color.withValues(alpha: b.opacity),
          b.color.withValues(alpha: 0),
        ], const [
          0,
          1,
        ]),
    );
  }
}

/// 크기·팔레트별 배경 `ui.Picture` 캐시.
///
/// 배경은 매 프레임 경로에 있으나 내용은 크기와 팔레트에만 의존한다.
///
/// **[obtain] 이 돌려주는 Picture 는 다음 cache miss 또는 [dispose] 전까지만
/// 유효하다.** 같은 키로 다시 부르면 같은 Picture 를 그대로 돌려주지만, 크기나
/// 팔레트가 바뀌면 이전 것을 `dispose` 한다. 호출부가 이를 보관했다가 나중에 다시
/// 그리면 이미 해제된 Picture 를 쓰게 된다. 현재 유일한 호출부인
/// `KoreaMapPainter.paint()` 는 받은 즉시 `drawPicture` 하고 보관하지 않는다 —
/// 이 계약을 깨지 말 것.
class SeaBackgroundCache {
  ui.Picture? _picture;
  Size? _size;
  SeaPalette? _palette;

  ui.Picture obtain(Size size, SeaPalette palette) {
    if (_picture case final p? when _size == size && _palette == palette) {
      return p;
    }
    final rec = ui.PictureRecorder();
    paintSea(Canvas(rec), size, palette);
    _picture?.dispose();
    final p = rec.endRecording();
    _picture = p;
    _size = size;
    _palette = palette;
    return p;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _size = null;
    _palette = null;
  }
}
