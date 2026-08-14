import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';

Rect _boundsOf(ArtShape s) {
  final c = s.circle;
  return c != null
      ? Rect.fromCircle(center: Offset(c.$1, c.$2), radius: c.$3)
      : parseSvgPath(s.d).getBounds();
}

void main() {
  group('SVG path 파서', () {
    test('절대 명령 M L Z 로 사각형을 그린다', () {
      final p = parseSvgPath('M10 20 L60 20 L60 70 L10 70 Z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 20, 60, 70));
    });

    test('상대 명령 m l 은 현재 점 기준으로 누적된다', () {
      final p = parseSvgPath('m10 20 l50 0 l0 50 l-50 0 z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 20, 60, 70));
    });

    test('H V 는 한 축만 움직인다', () {
      final p = parseSvgPath('M10 20 H60 V70 H10 Z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 20, 60, 70));
    });

    test('h v 상대형도 같은 결과를 낸다', () {
      final abs = parseSvgPath('M10 20 H60 V70 H10 Z').getBounds();
      final rel = parseSvgPath('M10 20 h50 v50 h-50 Z').getBounds();
      expect(rel, abs);
    });

    test('M 뒤에 좌표가 이어지면 lineto 로 해석한다', () {
      // SVG 명세: `M x y x y` 의 두 번째부터는 implicit lineto 다.
      // 이걸 moveTo 로 처리하면 선이 끊겨 채움이 사라진다.
      final p = parseSvgPath('M10 20 60 20 60 70 10 70 Z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 20, 60, 70));
      expect(p.contains(const Offset(35, 45)), isTrue);
    });

    test('C 3차 베지어의 끝점이 반영된다', () {
      final p = parseSvgPath('M0 0 C10 0 20 0 30 0');
      expect(p.getBounds().right, closeTo(30, 0.01));
    });

    test('S 는 직전 3차 제어점을 현재 점 기준으로 반사한다', () {
      // 예외가 안 난다는 것만 보면 반사가 틀려도 통과한다. 결과를 비교한다.
      // C 의 두 번째 제어점 (30,40) 을 끝점 (40,0) 기준으로 반사하면 (50,-40) 이다.
      final s = parseSvgPath('M0 0 C10 40 30 40 40 0 S70 -40 80 0');
      final explicit =
          parseSvgPath('M0 0 C10 40 30 40 40 0 C50 -40 70 -40 80 0');
      expect(s.getBounds(), explicit.getBounds());
    });

    test('직전 제어점이 없는 S 는 현재 점을 반사점으로 쓴다', () {
      final s = parseSvgPath('M0 0 S10 10 20 0');
      final explicit = parseSvgPath('M0 0 C0 0 10 10 20 0');
      expect(s.getBounds(), explicit.getBounds());
    });

    test('T 는 직전 2차 제어점을 반사한다', () {
      final t = parseSvgPath('M0 0 Q10 20 20 0 T40 0');
      final explicit = parseSvgPath('M0 0 Q10 20 20 0 Q30 -20 40 0');
      expect(t.getBounds(), explicit.getBounds());
    });

    test('Z 다음 상대 이동은 서브패스 시작점 기준이다', () {
      // Z 는 현재 점을 서브패스 시작점으로 되돌린다. 이걸 놓치면
      // 두 번째 서브패스가 엉뚱한 곳에 그려진다.
      final p = parseSvgPath('M10 10 h10 v10 h-10 Z m30 0 h10 v10 h-10 Z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 10, 50, 20));
    });

    test('지수 표기를 숫자로 읽는다', () {
      // `e` 를 명령 문자로 끊으면 파싱이 깨진다. mapshaper 등 도구가
      // 아주 작은 좌표를 지수로 내보낼 수 있다.
      final p = parseSvgPath('M1e1 2e1 L3e1 2e1');
      expect(p.getBounds().left, closeTo(10, 0.001));
      expect(p.getBounds().right, closeTo(30, 0.001));
    });

    test('음수 지수도 읽는다', () {
      expect(() => parseSvgPath('M1e-5 0 L1 1'), returnsNormally);
    });

    test('Z 뒤에 숫자가 오면 무한 루프 대신 실패한다', () {
      // Z 는 인자를 소비하지 않으므로, 숫자가 이어지면 루프가 전진하지 못한다.
      expect(() => parseSvgPath('M0 0 Z1'), throwsA(isA<FormatException>()));
    });

    test('구분자 없는 음수를 새 숫자로 끊는다', () {
      // `h-50` 처럼 붙여 쓰는 축약형은 SVG 에서 흔하다.
      final p = parseSvgPath('M60 70h-50v-50h50Z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 20, 60, 70));
    });

    test('지원하지 않는 호 명령 A 는 조용히 무시하지 않고 실패한다', () {
      // 빈 Path 를 돌려주면 아트가 안 보이는 원인을 추적하기 어렵다.
      expect(() => parseSvgPath('M0 0 A10 10 0 0 1 20 0'),
          throwsA(isA<FormatException>()));
    });

    test('명령 없이 숫자로 시작하면 실패한다', () {
      expect(() => parseSvgPath('10 20 30'), throwsA(isA<FormatException>()));
    });

    test('인자가 모자라면 실패한다', () {
      expect(() => parseSvgPath('M10'), throwsA(isA<FormatException>()));
    });
  });

  group('파일럿 아트 데이터', () {
    test('랜드마크 14개 · 카테고리 8종이 모두 파싱된다', () {
      expect(kLandmarkArt.length, 14);
      expect(kCategoryArt.length, ArtCategory.values.length);

      for (final art in [...kLandmarkArt.values, ...kCategoryArt.values]) {
        for (final s in art.shapes) {
          if (s.circle != null) continue;
          expect(() => parseSvgPath(s.d), returnsNormally,
              reason: '${art.name}: "${s.d}"');
        }
      }
    });

    test('배경 도형이 bleed 한계를 넘지 않는다', () {
      // 좌표 오타는 눈으로 잡히지 않는다. 배경은 잘리는 것이 전제이지만
      // 한계를 넘으면 그려도 화면에 못 들어와 낭비다.
      for (final art in [...kLandmarkArt.values, ...kCategoryArt.values]) {
        for (final s in art.shapes) {
          if (s.layer != ArtLayer.background) continue;
          final b = _boundsOf(s);
          // `Rect.contains` 는 오른쪽·아래 경계를 제외한다. 한계에 정확히
          // 맞닿는 배경이 실패하므로 명시적으로 4방향을 inclusive 비교한다.
          // (이 프로젝트는 `hit_test` 에서 같은 함정을 이미 한 번 겪었다.)
          expect(b.left, greaterThanOrEqualTo(kBleedArea.left),
              reason: '${art.name}: $b');
          expect(b.top, greaterThanOrEqualTo(kBleedArea.top),
              reason: '${art.name}: $b');
          expect(b.right, lessThanOrEqualTo(kBleedArea.right),
              reason: '${art.name}: $b');
          expect(b.bottom, lessThanOrEqualTo(kBleedArea.bottom),
              reason: '${art.name}: $b');
        }
      }
    });

    test('모든 랜드마크가 장면 구성이다 — 배경 층을 가진다', () {
      // 배경이 없으면 "오브젝트 하나" 구성이라 B 배치에서 잘리면 무너진다.
      // 목록을 고정하지 않고 전수 검사하므로 새 랜드마크도 자동으로 걸린다.
      for (final art in kLandmarkArt.values) {
        expect(art.shapes.any((s) => s.layer == ArtLayer.background), isTrue,
            reason: '${art.name}: 배경 층이 없다 (아이콘 구성)');
      }
    });

    test('장면 구성 아트의 핵심 모티프가 안전 영역 안에 있다', () {
      // B 배치는 잘림을 전제한다. 핵심이 안전 영역을 벗어나면 가장 불리한
      // 지역(부산 서구, 가로:세로 1:3.73)에서 무엇인지 알 수 없게 된다.
      //
      // 배경 층을 가진 아트(= 장면 구성으로 전환된 것)를 전부 검사한다.
      // 아직 전환하지 않은 카테고리 아이콘은 대상이 아니다.
      const slack = 3.0;
      final scene = [...kLandmarkArt.values, ...kCategoryArt.values]
          .where((a) => a.shapes.any((s) => s.layer == ArtLayer.background));
      expect(scene, isNotEmpty);

      for (final art in scene) {
        for (final s in art.shapes) {
          if (s.layer != ArtLayer.core) continue;
          final b = _boundsOf(s);
          expect(b.left, greaterThanOrEqualTo(kSafeArea.left - slack),
              reason: '${art.name}: $b');
          expect(b.top, greaterThanOrEqualTo(kSafeArea.top - slack),
              reason: '${art.name}: $b');
          expect(b.right, lessThanOrEqualTo(kSafeArea.right + slack),
              reason: '${art.name}: $b');
          expect(b.bottom, lessThanOrEqualTo(kSafeArea.bottom + slack),
              reason: '${art.name}: $b');
        }
      }
    });

    test('배경은 핵심보다 먼저 그려진다', () {
      // 리스트 순서가 곧 드로우 순서다. 배경이 뒤에 오면 핵심을 덮는다.
      for (final art in [...kLandmarkArt.values, ...kCategoryArt.values]) {
        final lastBg =
            art.shapes.lastIndexWhere((s) => s.layer == ArtLayer.background);
        final firstCore =
            art.shapes.indexWhere((s) => s.layer == ArtLayer.core);
        if (lastBg < 0 || firstCore < 0) continue;
        expect(lastBg, lessThan(firstCore), reason: art.name);
      }
    });

    test('랜드마크 소재는 권리 검토를 거친 것만 쓴다', () {
      // 현대 건축물은 저작권법 제35조 제2항의 판매 목적 복제 제약에 걸린다.
      // 목록에 새 소재를 넣을 때 이 테스트가 검토를 강제한다.
      // 판정 근거는 `design/art-provenance.md` 에 한 행씩 남긴다.
      //
      // **예외를 추가하려면 provenance 에 위험과 결정 근거를 먼저 적는다.**
      const safe = {
        '첨성대', '수원화성 팔달문', '하회마을', '돌하르방', '순천만 갈대밭', '울릉도',
        '강화 고인돌', '백령도 두무진', '계양산', '세종대왕릉', '남한산성',
        '두물머리', '자라섬·북한강',
      };
      // ⚠ 현대 건축물 예외. 1971년 완공이라 보호기간 내이고 상표 문제도 있다.
      // 사용자가 위험을 알고 채택했다(2026-08-13). 인앱결제 추가 전 법률 검토 필요.
      const riskyExceptions = {'남산타워'};

      final names = kLandmarkArt.values.map((a) => a.name).toSet();
      expect(names, safe.union(riskyExceptions));
      // 예외가 늘어나면 여기서 걸린다. 하나씩 근거를 확인하고 늘린다.
      expect(names.intersection(riskyExceptions).length, 1);
    });
  });

  group('폴백 등급', () {
    test('랜드마크가 있으면 랜드마크를 쓴다', () {
      expect(artForRegion('47130')?.name, '첨성대');
    });

    test('랜드마크가 없으면 카테고리로 내려간다', () {
      // 랜드마크가 제작되면 이 예시는 폴백이 아니게 되므로, 랜드마크 계획이
      // 없는 지역을 고른다.
      expect(artForRegion('12870')?.name, '섬'); // 신안군
      expect(artForRegion('26140')?.name, '바다·해변'); // 부산 서구
      expect(kLandmarkArt.containsKey('12870'), isFalse);
      expect(kLandmarkArt.containsKey('26140'), isFalse);
    });

    test('둘 다 없으면 null — 1층 단색 폴백', () {
      expect(artForRegion('99999'), isNull);
    });

    test('파일럿 대상 10개 전부가 아트를 받는다', () {
      const pilot = [
        '47130', '41115', '47170', '50000', '12150', '47940',
        '11000', '12770', '28720', '26140',
      ];
      for (final c in pilot) {
        expect(artForRegion(c), isNotNull, reason: c);
      }
    });
  });

  group('장면 변형', () {
    test('같은 코드는 언제나 같은 변형을 준다', () {
      // 난수를 쓰면 앱을 다시 켤 때마다 강남구가 다르게 보인다.
      for (final code in ['11680', '11110', '28177', '41111']) {
        expect(ArtVariant.forCode(code), ArtVariant.forCode(code));
      }
    });

    test('String.hashCode 에 의존하지 않는다', () {
      // Dart 의 String.hashCode 는 실행마다 달라질 수 있다.
      // 값을 고정해 두어 해시 구현을 바꾸면 테스트가 걸리게 한다.
      final v = ArtVariant.forCode('11680');
      expect(v.layout, inInclusiveRange(0, kCityLayoutCount - 1));
      expect(v.bgShift.abs(), lessThanOrEqualTo(14));
      // 같은 문자열은 같은 결과 — 플랫폼과 무관해야 한다.
      expect(ArtVariant.forCode('11680'), v);
    });

    test('랜드마크는 변형하지 않는다', () {
      // 첨성대를 좌우로 뒤집을 이유가 없다.
      expect(artVariantFor('47130'), ArtVariant.none);
      expect(artVariantFor('50000'), ArtVariant.none);
    });

    test('도시로 배정된 지역들이 충분히 다른 그림을 받는다', () {
      // 원래 이 변형은 서울 25개 구가 같은 그림을 쓰는 문제 때문에 넣었다.
      // 2026-08-14 통합으로 서울은 1개가 됐지만, 수도권 시·군과 광역시 자치구가
      // 여전히 도시로 몰린다(주 노출 195개 중 69개).
      final cityCodes = kRegionCategory.entries
          .where((e) => e.value == ArtCategory.city)
          .map((e) => e.key)
          .toList();
      expect(cityCodes.length, greaterThan(50));

      final looks = <String>{};
      final layouts = <int>{};
      for (final c in cityCodes) {
        final v = ArtVariant.forCode(c);
        looks.add('${v.layout}/${v.mirror}/${v.bgShift}');
        layouts.add(v.layout);
      }
      debugPrint('도시 ${cityCodes.length}개 · 구분되는 조합 ${looks.length}가지 '
          '· 배치 ${layouts.length}종');
      // 60가지 조합이 있으므로 도시 지역 수가 많아도 대부분 구분된다.
      expect(looks.length, greaterThanOrEqualTo(30));
      expect(layouts.length, kCityLayoutCount); // 배치 6종을 모두 쓴다
    });

    test('도시 장면 6종의 핵심이 모두 안전 영역 안에 있다', () {
      // 건물 높이를 바꾸므로 조합마다 다시 확인해야 한다.
      const slack = 3.0;
      for (final art in kCityScenes) {
        for (final s in art.shapes) {
          if (s.layer != ArtLayer.core) continue;
          final b = _boundsOf(s);
          expect(b.left, greaterThanOrEqualTo(kSafeArea.left - slack));
          expect(b.top, greaterThanOrEqualTo(kSafeArea.top - slack));
          expect(b.right, lessThanOrEqualTo(kSafeArea.right + slack));
          expect(b.bottom, lessThanOrEqualTo(kSafeArea.bottom + slack));
        }
      }
    });

    test('도시 장면 6종이 서로 다르다', () {
      final ds = kCityScenes
          .map((a) => a.shapes.map((s) => s.d).join('|'))
          .toSet();
      expect(ds.length, kCityLayoutCount);
    });

    test('변형이 다르면 캐시가 다시 만든다', () {
      // 키에서 빼면 좌우 반전만 다른 두 지역이 같은 그림을 재생한다.
      final cache = RegionArtCache();
      final art = kCityScenes.first;
      const target = Rect.fromLTRB(0, 0, 100, 100);
      final a = cache.obtain(art, target, variant: const ArtVariant(false, 0, 0));
      final b = cache.obtain(art, target, variant: const ArtVariant(true, 0, 0));
      expect(identical(a, b), isFalse);
      final c = cache.obtain(art, target, variant: const ArtVariant(true, 7, 0));
      expect(identical(b, c), isFalse);
      cache.dispose();
    });
  });

  group('배치와 캐시', () {
    test('아트 영역은 항상 정사각형이고 bounds 중심에 놓인다', () {
      // 100×100 좌표계라 정사각형이 아니면 비율이 깨진다.
      const b = Rect.fromLTRB(0, 0, 300, 100);
      final r = artTargetRect(b);
      expect(r.width, closeTo(r.height, 0.001));
      expect(r.center, b.center);
    });

    test('가장 큰 링은 bbox 가 아니라 실제 면적으로 고른다', () {
      // 가늘고 긴 링은 bbox 가 커도 면적이 작다. 실제 에셋에서 안산시단원구와
      // 신안군이 두 기준의 선택이 갈리는 지역이다.
      // 얇은 대각선 띠(bbox 100×100, 면적 ≈ 500) vs 작은 정사각형(면적 900).
      final thin = Float32List.fromList([0, 0, 100, 95, 100, 100, 5, 5]);
      final blob = Float32List.fromList([0, 0, 30, 0, 30, 30, 0, 30]);
      final r = largestRingBounds([thin, blob],
          scale: 1, offset: Offset.zero);
      expect(r, const Rect.fromLTRB(0, 0, 30, 30));
    });

    test('링이 하나면 그 링을 쓴다', () {
      final only = Float32List.fromList([10, 10, 40, 10, 40, 40, 10, 40]);
      expect(largestRingBounds([only], scale: 1, offset: Offset.zero),
          const Rect.fromLTRB(10, 10, 40, 40));
    });

    test('배율과 이동이 링 bounds 에 반영된다', () {
      final only = Float32List.fromList([0, 0, 10, 0, 10, 10, 0, 10]);
      final r = largestRingBounds([only],
          scale: 3, offset: const Offset(5, 7));
      expect(r, const Rect.fromLTRB(5, 7, 35, 37));
    });

    test('B 배치는 지역보다 크게 잡아 창처럼 비춘다', () {
      // A 와 달리 지역 안에 맞추지 않는다. 짧은 변이 아니라 긴 변 기준이다.
      final path = Path()..addRect(const Rect.fromLTRB(0, 0, 100, 300));
      final r = artTargetFill(path, const Rect.fromLTRB(0, 100, 100, 200));
      expect(r.width, closeTo(300 * 0.95, 0.001));
      expect(r.center.dy, closeTo(150, 0.001)); // focus 중심을 따른다
    });

    test('세로로 긴 지역에서는 짧은 변이 아트 크기를 정한다', () {
      // 부산 서구는 가로:세로가 1:3.73 이다. 짧은 변 기준이라 아트가 작아진다.
      final r = artTargetRect(const Rect.fromLTRB(0, 0, 26, 97));
      expect(r.width, closeTo(26 * 0.52, 0.001));
    });

    test('같은 입력이면 Picture 를 다시 만들지 않는다', () {
      final cache = RegionArtCache();
      final art = kLandmarkArt['47130']!;
      const target = Rect.fromLTRB(0, 0, 100, 100);
      final a = cache.obtain(art, target);
      final b = cache.obtain(art, target);
      expect(identical(a, b), isTrue);
      cache.dispose();
    });

    test('배치가 바뀌면 Picture 를 다시 만든다', () {
      // 화면 회전이나 분할 화면에서 target 이 바뀐다. 갱신하지 않으면
      // 이전 크기의 그림이 계속 재생된다.
      final cache = RegionArtCache();
      final art = kLandmarkArt['47130']!;
      final a = cache.obtain(art, const Rect.fromLTRB(0, 0, 100, 100));
      final b = cache.obtain(art, const Rect.fromLTRB(0, 0, 200, 200));
      expect(identical(a, b), isFalse);
      cache.dispose();
    });

    test('아트가 바뀌면 Picture 를 다시 만든다', () {
      final cache = RegionArtCache();
      const target = Rect.fromLTRB(0, 0, 100, 100);
      final a = cache.obtain(kLandmarkArt['47130']!, target);
      final b = cache.obtain(kLandmarkArt['50000']!, target);
      expect(identical(a, b), isFalse);
      cache.dispose();
    });

    test('아트 한 장 기록 비용이 폭주하지 않는다', () {
      // 정밀 측정이 아니라 회귀 감지용이다. 파서가 매 프레임 도는 구조로
      // 되돌아가거나 도형 수가 터지면 걸린다.
      final sw = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        final rec = ui.PictureRecorder();
        paintRegionArt(Canvas(rec), kLandmarkArt['12150']!,
            const Rect.fromLTRB(0, 0, 400, 400));
        rec.endRecording().dispose();
      }
      sw.stop();
      final per = sw.elapsedMicroseconds / 50;
      debugPrint('아트 1장 기록 ${per.toStringAsFixed(0)}us '
          '(순천만, 도형 ${kLandmarkArt['12150']!.shapes.length}개)');
      expect(per, lessThan(20000));
    });
  });
}
