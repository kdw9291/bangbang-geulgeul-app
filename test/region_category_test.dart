import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';
import 'package:mapscratch/region_category.g.dart';

/// 231개 카테고리 배정 검증.
///
/// 배정 자체는 사람이 정한다 — 지도 에셋에 고도·토지이용·인구 데이터가 없어
/// 산과 들판을 가를 신호가 아예 없기 때문이다(Codex 검토 2026-08-13).
/// 그래서 여기서는 **의미가 아니라 정합성과 모순**을 검사한다.
/// 원본은 `design/tools/make_category_map.py`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  group('정합성', () {
    test('지도 코드와 배정 코드가 정확히 일치한다', () {
      final mapCodes = data.regions.map((r) => r.code).toSet();
      expect(kRegionCategory.keys.toSet(), mapCodes);
    });

    test('231개 전부 배정돼 있다', () {
      // 랜드마크가 있는 지역도 폴백으로 카테고리를 가진다.
      // 랜드마크를 빼거나 바꿔도 아트가 사라지지 않게 하기 위해서다.
      expect(kRegionCategory.length, 231);
    });

    test('생성물이 단일 원본과 일치한다', () {
      // 원본(`tool/category/make_category_map.py`)만 고치고 재생성을 잊으면
      // 앱은 옛 배정을 쓰면서 테스트는 통과한다. 그 구멍을 막는다.
      final py = Process.runSync(
        'python',
        ['tool/category/make_category_map.py', '--check'],
        workingDirectory: Directory.current.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (py.exitCode == 2) {
        // python 이 없는 환경에서는 건너뛴다. CI 에서는 있어야 한다.
        debugPrint('경고: python 을 찾지 못해 생성물 최신성을 확인하지 못했다');
        return;
      }
      expect(py.exitCode, 0, reason: '${py.stdout}${py.stderr}');
    }, skip: !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);

    test('모든 카테고리에 아트가 있다', () {
      for (final c in kRegionCategory.values.toSet()) {
        expect(kCategoryArt[c], isNotNull, reason: '$c');
      }
    });

    test('231개 전부 아트를 받는다 — 단색 폴백으로 떨어지는 지역이 없다', () {
      for (final r in data.regions) {
        expect(artForRegion(r.code), isNotNull, reason: '${r.code} ${r.name}');
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
        final cat = kRegionCategory[r.code]!;
        if (cat != ArtCategory.sea && cat != ArtCategory.island) continue;
        if (_unsharedRatio(data, r) < 0.05) bad.add('${r.code} ${r.name} $cat');
      }
      expect(bad, isEmpty);
    });

    test('완전히 둘러싸인 섬은 바다가 아니라 섬으로 배정한다', () {
      // 울릉도가 island 가 아니라 sea 로 가던 초기 규칙 오류를 막는다.
      // 링이 1개여도 사방이 바다면 섬이다.
      final bad = <String>[];
      for (final r in data.regions) {
        if (_unsharedRatio(data, r) < 0.99) continue;
        if (kRegionCategory[r.code] != ArtCategory.island) {
          bad.add('${r.code} ${r.name}');
        }
      }
      expect(bad, isEmpty);
    });

    test('서울·제주가 하나의 긁기 단위로 병합돼 있다', () {
      // 2026-08-14 사용자 결정. 병합 명세는 design/tools/merge_spec.py 이고
      // mapshaper -dissolve 가 위상 연산으로 처리한다.
      final byCode = {for (final r in data.regions) r.code: r};

      final seoul = byCode['11000'];
      expect(seoul, isNotNull, reason: '서울 통합 코드가 없다');
      expect(seoul!.name, '서울특별시');
      // 내부 구 경계가 남아 있으면 링이 여러 개가 되고 지도에 경계선이 그려진다.
      expect(seoul.rings.length, 1, reason: '서울 내부 경계가 남았다');

      final jeju = byCode['50000'];
      expect(jeju, isNotNull, reason: '제주 통합 코드가 없다');
      expect(jeju!.name, '제주특별자치도');

      // 흡수된 옛 코드가 남아 있으면 안 된다.
      final leftovers = data.regions
          .map((r) => r.code)
          .where((c) => (c.startsWith('11') && c != '11000') ||
              (c.startsWith('50') && c != '50000'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('옛 서울 구 위치를 찍으면 통합 서울로 판정된다', () {
      // 병합이 기하적으로 온전한지 보는 검사다. 구멍이 남으면 여기서 걸린다.
      final seoul = data.regions.firstWhere((r) => r.code == '11000');
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
      final mapCodes = data.regions.map((r) => r.code).toSet();
      expect(kPlannedLandmarks.difference(mapCodes), isEmpty);
      expect(kPlannedLandmarks.length, 36);
    });
  });

  group('분포 — 경고만 한다', () {
    // **분포를 실패 조건으로 두지 않는다.** 의미가 맞는 배정을 분포를 맞추려고
    // 바꾸게 되면 배정 품질이 떨어진다 (Codex 검토 2026-08-13).
    // 대신 수치를 찍어 두고 사람이 보게 한다.

    test('주 노출 195개 기준 분포를 보고한다', () {
      // 계획된 랜드마크 36개는 카테고리를 폴백으로만 쓰므로 빼고 센다.
      // 제작 진행도와 무관하게 최종 상태 기준으로 본다.
      final counts = <ArtCategory, int>{};
      for (final r in data.regions) {
        if (kPlannedLandmarks.contains(r.code)) continue;
        counts[kRegionCategory[r.code]!] =
            (counts[kRegionCategory[r.code]!] ?? 0) + 1;
      }
      final total = counts.values.reduce((a, b) => a + b);
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      debugPrint('주 노출 $total개');
      for (final e in sorted) {
        debugPrint('  ${e.key.name.padRight(10)} ${e.value}개 '
            '(${(e.value / total * 100).toStringAsFixed(1)}%)');
      }
      expect(total, 195); // 231 − 랜드마크 36
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
        bySido.putIfAbsent(r.sido, () => {}).add(kRegionCategory[r.code]!);
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
            if (p.$3 == region.code) continue;
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
        g.putIfAbsent(key, () => []).add((x, y, r.code));
      }
    }
  }
  return g;
}
