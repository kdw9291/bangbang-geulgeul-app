import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/records_page.dart';

/// **검사가 아니라 눈 확인 도구다.** `build/records_*.png` 로 나온다.
///
/// 한글은 검증하지 못한다 — 위젯 테스트 폰트에 글리프가 없어 사각형으로
/// 나온다. 색·간격·막대·메달 배치까지만 볼 수 있고 폭과 줄바꿈은 실기기에서만
/// 확인할 수 있다(M6 에서 시도명 중복을 PNG 로 못 잡았다).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData map;
  setUpAll(() async => map = await MapData.load());

  Future<void> shoot(
    WidgetTester tester,
    String name,
    AppTheme theme,
    int collectedCount,
  ) async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    final scratched = map.regions
        .take(collectedCount)
        .map((r) => r.scratchUnitId)
        .toSet();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppThemeScope(
        theme: theme,
        child: Scaffold(
          backgroundColor: theme.background,
          body: RepaintBoundary(
            key: const Key('shot'),
            child: ColoredBox(
              color: theme.background,
              child: RecordsPage(data: map, scratched: scratched),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')));
    // `runAsync` 밖에서 부르면 가짜 async 큐에서 끝나지 않고 멈춘다.
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/records_$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('[PREVIEW] ${file.path}');
    });
  }

  testWidgets('빈 상태 — 다크', (t) async => shoot(t, 'empty_dark', kThemeDark, 0));
  testWidgets('빈 상태 — 라이트',
      (t) async => shoot(t, 'empty_light', kThemeLight, 0));
  testWidgets('전부 — 다크',
      (t) async => shoot(t, 'all_dark', kThemeDark, 232));
  testWidgets('60곳 — 다크', (t) async => shoot(t, 'some_dark', kThemeDark, 60));
  testWidgets('60곳 — 라이트',
      (t) async => shoot(t, 'some_light', kThemeLight, 60));
  testWidgets('전부 — 라이트',
      (t) async => shoot(t, 'all_light', kThemeLight, 232));
}
