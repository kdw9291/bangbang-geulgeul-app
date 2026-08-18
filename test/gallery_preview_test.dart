import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/gallery_page.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_category.g.dart';

/// **검사가 아니라 눈 확인 도구다.**
///
/// 이 프로젝트는 단위 테스트가 전부 통과한 상태에서 화면이 틀린 적이 여러 번
/// 있었다(아트 배치·독도 파편화·시트 버튼이 화면 밖). 갤러리도 만들었으면
/// 반드시 그려서 본다. `build/gallery_*.png` 로 나온다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData map;
  setUpAll(() async => map = await MapData.load());

  Future<void> shoot(
    WidgetTester tester,
    String name,
    AppTheme theme,
    CollectionSnapshot snapshot,
  ) async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppThemeScope(
        theme: theme,
        child: Scaffold(
          backgroundColor: theme.background,
          body: RepaintBoundary(
            key: const Key('shot'),
            // 배경을 함께 담는다. 안 그리면 투명이 흰색으로 나와
            // 다크 테마 대비를 눈으로 판단할 수 없다.
            child: ColoredBox(
              color: theme.background,
              child: GalleryPage(
              data: map,
              snapshot: snapshot,
                onOpenRegion: (_) async {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')));
    // **`runAsync` 안에서 인코딩한다.** 위젯 테스트의 가짜 async 큐에서는
    // `toImage` 가 끝나지 않아 그대로 멈춘다. 안에 `pump` 는 넣지 않는다 —
    // 대기와 렌더를 섞으면 `setState` 가 화면에 반영되지 않는다.
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/gallery_$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('[PREVIEW] ${file.path}');
    });
  }

  CollectionSnapshot collect(Iterable<String> ids) {
    var s = CollectionSnapshot.empty;
    for (final id in ids) {
      s = s.collect(CollectedUnit(
        scratchUnitId: id,
        collectedAtUtc: DateTime.parse('2026-08-14T15:30:00Z'),
        utcOffsetMinutes: 540,
      ));
    }
    return s;
  }

  testWidgets('빈 갤러리 — 다크', (tester) async {
    await shoot(tester, 'empty_dark', kThemeDark, CollectionSnapshot.empty);
  });

  testWidgets('일부 수집 — 다크', (tester) async {
    await shoot(tester, 'some_dark', kThemeDark,
        collect(kPlannedLandmarks.take(6)));
  });

  testWidgets('일부 수집 — 라이트', (tester) async {
    await shoot(tester, 'some_light', kThemeLight,
        collect(kPlannedLandmarks.take(6)));
  });

  testWidgets('전부 수집 — 라이트', (tester) async {
    await shoot(tester, 'all_light', kThemeLight, collect(kPlannedLandmarks));
  });
}
