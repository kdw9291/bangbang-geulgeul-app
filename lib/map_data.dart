import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

import 'geometry.dart';

/// 시도 색. 참조 실물 맵의 권역 논리를 따른다
/// (수도권 자주 · 강원 주황 · 충청 보라 · 전라 초록 · 경상 파랑 · 제주 연두).
/// 순서는 에셋의 `sidos` 배열과 반드시 일치해야 한다.
const List<Color> kSidoColors = [
  Color(0xFFE0457B), // 서울
  Color(0xFFB03268), // 인천
  Color(0xFFF0809F), // 경기
  Color(0xFFE8833A), // 강원
  Color(0xFF8B6FD4), // 충북
  Color(0xFFA98BE0), // 충남
  Color(0xFF6B4FB8), // 대전
  Color(0xFFC3B2EE), // 세종
  Color(0xFF52A96C), // 전북
  Color(0xFF2E8F55), // 전남광주
  Color(0xFF4A90D9), // 경북
  Color(0xFF2C6DB5), // 대구
  Color(0xFF74B2E8), // 경남
  Color(0xFF1D5A9C), // 부산
  Color(0xFF3F86C9), // 울산
  Color(0xFFAFC63C), // 제주
];

class Region {
  Region({
    required this.scratchUnitId,
    required this.name,
    required this.sido,
    required this.path,
    required this.bounds,
    required this.rings,
  });

  /// 긁기 단위 하나를 가리키는 앱 도메인 식별자. **불투명한 ID 로 다룬다.**
  ///
  /// 대부분은 통계청 시군구 코드 5자리(`sgg`)와 같지만 **전부는 아니다.**
  /// 2026-08-14 통합으로 서울은 `11000`, 제주는 `50000` 이라는 합성 ID 를 쓴다
  /// (시도 2자리 + `000`). 이 둘은 통계청 코드가 아니므로 `sgg` 라고 부르지 않는다.
  ///
  /// 값의 구조를 해석해 의미를 끌어내지 않는다. 통합 단위인지 알아야 하는
  /// 코드가 생기면 그때 명시적인 구분을 도입한다 — `000` 접미사 추론은 쓰지 않는다.
  /// 병합 명세는 `design/tools/merge_spec.py`.
  final String scratchUnitId;
  final String name;
  final int sido; // kSidoColors 인덱스
  final Path path;
  final Rect bounds; // T4 지역 판정에서 1차 필터로 쓴다

  /// 링별 평면 좌표 `[x0,y0,x1,y1,...]`.
  ///
  /// `Path` 는 정점을 되돌려주지 않으므로, 폴리곤까지의 **실제 거리**를 재려면
  /// 원본 좌표가 필요하다. bounds 거리로 대신하면 다도해 지역의 넓은 bounds가
  /// 먼 바다까지 삼킨다.
  final List<Float32List> rings;

  /// [p] 에서 이 지역 경계까지의 **최단 거리**(지도 좌표 단위 = km).
  /// 내부에 있으면 0.
  ///
  /// 조기 종료는 두지 않는다. 가장 가까운 지역을 고르려면 각 후보의 진짜
  /// 최솟값이 필요하고, 임계값을 만나자마자 멈추면 그 값이 최솟값이 아닐 수
  /// 있어 선택 결과가 스캔 순서에 좌우된다.
  double distanceTo(Offset p) {
    if (path.contains(p)) return 0;
    var best = double.infinity;
    for (final ring in rings) {
      for (var i = 0; i + 3 < ring.length; i += 2) {
        final d = distanceToSegmentRaw(
            p.dx, p.dy, ring[i], ring[i + 1], ring[i + 2], ring[i + 3]);
        if (d < best) best = d;
      }
    }
    return best;
  }
}

class SidoLine {
  SidoLine({required this.sido, required this.path});

  /// kSidoColors 인덱스
  final int sido;
  final Path path;
}

class MapData {
  MapData({
    required this.size,
    required this.sidoNames,
    required this.regions,
    required this.sidoLines,
    required this.backgroundLand,
    required this.vertexCount,
    required this.loadMs,
    required this.readMs,
    required this.decodeMs,
    required this.pathMs,
  });

  final Size size;
  final List<String> sidoNames;
  final List<Region> regions;

  /// 시도 외곽선. **배열 순서는 시도 인덱스와 무관하다** — 에셋의 피처 순서를
  /// 그대로 따르므로, 색을 칠할 때는 반드시 각 항목의 `sido` 를 써야 한다.
  final List<SidoLine> sidoLines;

  /// 북한 등 **선택할 수 없는 배경 땅.**
  ///
  /// `regions` 에 넣지 않는다 — 넣으면 지역 판정·카테고리 생성기·개수 검사·
  /// 시도 달성률이 전부 오염된다. 긁기 단위가 아니라 배경일 뿐이다.
  ///
  /// **y 가 음수다.** 지도 프레임은 남한만으로 정하므로(그래야 남한 배율이
  /// 유지된다) 북한은 위쪽으로 벗어난다. 렌더는 이 영역이 잘리지 않도록
  /// 클리핑을 풀어야 한다.
  final Path? backgroundLand;

  final int vertexCount;

  /// 전체 로딩 시간과 그 내역. 어느 단계가 병목인지 알아야 줄일 수 있다.
  final int loadMs;
  final int readMs; // 에셋 문자열 읽기
  final int decodeMs; // JSON 파싱
  final int pathMs; // ui.Path 생성

  static const _asset = 'assets/map/korea_sgg.json';

  /// 에셋은 좌표가 미리 투영·정규화되어 있어 여기서 변환하지 않는다.
  static Future<MapData> load() async {
    final sw = Stopwatch()..start();
    final raw = await rootBundle.loadString(_asset);
    final readMs = sw.elapsedMilliseconds;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final decodeMs = sw.elapsedMilliseconds - readMs;
    final pathStart = sw.elapsedMilliseconds;

    var vertices = 0;

    Path buildPath(List<dynamic> rings) {
      // 구멍(내부 링)의 감김 방향에 의존하지 않도록 evenOdd 를 쓴다.
      final p = Path()..fillType = PathFillType.evenOdd;
      for (final ring in rings) {
        final f = (ring as List).cast<num>();
        p.moveTo(f[0].toDouble(), f[1].toDouble());
        for (var i = 2; i < f.length; i += 2) {
          p.lineTo(f[i].toDouble(), f[i + 1].toDouble());
        }
        p.close();
        vertices += f.length ~/ 2;
      }
      return p;
    }

    final regions = <Region>[];
    for (final r in json['regions'] as List) {
      final m = r as Map<String, dynamic>;
      final rawRings = m['r'] as List;
      final path = buildPath(rawRings);
      // 거리 계산용 원본 좌표. Float32 로 충분하다 — 지도 좌표는 0~623km 범위이고
      // 판정 허용 오차가 km 단위라 소수점 이하 정밀도가 남는다.
      final rings = <Float32List>[];
      for (final ring in rawRings) {
        final f = (ring as List).cast<num>();
        final buf = Float32List(f.length);
        for (var i = 0; i < f.length; i++) {
          buf[i] = f[i].toDouble();
        }
        rings.add(buf);
      }
      regions.add(Region(
        scratchUnitId: m['c'] as String,
        name: m['n'] as String,
        sido: m['s'] as int,
        path: path,
        bounds: path.getBounds(),
        rings: rings,
      ));
    }

    // 배경 땅은 여러 링을 한 Path 로 합친다. 개별 링을 구분할 이유가 없다.
    Path? background;
    if (json['bg'] case final List raw when raw.isNotEmpty) {
      background = buildPath(raw);
    }

    final lines = <SidoLine>[];
    for (final s in json['sidoLines'] as List) {
      final m = s as Map<String, dynamic>;
      lines.add(SidoLine(
        sido: m['s'] as int,
        path: buildPath(m['r'] as List),
      ));
    }

    sw.stop();
    return MapData(
      size: Size((json['w'] as num).toDouble(), (json['h'] as num).toDouble()),
      sidoNames: (json['sidos'] as List).cast<String>(),
      regions: regions,
      sidoLines: lines,
      backgroundLand: background,
      vertexCount: vertices,
      loadMs: sw.elapsedMilliseconds,
      readMs: readMs,
      decodeMs: decodeMs,
      pathMs: sw.elapsedMilliseconds - pathStart,
    );
  }
}
