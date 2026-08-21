import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_search.dart';

/// M3 지역 검색. **순수 로직이라 실제 에셋 193개로 직접 검사한다.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RegionSearcher searcher;
  setUpAll(() async => searcher = RegionSearcher(await MapData.load()));

  List<String> names(String q) =>
      searcher.search(q).map((r) => r.region.name).toList();

  group('초성 추출', () {
    test('완성형 음절을 초성으로 바꾼다', () {
      expect(choseongOf('순천시'), 'ㅅㅊㅅ');
      expect(choseongOf('서울특별시'), 'ㅅㅇㅌㅂㅅ');
      expect(choseongOf('독도'), 'ㄷㄷ');
    });

    test('쌍자음 초성도 제자리에 온다', () {
      expect(choseongOf('꽃'), 'ㄲ');
      expect(choseongOf('땅'), 'ㄸ');
    });

    test('초성 19자를 각각 제자리로 뽑는다', () {
      // 전수 검사가 `choseongOf` 로 질의도 만들기 때문에, 그것만으로는
      // 이 함수가 옳다는 증거가 되지 않는다. 고정 기대값을 따로 둔다
      // (Codex 18회차).
      const samples = {
        '가': 'ㄱ', '까': 'ㄲ', '나': 'ㄴ', '다': 'ㄷ', '따': 'ㄸ',
        '라': 'ㄹ', '마': 'ㅁ', '바': 'ㅂ', '빠': 'ㅃ', '사': 'ㅅ',
        '싸': 'ㅆ', '아': 'ㅇ', '자': 'ㅈ', '짜': 'ㅉ', '차': 'ㅊ',
        '카': 'ㅋ', '타': 'ㅌ', '파': 'ㅍ', '하': 'ㅎ',
      };
      samples.forEach((syllable, cho) {
        expect(choseongOf(syllable), cho, reason: syllable);
      });
      expect(samples.values.toSet().length, 19);
    });

    test('한글이 아닌 문자는 그대로 둔다', () {
      expect(choseongOf('DK001'), 'DK001');
      expect(choseongOf('제주 A'), 'ㅈㅈ A');
    });

    test('자음과 모음이 떨어진 상태를 가려낸다', () {
      // IME 조합이 끊기면 `ㅅㅓ` 처럼 남는다. 무엇을 쳐도 0건이 되므로
      // 화면이 다른 안내를 띄워야 한다 (2026-08-15 실기기에서 재현).
      expect(hasLooseJamo('ㅅㅓ'), isTrue);
      expect(hasLooseJamo('ㅅㅓ서'), isTrue);
      expect(hasLooseJamo('부산 ㅅㅓ'), isTrue);

      // 순수 초성은 정상 질의다.
      expect(hasLooseJamo('ㅅㅊ'), isFalse);
      expect(hasLooseJamo('ㄱ'), isFalse);
      // 완성형만 있는 질의도 정상이다.
      expect(hasLooseJamo('서구'), isFalse);
      expect(hasLooseJamo('부산 중구'), isFalse);
      expect(hasLooseJamo(''), isFalse);
    });

    test('떨어진 자모 질의는 실제로 0건이다', () {
      expect(searcher.search('ㅅㅓ'), isEmpty);
    });

    test('초성 질의인지 가려낸다', () {
      expect(isChoseongQuery('ㅅㅊ'), isTrue);
      expect(isChoseongQuery('ㄱㄴㄷ'), isTrue);
      // `서` 는 초성이 아니라 이미 글자다.
      expect(isChoseongQuery('서'), isFalse);
      expect(isChoseongQuery('ㅅ천'), isFalse);
      expect(isChoseongQuery(''), isFalse);
    });
  });

  group('초성 검색', () {
    test('ㅅㅊ 로 순천시를 찾는다', () {
      expect(names('ㅅㅊ'), contains('순천시'));
    });

    test('ㄷㄷ 로 독도를 찾는다', () {
      expect(names('ㄷㄷ'), contains('독도'));
    });

    test('초성이 이름 중간에 걸려도 찾는다', () {
      // 고양시일산동구 → ㄱㅇㅅㅇㅅㄷㄱ. `ㅇㅅㄷ` 는 중간이다.
      expect(names('ㅇㅅㄷ'), contains('고양시일산동구'));
    });

    test('시도 초성으로도 찾는다', () {
      final r = searcher.search('ㅂㅅㄱㅇㅅ'); // 부산광역시
      expect(r, isNotEmpty);
      expect(r.every((e) => e.sidoName == '부산광역시'), isTrue);
    });
  });

  group('이름 검색', () {
    test('앞에서 시작하는 쪽이 먼저 나온다', () {
      final r = searcher.search('경주');
      expect(r.first.region.name, '경주시');
    });

    test('이름 중간에 들어 있어도 찾는다', () {
      expect(names('일산'), contains('고양시일산동구'));
    });

    test('한 이름을 띄어 써도 찾는다', () {
      expect(names('고양시 일산동구'), contains('고양시일산동구'));
    });

    test('시도명과 지역명을 함께 쳐서 동명을 좁힌다', () {
      // `고성군` 만 치면 두 곳이 나온다. 이게 안 되면 사용자는 목록을 눈으로
      // 훑어야 한다 (Codex 18회차).
      //
      // **예전에는 `부산 중구` 로 검사했다.** 2026-08-20 광역시 통합으로 `중구`
      // 여섯 곳이 통째로 사라져 동명이 `고성군` 하나만 남았다.
      final r = searcher.search('경상남도 고성군');
      expect(r.length, 1);
      expect(r.single.region.name, '고성군');
      expect(r.single.sidoName, '경상남도');
    });

    test('시도명을 줄여 써도 좁혀진다', () {
      final r = searcher.search('강원 고성군');
      expect(r.length, 1);
      expect(r.single.sidoName, '강원특별자치도');
    });

    test('초성으로도 좁힐 수 있다', () {
      final r = searcher.search('ㄱㅇ ㄱㅅㄱ');
      expect(r.map((e) => e.region.name), contains('고성군'));
      expect(r.single.sidoName, '강원특별자치도');
    });

    test('초성 잡음은 순위로 뒤에 선다', () {
      // **초성 복합 질의는 잡음이 섞인다.** 긴 시도명의 초성열에는 짧은 토막이
      // 우연히 들어가기 때문이다 — `전남광주통합특별시`(ㅈㄴㄱㅈㅌㅎㅌㅂㅅ)에
      // 태백시의 `ㅌㅂㅅ` 가 들어 있어 걸린다. 규칙상 맞는 결과이므로 없애지
      // 않고 **뒤로 밀리는 것**만 보장한다.
      //
      // **조건문으로 감싸면 안 된다.** 예전에는 `if (firstOther >= 0)` 안에
      // 두었는데, 2026-08-20 광역시 통합으로 그 질의의 결과가 1개가 되면서
      // 이 계약이 **한 번도 검사되지 않게 됐다**(Codex 30회차). 잡음이 실제로
      // 생기는 질의를 골라 조건 없이 단언한다.
      final r = searcher.search('ㄱㅇ ㅌㅂㅅ');
      expect(r.length, greaterThan(1), reason: '잡음이 사라지면 이 테스트는 뜻이 없다');
      expect(r.first.sidoName, '강원특별자치도');
      final firstOther = r.indexWhere((e) => e.sidoName != '강원특별자치도');
      expect(firstOther, greaterThan(0));
      expect(r[firstOther].rank, greaterThan(r.first.rank));
    });

    test('토막 하나라도 안 맞으면 결과가 없다', () {
      expect(searcher.search('강원 경주시'), isEmpty);
    });

    test('시도명으로 그 시도의 지역들을 찾는다', () {
      final r = searcher.search('울산광역시');
      expect(r, isNotEmpty);
      expect(r.every((e) => e.sidoName == '울산광역시'), isTrue);
    });

    test('이름 일치가 시도 일치보다 먼저다', () {
      // `제주특별자치도` 는 통합 긁기 단위의 이름이자 시도명이다.
      final r = searcher.search('제주');
      expect(r.first.region.name, '제주특별자치도');
    });

    test('빈 질의와 공백만은 결과가 없다', () {
      expect(searcher.search(''), isEmpty);
      expect(searcher.search('   '), isEmpty);
    });

    test('없는 이름은 결과가 없다', () {
      expect(searcher.search('없는지역이름'), isEmpty);
    });
  });

  group('동명 지역', () {
    test('이름이 겹치는 곳은 고성군 하나뿐이다', () {
      // 시도명을 함께 보여주지 않으면 어느 곳인지 알 수 없다.
      //
      // **2026-08-20 광역시 통합으로 여섯에서 하나로 줄었다.** 겹치던 중구·서구·
      // 동구·남구·북구가 전부 광역시 안에 있었기 때문이다. 통합의 부수 효과라
      // 목표는 아니었지만 검색이 눈에 띄게 쉬워졌으므로 계약으로 남긴다.
      expect(searcher.ambiguousNames, {'고성군'});
    });

    test('고성군을 찾으면 전부 ambiguous 로 표시된다', () {
      final r = searcher.search('고성군');
      expect(r.length, greaterThan(1));
      expect(r.every((e) => e.ambiguousName), isTrue);
      // 시도명이 서로 달라야 구분이 된다.
      expect(r.map((e) => e.sidoName).toSet().length, r.length);
    });

    test('겹치지 않는 이름은 ambiguous 가 아니다', () {
      expect(searcher.search('경주시').single.ambiguousName, isFalse);
    });
  });

  group('결과 개수', () {
    test('많이 걸려도 자르지 않는다', () {
      // 예전에는 30개에서 조용히 끊었다. 그러면 사용자는 찾는 곳이 없는 것인지
      // 잘린 것인지 알 수 없다 (2026-08-15 사용자 결정으로 상한을 없앴다).
      expect(searcher.search('시').length, greaterThan(100));
      // 상한(30)의 몇 배인지가 요점이라 통합 뒤 값에 맞춰 낮췄다.
      expect(searcher.search('ㄱ').length, greaterThan(140));
    });

    test('좁히라고 안내할 기준이 있다', () {
      // 화면이 이 값으로 안내를 켠다.
      expect(searcher.search('시').length,
          greaterThan(RegionSearcher.crowded));
      expect(searcher.search('경주시').length,
          lessThanOrEqualTo(RegionSearcher.crowded));
    });

    test('193개 전부 자기 이름으로 찾힌다', () {
      final missing = <String>[];
      for (final r in searcher.data.regions) {
        final hit = searcher
            .search(r.name)
            .any((e) => e.region.scratchUnitId == r.scratchUnitId);
        if (!hit) missing.add('${r.scratchUnitId} ${r.name}');
      }
      expect(missing, isEmpty);
    });

    test('193개 전부 자기 초성으로 찾힌다', () {
      final missing = <String>[];
      for (final r in searcher.data.regions) {
        final hit = searcher
            .search(choseongOf(r.name))
            .any((e) => e.region.scratchUnitId == r.scratchUnitId);
        if (!hit) missing.add('${r.scratchUnitId} ${r.name}');
      }
      expect(missing, isEmpty);
    });
  });
}
