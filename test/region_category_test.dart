import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';

/// 193개 카테고리 배정 검증.
///
/// 배정 자체는 사람이 정한다 — 지도 에셋에 고도·토지이용·인구 데이터가 없어
/// 산과 들판을 가를 신호가 아예 없기 때문이다(Codex 검토 2026-08-13).
/// 그래서 여기서는 **의미가 아니라 정합성과 모순**을 검사한다.
/// 원본은 `tool/category/make_category_map.py`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  group('정합성', () {
    test('지도 코드와 배정 코드가 정확히 일치한다', () {
      final mapCodes = data.regions.map((r) => r.scratchUnitId).toSet();
      expect(kRegionCategory.keys.toSet(), mapCodes);
    });

    test('193개 전부 배정돼 있다', () {
      // 랜드마크가 있는 지역도 폴백으로 카테고리를 가진다.
      // 랜드마크를 빼거나 바꿔도 아트가 사라지지 않게 하기 위해서다.
      expect(kRegionCategory.length, 193);
    });

    test('생성물이 단일 원본과 일치한다', () {
      // 원본(`tool/category/make_category_map.py`)만 고치고 재생성을 잊으면
      // 앱은 옛 배정을 쓰면서 테스트는 통과한다. 그 구멍을 막는다.
      //
      // **신호 파일도 함께 본다.** 카테고리 생성기는 신호의 코드 집합만
      // 비교하므로, 지역 코드가 그대로인 채 도형만 바뀌면 낡은 `coast` 가
      // 조용히 통과한다 (Codex 30회차 코드 리뷰).
      for (final script in const [
        'tool/category/make_signals.py',
        'tool/category/make_category_map.py',
      ]) {
        final py = Process.runSync(
          'python',
          [script, '--check'],
          workingDirectory: Directory.current.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (py.exitCode == 2) {
          // python 이 없는 환경에서는 건너뛴다. CI 에서는 있어야 한다.
          debugPrint('경고: python 을 찾지 못해 생성물 최신성을 확인하지 못했다');
          return;
        }
        expect(py.exitCode, 0, reason: '$script: ${py.stdout}${py.stderr}');
      }
    }, skip: !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);

    test('병합 검증 로직이 잘못된 병합을 잡는다', () {
      // **앱 테스트는 이미 만들어진 에셋만 본다.** 생성기가 잘못된 병합을
      // 걸러내는지는 파이썬 쪽 반례 테스트만 검사할 수 있다.
      //
      // `verify_merge.py` 는 병합 전 원본과 면적을 대조한다. 코드 집합 검사와
      // 개수 트립와이어로는 **병합 그룹 안에서 구성원이 빠지는 것**을 못 잡기
      // 때문이다 (Codex 30회차 재검토 지적).
      for (final script in const [
        'tool/map/test_merge_spec.py',
        'tool/map/verify_merge.py',
        // **검증기가 무엇을 거부하는지는 거부당하는 입력으로만 확인된다.**
        // 정상 파일에 돌려 0 만 보면 `TOLERANCE` 가 1 이 되어도 통과한다
        // (Codex 30회차 3차 지적).
        'tool/map/test_verify_merge.py',
      ]) {
        final py = Process.runSync(
          'python',
          [script],
          workingDirectory: Directory.current.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (py.exitCode == 2) {
          debugPrint('경고: python 을 찾지 못해 병합 검증을 확인하지 못했다');
          return;
        }
        expect(py.exitCode, 0, reason: '$script: ${py.stdout}${py.stderr}');
      }
    }, skip: !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);

    test('모든 카테고리에 아트가 있다', () {
      for (final c in kRegionCategory.values.toSet()) {
        expect(kCategoryArt[c], isNotNull, reason: '$c');
      }
    });

    test('193개 전부 아트를 받는다 — 단색 폴백으로 떨어지는 지역이 없다', () {
      for (final r in data.regions) {
        expect(artForRegion(r.scratchUnitId), isNotNull, reason: '${r.scratchUnitId} ${r.name}');
      }
    });
  });

  group('모순 탐지', () {
    // 지도 기하로 잡을 수 있는 모순만 본다.
    // "춘천은 도시인가 산인가" 같은 판단은 자동으로 할 수 없다.

    test('내륙인데 바다·섬으로 배정된 지역이 없다', () {
      // 다른 지역과 맞닿지 않는 경계가 거의 없으면 바다에 접하지 않는다.
      // 단 휴전선 접경은 이 신호가 해안처럼 보이므로 반대 방향만 검사한다.
      final bad = <String>[];
      for (final r in data.regions) {
        final cat = kRegionCategory[r.scratchUnitId]!;
        if (cat != ArtCategory.sea && cat != ArtCategory.island) continue;
        if (_unsharedRatio(data, r) < 0.05) bad.add('${r.scratchUnitId} ${r.name} $cat');
      }
      expect(bad, isEmpty);
    });

    test('완전히 둘러싸인 섬은 바다가 아니라 섬으로 배정한다', () {
      // 울릉도가 island 가 아니라 sea 로 가던 초기 규칙 오류를 막는다.
      // 링이 1개여도 사방이 바다면 섬이다.
      final bad = <String>[];
      for (final r in data.regions) {
        if (_unsharedRatio(data, r) < 0.99) continue;
        if (kRegionCategory[r.scratchUnitId] != ArtCategory.island) {
          bad.add('${r.scratchUnitId} ${r.name}');
        }
      }
      expect(bad, isEmpty);
    });

    test('통합 시도가 명세대로 병합돼 있다', () {
      // 2026-08-14 서울·제주, 2026-08-20 광역시 다섯. 병합 명세는
      // `tool/map/merge_spec.py` 이고 mapshaper -dissolve2 가 위상 연산으로
      // 처리한다.
      final byCode = {for (final r in data.regions) r.scratchUnitId: r};
      const merged = {
        '11000': '서울특별시',
        '26000': '부산광역시',
        '27000': '대구광역시',
        '28000': '인천광역시',
        '30000': '대전광역시',
        '31000': '울산광역시',
        '50000': '제주특별자치도',
      };
      for (final e in merged.entries) {
        final r = byCode[e.key];
        expect(r, isNotNull, reason: '${e.value} 통합 코드 ${e.key} 가 없다');
        expect(r!.name, e.value);
      }

      // **`rings.length == 1` 을 모두에게 요구하면 안 된다.** 부산에는 가덕도,
      // 인천에는 영종도, 제주에는 부속섬이 있어 링이 여럿이다. 내부 구 경계가
      // 남았는지는 서울처럼 부속섬이 없는 곳에서만 링 수로 볼 수 있다.
      expect(byCode['11000']!.rings.length, 1, reason: '서울 내부 경계가 남았다');
      expect(byCode['27000']!.rings.length, 1, reason: '대구 내부 경계가 남았다');
      expect(byCode['30000']!.rings.length, 1, reason: '대전 내부 경계가 남았다');
      expect(byCode['31000']!.rings.length, 1, reason: '울산 내부 경계가 남았다');

      // 흡수된 옛 코드가 남아 있으면 안 된다.
      //
      // **인천은 강화군·옹진군이 살아 있어야 한다.** 그래서 접두사로 싸잡아
      // 지우지 않고 잔류 목록을 따로 둔다.
      const survivors = {'28710', '28720'};
      final leftovers = data.regions
          .map((r) => r.scratchUnitId)
          .where((c) =>
              !merged.containsKey(c) &&
              !survivors.contains(c) &&
              const ['11', '26', '27', '28', '30', '31', '50']
                  .any(c.startsWith))
          .toList();
      expect(leftovers, isEmpty, reason: '흡수됐어야 할 옛 코드가 남았다');
    });

    test('통합 시도의 단위 수가 명세와 같다', () {
      // 전체 193 이 맞아도 **시도별 분포가 틀릴 수 있다** (Codex 30회차).
      // 인천 3 은 강화군·옹진군을 남긴 예외이고, 그것이 계약이다.
      final count = <String, int>{};
      for (final r in data.regions) {
        final sido = data.sidoNames[r.sido];
        count[sido] = (count[sido] ?? 0) + 1;
      }
      expect(count['서울특별시'], 1);
      expect(count['부산광역시'], 1);
      expect(count['대구광역시'], 1);
      expect(count['인천광역시'], 3, reason: '강화군·옹진군이 남아야 한다');
      expect(count['대전광역시'], 1);
      expect(count['울산광역시'], 1);
      expect(count['제주특별자치도'], 1);
      expect(count['세종특별자치시'], 1);
    });

    test('옛 서울 구 위치를 찍으면 통합 서울로 판정된다', () {
      // 병합이 기하적으로 온전한지 보는 검사다. 구멍이 남으면 여기서 걸린다.
      final seoul = data.regions.firstWhere((r) => r.scratchUnitId == '11000');
      final b = seoul.bounds;
      var inside = 0;
      for (var i = 1; i < 10; i++) {
        for (var j = 1; j < 10; j++) {
          final p = Offset(
            b.left + b.width * i / 10,
            b.top + b.height * j / 10,
          );
          if (seoul.path.contains(p)) inside++;
        }
      }
      // 서울 bounds 대비 육지 비율이 54% 라 격자 81점 중 상당수가 내부여야 한다.
      debugPrint('서울 격자 81점 중 내부 $inside점');
      expect(inside, greaterThan(30));
    });

    test('제작된 랜드마크가 계획 목록과 정확히 일치한다', () {
      // 계획에 없는 지역에 랜드마크를 만들면 분포 계산이 어긋나고,
      // 계획에 있는데 안 만들면 그 지역은 카테고리로 폴백한다.
      final made = kLandmarkArt.keys.toSet();
      expect(made.difference(kPlannedLandmarks), isEmpty,
          reason: '계획에 없는 랜드마크');
      expect(kPlannedLandmarks.difference(made), isEmpty,
          reason: '아직 만들지 않은 랜드마크');
    });

    test('계획된 랜드마크 코드가 모두 지도에 있다', () {
      final mapCodes = data.regions.map((r) => r.scratchUnitId).toSet();
      expect(kPlannedLandmarks.difference(mapCodes), isEmpty);
      expect(kPlannedLandmarks.length, 32);
    });
  });

  group('분포 — 경고만 한다', () {
    // **분포를 실패 조건으로 두지 않는다.** 의미가 맞는 배정을 분포를 맞추려고
    // 바꾸게 되면 배정 품질이 떨어진다 (Codex 검토 2026-08-13).
    // 대신 수치를 찍어 두고 사람이 보게 한다.

    test('주 노출 161개 기준 분포를 보고한다', () {
      // 계획된 랜드마크 32개는 카테고리를 폴백으로만 쓰므로 빼고 센다.
      // 제작 진행도와 무관하게 최종 상태 기준으로 본다.
      final counts = <ArtCategory, int>{};
      for (final r in data.regions) {
        if (kPlannedLandmarks.contains(r.scratchUnitId)) continue;
        counts[kRegionCategory[r.scratchUnitId]!] =
            (counts[kRegionCategory[r.scratchUnitId]!] ?? 0) + 1;
      }
      final total = counts.values.reduce((a, b) => a + b);
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      debugPrint('주 노출 $total개');
      for (final e in sorted) {
        debugPrint('  ${e.key.name.padRight(10)} ${e.value}개 '
            '(${(e.value / total * 100).toStringAsFixed(1)}%)');
      }
      expect(total, 161); // 193 − 랜드마크 32
    });

    test('쓰이지 않는 카테고리를 보고한다', () {
      final used = kRegionCategory.values.toSet();
      final unused =
          ArtCategory.values.where((c) => !used.contains(c)).toList();
      if (unused.isNotEmpty) {
        debugPrint('경고: 아트를 만들었으나 쓰이지 않는 카테고리 $unused');
      }
      // 실패시키지 않는다 — 배정이 옳다면 안 쓰는 종이 생겨도 정상이다.
    });

    test('한 시도가 한 카테고리로만 채워지면 보고한다', () {
      final bySido = <int, Set<ArtCategory>>{};
      final count = <int, int>{};
      for (final r in data.regions) {
        bySido.putIfAbsent(r.sido, () => {}).add(kRegionCategory[r.scratchUnitId]!);
        count[r.sido] = (count[r.sido] ?? 0) + 1;
      }
      for (final e in bySido.entries) {
        if ((count[e.key] ?? 0) < 5) continue;
        if (e.value.length == 1) {
          debugPrint('경고: ${data.sidoNames[e.key]} 가 ${e.value.first} 하나뿐이다');
        }
      }
    });
  });
}

/// 다른 지역과 맞닿지 않는 경계 정점의 비율.
///
/// **해안 비율이 아니다.** 휴전선 접경도 여기 잡힌다 — 북한 쪽 인접 지역이
/// 데이터에 없기 때문이다. 그래서 "내륙인데 바다" 만 잡고 반대는 잡지 않는다.
double _unsharedRatio(MapData data, Region region) {
  const cell = 0.6;
  const eps2 = 0.35 * 0.35;
  _grid ??= _buildGrid(data, cell);
  var total = 0, free = 0;
  for (final ring in region.rings) {
    for (var i = 0; i < ring.length; i += 2) {
      final x = ring[i], y = ring[i + 1];
      total++;
      var near = false;
      final gx = (x / cell).floor(), gy = (y / cell).floor();
      for (var a = -1; a <= 1 && !near; a++) {
        for (var b = -1; b <= 1 && !near; b++) {
          for (final p in _grid![(gx + a) * 100000 + (gy + b)] ?? const []) {
            if (p.$3 == region.scratchUnitId) continue;
            final dx = p.$1 - x, dy = p.$2 - y;
            if (dx * dx + dy * dy < eps2) {
              near = true;
              break;
            }
          }
        }
      }
      if (!near) free++;
    }
  }
  return total == 0 ? 0 : free / total;
}

Map<int, List<(double, double, String)>>? _grid;

Map<int, List<(double, double, String)>> _buildGrid(MapData data, double cell) {
  final g = <int, List<(double, double, String)>>{};
  for (final r in data.regions) {
    for (final ring in r.rings) {
      for (var i = 0; i < ring.length; i += 2) {
        final x = ring[i], y = ring[i + 1];
        final key = (x / cell).floor() * 100000 + (y / cell).floor();
        g.putIfAbsent(key, () => []).add((x, y, r.scratchUnitId));
      }
    }
  }
  return g;
}
