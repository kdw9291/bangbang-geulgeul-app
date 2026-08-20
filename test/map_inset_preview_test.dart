import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/map_inset.dart';
import 'package:mapscratch/map_inset_panel.dart';

/// **검사가 아니라 눈 확인 도구다.** `build/inset_*.png` 로 나온다.
///
/// 한글은 검증하지 못한다(테스트 폰트). 확대가 실제로 되는지, 수집한 곳이
/// 시도색으로 갈리는지, 경계선이 뭉개지지 않는지를 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData map;
  setUpAll(() async => map = await MapData.load());

  Future<void> shoot(
    WidgetTester tester,
    String insetId,
    AppTheme theme,
    Set<String> scratched,
    String name,
  ) async {
    final inset = resolveInset(
      kInsetDefinitions.firstWhere((d) => d.id == insetId),
      map,
    );
    // 실제 UI 와 같은 크기여야 눈 확인이 의미가 있다.
    const canvas = kInsetCanvasSize;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppThemeScope(
        theme: theme,
        child: Scaffold(
          backgroundColor: theme.background,
          body: Center(
            child: RepaintBoundary(
              key: const Key('shot'),
              child: SizedBox(
                width: canvas.width,
                height: canvas.height,
                child: CustomPaint(
                  painter: InsetPainter(
                    inset: inset,
                    sidoNames: map.sidoNames,
                    transform: InsetTransform.fit(inset.window, canvas),
                    scratched: scratched,
                    selected: null,
                    foil: theme.foilLight,
                    outline: theme.onSurfaceGhost,
                    selectionOuter: theme.selectionOuter,
                    selectionInner: theme.selectionInner,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/inset_$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('[PREVIEW] ${file.path}');
    });
  }

  testWidgets('수도권 — 빈 상태', (t) async {
    await shoot(t, 'capital', kThemeLight, const {}, 'capital_empty');
  });

  testWidgets('부산울산 — 일부 수집', (t) async {
    await shoot(t, 'busan', kThemeLight,
        {'26110', '26140', '26170', '26200', '26230'}, 'busan_some');
  });

  testWidgets('대구 — 일부 수집', (t) async {
    await shoot(t, 'daegu', kThemeLight, {'27110', '27140', '27710'},
        'daegu_some');
  });

  testWidgets('대구 — 다크', (t) async {
    await shoot(t, 'daegu', kThemeDark, {'27110', '27140'}, 'daegu_dark');
  });
}
