import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_art.dart';

/// 2026-08-20 광역시 통합 5곳의 아트가 **도형 안에 남는가.**
///
/// 통합 도형은 링이 여럿이고 종횡비도 달라져(대구 1:1.62) 아트가 잘릴 수 있다.
/// `artTargetFill` 은 줄여 맞추지 않고 **항상 긴 변의 95%** 로 정사각형을 잡으므로,
/// 세로로 긴 도형에서는 아트가 좌우로 잘려 나간다.
///
/// 기존 안전 영역 테스트(`region_art_test`)는 **SVG 좌표만** 본다. 그 영역이
/// 실제 지역 도형 안에 남는지는 검사하지 않아, 도형이 바뀌어도 통과한다.
/// 여기서 실제 `Path.contains` 로 잰다 (Codex 30회차 설계 검토 지적).
///
/// 산출물: `build/merged_regions.png` (눈 확인용, 검사는 아래 단언이 한다)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 통합으로 생긴 긁기 단위와 각각의 **하한**.
  ///
  /// 하한은 2026-08-20 실측(부산 82 · 대구 52 · 인천 84 · 대전 100 · 울산 98)
  /// 아래로 **5~7%p** 잡았다. **목표치가 아니라 회귀 감지선이다** — 도형이나
  /// 아트를 고쳤을 때 조용히 나빠지는 것을 잡는다. 플랫폼별 래스터 차이로
  /// 흔들리지 않을 만큼은 띄우되, 눈에 띄는 악화는 걸리게 둔다.
  const merged = {
    '26000': 75.0, // 부산 — 가덕도 등으로 링 3개
    '27000': 45.0, // 대구 — 군위군이 붙어 세로로 길다. 32곳 중 3위로 나쁘다
    '28000': 78.0, // 인천 — 영종도로 링 3개
    '30000': 95.0, // 대전
    '31000': 92.0, // 울산
  };

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  /// 아트의 안전 영역 중 **실제 도형 안에 드는 비율**(%).
  ///
  /// 초점은 긁기 화면과 같은 `largestRingBounds` 를 쓴다. 전국 지도는 전체
  /// bounds 를 쓰지만, 아트를 크게 보는 곳은 긁기 화면이라 그쪽을 기준으로 한다.
  double safeAreaCoverage(Region r, {Matrix4? transform}) {
    final m = transform ?? Matrix4.identity();
    final path = r.path.transform(m.storage);
    final focus = largestRingBounds(r.rings,
        scale: m.storage[0], offset: Offset(m.storage[12], m.storage[13]));
    final t = artTargetFill(path, focus);
    final safe = Rect.fromLTWH(
      t.left + t.width * kSafeArea.left / 100,
      t.top + t.height * kSafeArea.top / 100,
      t.width * kSafeArea.width / 100,
      t.height * kSafeArea.height / 100,
    );
    var inside = 0, total = 0;
    for (var a = 0; a < 24; a++) {
      for (var b = 0; b < 24; b++) {
        total++;
        if (path.contains(Offset(safe.left + safe.width * (a + .5) / 24,
            safe.top + safe.height * (b + .5) / 24))) {
          inside++;
        }
      }
    }
    return inside / total * 100;
  }

  Region regionOf(String code) =>
      data.regions.firstWhere((e) => e.scratchUnitId == code);

  group('통합 지역의 아트', () {
    test('다섯 곳 전부가 하한을 넘는다', () {
      for (final e in merged.entries) {
        final r = regionOf(e.key);
        final got = safeAreaCoverage(r);
        expect(got, greaterThanOrEqualTo(e.value),
            reason: '${r.name}(${e.key}) 안전 영역이 ${got.toStringAsFixed(0)}% 만'
                ' 도형 안에 있다. 하한 ${e.value}%');
      }
    });

    test('다섯 곳 모두 랜드마크를 하나씩 갖는다', () {
      // 하한 검사가 **측정하지 못한 채 통과**하는 것을 막는다.
      for (final code in merged.keys) {
        expect(kLandmarkArt[code], isNotNull, reason: code);
      }
      expect(merged.length, 5);
    });

    test('통합이 랜드마크 전체를 나쁘게 만들지 않았다', () {
      // 통합 지역만 보면 "원래 다 이렇다" 인지 알 수 없다. 32곳의 중앙값을
      // 함께 잡아 둔다. 2026-08-20 실측 90%.
      final rates = <double>[];
      for (final r in data.regions) {
        if (!kLandmarkArt.containsKey(r.scratchUnitId)) continue;
        rates.add(safeAreaCoverage(r));
      }
      expect(rates.length, 32);
      rates.sort();
      // **짝수라 가운데 둘의 평균을 쓴다.** `~/ 2` 한 쪽만 보면 절반이
      // 85 아래로 떨어져도 통과한다 (Codex 30회차 3차 지적).
      final mid = (rates[rates.length ~/ 2 - 1] + rates[rates.length ~/ 2]) / 2;
      expect(mid, greaterThanOrEqualTo(85.0),
          reason: '랜드마크 32곳의 중앙값이 ${mid.toStringAsFixed(1)}% 로 떨어졌다');
    });
  });

  test('통합 5곳을 긁기 화면 초점으로 그린다 — 눈 확인용', () async {
    const codes = ['26000', '27000', '28000', '30000', '31000'];
    const cell = 300.0, label = 34.0;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, cell * codes.length, cell + label),
        Paint()..color = const Color(0xFF101418));

    for (var i = 0; i < codes.length; i++) {
      final r = regionOf(codes[i]);
      const pad = 24.0;
      final k = math.min((cell - pad * 2) / r.bounds.width,
          (cell - pad * 2) / r.bounds.height);
      final m = Matrix4.identity()
        ..translateByDouble(i * cell + cell / 2 - r.bounds.center.dx * k,
            label + cell / 2 - r.bounds.center.dy * k, 0, 1)
        ..scaleByDouble(k, k, 1, 1);
      final path = r.path.transform(m.storage);
      final focus = largestRingBounds(r.rings,
          scale: m.storage[0], offset: Offset(m.storage[12], m.storage[13]));
      final t = artTargetFill(path, focus);

      canvas.drawPath(path, Paint()..color = const Color(0xFF2E4A63));
      canvas.save();
      canvas.clipPath(path);
      paintRegionArt(canvas, kLandmarkArt[codes[i]]!, t);
      canvas.restore();
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: .35));
      // 노란 테두리 = 아트 전체, 빨간 테두리 = 안전 영역.
      canvas.drawRect(
          t,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFE0B84A));
      canvas.drawRect(
          Rect.fromLTWH(
            t.left + t.width * kSafeArea.left / 100,
            t.top + t.height * kSafeArea.top / 100,
            t.width * kSafeArea.width / 100,
            t.height * kSafeArea.height / 100,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFFE05A5A));
      debugPrint('[MERGED] ${r.name} 링 ${r.rings.length} · '
          '${kLandmarkArt[codes[i]]!.name} · '
          '안전영역 ${safeAreaCoverage(r).toStringAsFixed(0)}%');
    }

    final img = await rec
        .endRecording()
        .toImage((cell * codes.length).round(), (cell + label).round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build').createSync(recursive: true);
    File('build/merged_regions.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
    debugPrint('[MERGED] → build/merged_regions.png');
  });
}
