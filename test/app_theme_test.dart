import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/sea_background.dart';

/// M11 계약 검증.
///
/// 이전 테스트들은 새 생성자 인자를 만족시키려고 `kThemeDark` 를 넘길 뿐이라
/// 테마 동작 자체를 검사하지 않았다 (Codex 12회차 지적).
void main() {
  group('바다 팔레트가 테마를 결정한다', () {
    test('밝은 바다는 라이트, 어두운 바다는 다크', () {
      // 이 대응이 깨지면 "밝은 지도 + 어두운 팝업" 부조화가 돌아온다.
      expect(kSeaCerulean.brightness, Brightness.light);
      expect(kSeaSunset.brightness, Brightness.light);
      expect(kSeaDeep.brightness, Brightness.dark);
      expect(kSeaFlat.brightness, Brightness.dark, reason: '측정용 단색은 기존 다크 기준');
    });

    test('themeForSea 가 밝기를 그대로 따른다', () {
      // `main.dart` 와 이 테스트가 **같은 함수**를 쓴다. 각자 계산하면
      // 제품 코드만 뒤집혀도 테스트가 통과한다.
      expect(identical(themeForSea(Brightness.light), kThemeLight), isTrue);
      expect(identical(themeForSea(Brightness.dark), kThemeDark), isTrue);
      for (final p in [...kSeaPalettes, kSeaFlat]) {
        expect(themeForSea(p.brightness).brightness, p.brightness,
            reason: p.name);
      }
    });
  });

  group('AppThemeScope', () {
    testWidgets('Scope 가 있으면 그 테마를 돌려준다', (tester) async {
      late AppTheme seen;
      await tester.pumpWidget(AppThemeScope(
        theme: kThemeLight,
        child: Builder(builder: (c) {
          seen = AppThemeScope.of(c);
          return const SizedBox();
        }),
      ));
      expect(identical(seen, kThemeLight), isTrue);
    });

    testWidgets('Scope 가 없으면 실패한다', (tester) async {
      // 조용히 다크로 떨어지면, Scope 를 빠뜨린 화면이 "밝은 바다 + 다크 UI"
      // 로 잘못 그려져도 아무도 모른다. 누락은 프로그래밍 오류다.
      await tester.pumpWidget(Builder(builder: (c) {
        expect(() => AppThemeScope.of(c), throwsA(anything));
        return const SizedBox();
      }));
    });

    testWidgets('maybeOf 는 Scope 가 없어도 null 만 돌려준다', (tester) async {
      AppTheme? seen = kThemeLight;
      await tester.pumpWidget(Builder(builder: (c) {
        seen = AppThemeScope.maybeOf(c);
        return const SizedBox();
      }));
      expect(seen, isNull);
    });

    testWidgets('팝업 route 에서도 같은 테마가 보인다', (tester) async {
      // 팝업은 Navigator 위에 뜬다. `home` 아래에 Scope 를 두면 보이지 않아
      // `MaterialApp.builder` 에서 감싸야 한다 — 그 구조를 고정한다.
      late AppTheme inSheet;
      await tester.pumpWidget(MaterialApp(
        builder: (c, child) =>
            AppThemeScope(theme: kThemeLight, child: child!),
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: c,
              builder: (sc) {
                inSheet = AppThemeScope.of(sc);
                return const SizedBox(height: 40);
              },
            ),
            child: const Text('열기'),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(identical(inSheet, kThemeLight), isTrue,
          reason: '팝업이 앱 테마를 상속받지 못했다');
    });
  });

  group('실제 앱 배선', () {
    testWidgets('MapScratchApp 아래에서 Scope 와 Material 밝기가 일치한다',
        (tester) async {
      // 테스트가 자체 MaterialApp 을 만들면, 실제 `main.dart` 가 나중에
      // `home` 아래 Scope 로 잘못 바뀌어도 잡지 못한다. 실물을 pump 한다.
      await tester.pumpWidget(const MapScratchApp());
      await tester.pump();

      final ctx = tester.element(find.byType(Scaffold).first);
      final scope = AppThemeScope.of(ctx);
      expect(scope.brightness, Theme.of(ctx).brightness,
          reason: '앱 테마와 Material 밝기가 어긋났다');
      expect(identical(scope, themeForSea(kSeaAdopted.brightness)), isTrue,
          reason: '기본 팔레트에 대응하는 테마가 아니다');
    });
  });

  group('대비', () {
    // 눈으로 통과한 것과 대비 기준을 통과한 것은 다르다. 처음 라이트 값은
    // 4.23:1 · 1.75:1 로 WCAG AA 에 미달했다 (Codex 12회차 지적).
    double lin(int c) {
      final v = c / 255;
      return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    }

    double lum(Color c) =>
        0.2126 * lin((c.r * 255).round()) +
        0.7152 * lin((c.g * 255).round()) +
        0.0722 * lin((c.b * 255).round());

    double contrast(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

    test('라이트 본문 텍스트가 AA 를 넘는다', () {
      final t = kThemeLight;
      expect(contrast(over(t.onSurface, t.surface), t.surface),
          greaterThanOrEqualTo(4.5));
      expect(contrast(over(t.onSurfaceMuted, t.surface), t.surface),
          greaterThanOrEqualTo(4.5));
      expect(contrast(over(t.onSurfaceFaint, t.background), t.background),
          greaterThanOrEqualTo(4.5),
          reason: '시도명·긁기 안내가 여기 쓰인다');
    });

    test('흐린 표시가 두 테마 모두 UI 기준 3:1 을 넘는다', () {
      for (final t in [kThemeLight, kThemeDark]) {
        expect(contrast(over(t.onSurfaceGhost, t.surface), t.surface),
            greaterThanOrEqualTo(3.0),
            reason: '${t.brightness} 시트 손잡이');
      }
    });

    test('텍스트 위계가 뒤집히지 않는다', () {
      // faint 를 올리다 muted 보다 강해져 위계가 뒤집힌 적이 있다.
      for (final t in [kThemeLight, kThemeDark]) {
        final c = [t.onSurface, t.onSurfaceMuted, t.onSurfaceFaint, t.onSurfaceGhost]
            .map((x) => contrast(over(x, t.surface), t.surface))
            .toList();
        for (var i = 0; i + 1 < c.length; i++) {
          expect(c[i], greaterThanOrEqualTo(c[i + 1]),
              reason: '${t.brightness}: 단계 $i 가 다음 단계보다 흐리다');
        }
      }
    });

    test('다크 본문 텍스트도 AA 를 넘는다', () {
      final t = kThemeDark;
      expect(contrast(over(t.onSurfaceMuted, t.surface), t.surface),
          greaterThanOrEqualTo(4.5));
      expect(contrast(over(t.onSurfaceFaint, t.background), t.background),
          greaterThanOrEqualTo(4.5));
    });

    test('선택 외곽선은 어떤 시도 색·바다 위에서도 보인다', () {
      // 단일 강조색으로는 불가능하다 — 라이트 후보 #E8890C 는 강원과 1.04:1,
      // 다크의 기존 노랑도 제주와 1.34:1 이었다. 두 겹 중 하나는 반드시 보여야 한다.
      final backgrounds = <Color>[
        ...kSidoColors,
        for (final p in [...kSeaPalettes, kSeaFlat]) p.base,
      ];
      for (final t in [kThemeLight, kThemeDark]) {
        for (final bg in backgrounds) {
          final best = [
            contrast(t.selectionOuter, bg),
            contrast(t.selectionInner, bg),
          ].reduce((a, b) => a > b ? a : b);
          expect(best, greaterThanOrEqualTo(3.0),
              reason: '$bg 위에서 선택 외곽선이 보이지 않는다');
        }
      }
    });
  });
}
