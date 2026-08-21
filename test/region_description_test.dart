import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';
import 'package:mapscratch/region_description.dart';
import 'package:mapscratch/sido_progress.dart';

/// M4 팝업 콘텐츠의 **데이터 쪽** 검증. 화면은 `region_sheet_test.dart` 가 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  group('설명 데이터', () {
    test('랜드마크 32개 전부에 설명이 있다', () {
      final missing = kLandmarkArt.keys
          .where((c) => !kLandmarkDescription.containsKey(c))
          .toList();
      expect(missing, isEmpty);
      expect(kLandmarkDescription.length, kLandmarkArt.length);
    });

    test('설명 키가 전부 실제 긁기 단위다', () {
      final codes = data.regions.map((r) => r.scratchUnitId).toSet();
      expect(kLandmarkDescription.keys.where((c) => !codes.contains(c)),
          isEmpty);
    });

    test('카테고리 8종 전부에 문구가 있다', () {
      for (final c in ArtCategory.values) {
        expect(kCategoryPhrase[c], isNotNull, reason: '$c');
      }
    });

    test('193개 전부가 설명을 받는다 — 빈 문자열로 떨어지지 않는다', () {
      // 하나라도 비면 그 지역은 수집 후에 할 말이 없는 화면이 된다.
      final empty = <String>[];
      for (final r in data.regions) {
        if (descriptionFor(r.scratchUnitId).trim().isEmpty) {
          empty.add('${r.scratchUnitId} ${r.name}');
        }
      }
      expect(empty, isEmpty);
    });

    test('랜드마크가 있으면 카테고리 문구보다 우선한다', () {
      // 경주시는 첨성대 랜드마크가 있고 카테고리는 heritage 다.
      expect(descriptionFor('47130'), kLandmarkDescription['47130']);
      expect(descriptionFor('47130'), isNot(kCategoryPhrase[ArtCategory.heritage]));
    });

    test('랜드마크가 없으면 카테고리 문구로 간다', () {
      final code = data.regions
          .map((r) => r.scratchUnitId)
          .firstWhere((c) => !kLandmarkArt.containsKey(c));
      expect(descriptionFor(code), kCategoryPhrase[kRegionCategory[code]]);
    });

    test('설명에 지역 이름을 그대로 베끼지 않는다', () {
      // 문구가 "경주시입니다" 류로 채워지면 성취 표시가 아니라 통보가 된다.
      // 카테고리 문구 8종에는 지역명이 들어가면 안 된다.
      final names = data.regions.map((r) => r.name).toSet();
      for (final phrase in kCategoryPhrase.values) {
        for (final n in names) {
          expect(phrase.contains(n), isFalse, reason: '$phrase 에 $n');
        }
      }
    });
  });

  group('시도 진행률', () {
    test('아무것도 안 긁었으면 0', () {
      final p = sidoProgressOf(data, const {}, 0);
      expect(p.collected, 0);
      expect(p.ratio, 0);
      expect(p.complete, isFalse);
      expect(p.remaining, p.total);
    });

    test('그 시도의 지역만 센다', () {
      // 경상북도(독도 포함)를 하나 긁어도 다른 시도는 0 이다.
      final gb = data.sidoNames.indexOf('경상북도');
      final p = sidoProgressOf(data, {'DK001'}, gb);
      expect(p.collected, 1);
      expect(p.sidoName, '경상북도');

      for (var i = 0; i < data.sidoNames.length; i++) {
        if (i == gb) continue;
        expect(sidoProgressOf(data, {'DK001'}, i).collected, 0);
      }
    });

    test('통합 단위는 한 번에 1/1 이 된다', () {
      // 시도 전체가 긁기 단위 하나인 곳들이다 — 서울·제주(2026-08-14)와
      // 광역시 넷(2026-08-20). **서울만 보면 광역시 통합이 깨져도 통과한다.**
      const oneToOne = {
        '서울특별시': '11000',
        '제주특별자치도': '50000',
        '부산광역시': '26000',
        '대구광역시': '27000',
        '대전광역시': '30000',
        '울산광역시': '31000',
      };
      for (final e in oneToOne.entries) {
        final i = data.sidoNames.indexOf(e.key);
        final p = sidoProgressOf(data, {e.value}, i);
        expect(p.total, 1, reason: e.key);
        expect(p.collected, 1, reason: e.key);
        expect(p.complete, isTrue, reason: e.key);
        expect(p.remaining, 0, reason: e.key);
      }
    });

    test('인천은 통합해도 1/1 이 아니다', () {
      // **강화군·옹진군을 남긴 예외가 살아 있는지 본다.** 옹진군(백령도)까지
      // 합치면 병합 도형 폭이 전국의 40% 가 되어 지도가 망가진다.
      final i = data.sidoNames.indexOf('인천광역시');
      final p = sidoProgressOf(data, {'28000'}, i);
      expect(p.total, 3);
      expect(p.collected, 1);
      expect(p.complete, isFalse);
      expect(p.remaining, 2);
    });

    test('알 수 없는 ID 는 수치에 끼어들지 않는다', () {
      // 저장에는 남아 있지만 지도에 없는 ID 다(개편·롤백). 진행률을 부풀리면
      // "다 모았다" 가 거짓이 된다 (Codex 20회차).
      final gb = data.sidoNames.indexOf('경상북도');
      final clean = sidoProgressOf(data, {'DK001'}, gb);
      final dirty = sidoProgressOf(data, {'DK001', '99999', 'NOPE'}, gb);

      expect(dirty.collected, clean.collected);
      expect(dirty.total, clean.total);
    });

    test('시도별 합이 193 다', () {
      var sum = 0;
      for (var i = 0; i < data.sidoNames.length; i++) {
        sum += sidoProgressOf(data, const {}, i).total;
      }
      expect(sum, 193);
    });
  });
}
