import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/achievement.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/sido_progress.dart';

/// M7 달성 메달과 요약의 **순수 로직**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  group('메달 구성', () {
    test('현재 데이터에서 20·50·100·150·193 가 된다', () {
      // 사용자 결정(2026-08-18). 마지막은 숫자가 아니라 **전국 완주**이므로
      // 상수로 박지 않고 카탈로그 크기에서 나온다 — 그 해석 결과를 못박는다.
      final m = MedalSet.of(data);
      expect(m.medals.map((e) => e.threshold).toList(), [20, 50, 100, 150, 193]);
      expect(m.medals.last.nationwide, isTrue);
      expect(m.total, data.regions.length);
    });

    test('총 개수가 바뀌어도 마지막은 전국 완주다', () {
      // 행정구역 개편으로 193 가 바뀌는 상황. 193 를 하드코딩했다면 여기서 깨진다.
      final m = MedalSet.forTotal(240);
      expect(m.medals.last.threshold, 240);
      expect(m.medals.map((e) => e.threshold).toList(),
          [20, 50, 100, 150, 240]);
    });

    test('총 개수가 임계치보다 작으면 그 메달을 만들지 않는다', () {
      // 임계치가 총 개수를 넘으면 영원히 못 받는 메달이 목록에 남는다.
      final m = MedalSet.forTotal(60);
      expect(m.medals.map((e) => e.threshold).toList(), [20, 50, 60]);
      expect(m.medals.last.nationwide, isTrue);
    });

    test('총 개수가 고정 임계치와 같으면 완주 메달로 합친다', () {
      // **정책이다.** 총 개수가 정확히 150 이면 `150곳` 과 `전국 완주` 가 같은
      // 값이 되어 같은 순간에 둘이 열린다. 하나로 합쳐 4개만 만든다
      // (Codex 25회차가 경계 정책이 불명확하다고 지적한 부분).
      final m = MedalSet.forTotal(150);
      expect(m.medals.map((e) => e.threshold).toList(), [20, 50, 100, 150]);
      expect(m.medals.last.nationwide, isTrue,
          reason: '마지막은 완주 메달이어야 한다');
      expect(m.medals.where((e) => e.threshold == 150).length, 1,
          reason: '같은 임계치 메달이 둘이면 화면에 같은 칩이 두 번 나온다');
    });

    test('메달 id 에 임계치 숫자를 쓰지 않는다', () {
      // 전국 완주의 id 가 `count232` 면 개편 때 id 가 흔들린다.
      expect(MedalSet.forTotal(193).medals.last.id, 'nationwide');
      expect(MedalSet.forTotal(240).medals.last.id, 'nationwide');
    });
  });

  group('획득 판정 경계값', () {
    final m = MedalSet.forTotal(193);
    Medal at(int t) => m.medals.firstWhere((e) => e.threshold == t);

    test('임계치 직전에는 못 받고 임계치에서 받는다', () {
      for (final t in [20, 50, 100, 150]) {
        expect(m.achieved(at(t), t - 1), isFalse, reason: '$t 직전에 받았다');
        expect(m.achieved(at(t), t), isTrue, reason: '$t 에서 못 받았다');
        expect(m.achieved(at(t), t + 1), isTrue);
      }
    });

    test('전국 완주는 192 에서 못 받고 193 에서 받는다', () {
      final nation = m.medals.last;
      expect(m.achieved(nation, 192), isFalse);
      expect(m.achieved(nation, 193), isTrue);
    });

    test('전국 완주는 총 개수를 넘겨도 받지 않는다', () {
      // **`>=` 로 두면 안 된다.** 모집단을 잘못 세어 194 가 나오면 그 버그가
      // "완주" 로 보여 가려진다 — M6 갤러리에서 실제로 겪은 유형이다.
      expect(m.achieved(m.medals.last, 194), isFalse);
    });

    test('0 곳이면 하나도 못 받는다', () {
      expect(m.achievedCount(0), 0);
      expect(m.nextAfter(0)!.threshold, 20);
    });

    test('다 받으면 다음 메달이 null 이다', () {
      // `remaining = 0` 을 돌려주면 화면이 "0곳 남았어요" 라고 쓴다.
      expect(m.achievedCount(193), 5);
      expect(m.nextAfter(193), isNull);
    });

    test('다음 메달은 아직 못 받은 첫 번째다', () {
      expect(m.nextAfter(19)!.threshold, 20);
      expect(m.nextAfter(20)!.threshold, 50);
      expect(m.nextAfter(151)!.threshold, 193);
    });
  });

  group('요약 모집단', () {
    test('전체와 시도 합계가 193 로 맞는다', () {
      final s = collectionSummaryOf(data, const {});
      expect(s.total, 193);
      expect(s.sidos.length, 16);
      expect(s.sidos.fold<int>(0, (a, b) => a + b.total), 193);
      expect(s.collected, 0);
    });

    test('알 수 없는 ID 는 세지 않는다', () {
      // **`CollectionSnapshot.length` 를 쓰면 194/193 이 된다**(M1 계약 —
      // 저장은 보존하되 표시·달성률에서 제외).
      final snap = CollectionSnapshot.empty.collect(CollectedUnit(
        scratchUnitId: '99999',
        collectedAtUtc: DateTime.utc(2026, 8, 15),
        utcOffsetMinutes: 540,
      ));
      expect(snap.length, 1, reason: '저장에는 남아 있어야 한다');

      // **걸러지지 않은 집합을 그대로 넣는다.** `idsIn` 으로 미리 거르면
      // 요약이 스스로 카탈로그를 훑는지 검증하지 못한다 — 앱은 M1 의
      // `_scratched` 파생과 요약의 카탈로그 순회 **두 겹**으로 막고 있어서,
      // 한쪽만 검사하면 다른 쪽을 깨뜨려도 통과한다.
      final raw = {'99999', '47130'};
      final s = collectionSummaryOf(data, raw);
      expect(s.collected, 1, reason: '알 수 없는 ID 가 달성률에 섞였다');
      expect(MedalSet.of(data).achievedCount(s.collected), 0);

      // 걸러 넣은 경로도 같은 결과여야 한다.
      final filtered =
          snap.idsIn(data.regions.map((r) => r.scratchUnitId));
      expect(collectionSummaryOf(data, filtered).collected, 0);
    });

    test('시도 순서가 데이터 순서와 같다', () {
      // 달성률로 재정렬하면 긁을 때마다 행이 움직인다.
      final s = collectionSummaryOf(data, const {});
      expect(s.sidos.map((e) => e.sidoName).toList(), data.sidoNames);
    });

    test('sidoProgressOf 와 결과가 어긋나지 않는다', () {
      // 모집단 규칙이 두 곳으로 갈라지는 것이 진짜 위험이다(Codex 25회차).
      final scratched = {'47130', '11000', '50000', '36110'};
      final s = collectionSummaryOf(data, scratched);
      for (var i = 0; i < data.sidoNames.length; i++) {
        final one = sidoProgressOf(data, scratched, i);
        expect(s.sidos[i].collected, one.collected, reason: one.sidoName);
        expect(s.sidos[i].total, one.total, reason: one.sidoName);
      }
    });
  });

  group('1/1 시도', () {
    test('광역시 통합으로 일곱 곳이 됐다', () {
      // 문서에 "서울·제주·독도" 로 적혀 있었으나 **독도는 경상북도 24곳 중
      // 하나**라 1/1 이 아니고, 세종이 빠져 있었다. 기존 테스트도 서울만 봤다.
      final s = collectionSummaryOf(data, const {});
      final ones =
          s.sidos.where((e) => e.total == 1).map((e) => e.sidoName).toSet();
      expect(ones, {
        '서울특별시', '세종특별자치시', '제주특별자치도',
        '부산광역시', '대구광역시', '대전광역시', '울산광역시',
      });
      // **인천은 강화군·옹진군이 남아 3곳**이라 여기 들어오지 않는다.
      // 그 예외가 살아 있는지 함께 본다.
      expect(s.sidos.firstWhere((e) => e.sidoName == '인천광역시').total, 3,
          reason: '인천은 강화군·옹진군이 통합에서 빠져 3곳이어야 한다');
    });

    test('독도는 경상북도에 들어가 1/1 을 만들지 않는다', () {
      final s = collectionSummaryOf(data, const {'DK001'});
      final gb = s.sidos.firstWhere((e) => e.sidoName == '경상북도');
      expect(gb.total, 24);
      expect(gb.collected, 1);
      expect(gb.complete, isFalse);
    });
  });
}
