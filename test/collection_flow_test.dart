import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/scratch_page.dart';

/// M1 의 **화면 쪽 계약**. 저장 계층 자체는 `collection_test.dart` 가 본다.
///
/// 여기서 막는 것은 하나다 — **긁은 것이 기록되지 않은 채로 화면을 떠나는 일.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  late Region region;
  setUpAll(() async {
    data = await MapData.load();
    // 독도는 표본이 적고 화면 가득 차서 자동 완성까지 몰기 쉽다.
    region = data.regions.firstWhere((r) => r.scratchUnitId == 'DK001');
  });

  Widget wrap(Widget child) => AppThemeScope(
        theme: kThemeLight,
        child: MaterialApp(theme: ThemeData.light(), home: child),
      );

  /// `PopScope` 는 제네릭(`PopScope<T>`)이라 `find.byType(PopScope)` 가 잡지
  /// 못한다. 술어로 찾는다.
  bool canPopNow(WidgetTester tester) {
    final found = tester
        .widgetList(find.byWidgetPredicate((w) => w is PopScope))
        .cast<PopScope>()
        .toList();
    expect(found, isNotEmpty, reason: 'PopScope 가 트리에 없다');
    return found.first.canPop;
  }

  bool closeButtonEnabled(WidgetTester tester) {
    // `byIcon` 은 `Icon` 을 잡는다. 버튼은 그 조상이다.
    final button = find.ancestor(
      of: find.byIcon(Icons.close),
      matching: find.byType(IconButton),
    );
    return tester.widget<IconButton>(button.first).onPressed != null;
  }

  /// 임계치를 넘길 때까지 화면을 훑는다.
  Future<void> scratchAll(WidgetTester tester) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var y = 40.0; y < size.height - 40; y += 12) {
      await tester.dragFrom(Offset(20, y), Offset(size.width - 40, 0));
      await tester.pump();
    }
  }

  testWidgets('임계치에 도달하면 화면을 닫기 전에 저장을 요청한다', (tester) async {
    // 예전에는 `pop(true)` 가 커밋 신호였다. 그러면 완료 연출을 보는 동안
    // 앱이 죽으면 기록이 사라진다.
    CollectedUnit? saved;
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async => saved = u,
    )));
    await tester.pump(); // 준비는 addPostFrameCallback 에서 돈다
    await tester.pump();

    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(saved, isNotNull, reason: '화면을 닫지 않았는데 저장이 요청되지 않았다');
    expect(saved!.scratchUnitId, 'DK001');
    expect(find.text('지도로 돌아가기'), findsOneWidget);
  });

  testWidgets('수집 시각과 오프셋을 수집 순간에 잡는다', (tester) async {
    CollectedUnit? saved;
    final before = DateTime.now().toUtc();
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async => saved = u,
    )));
    await tester.pump();
    await tester.pump();
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(saved!.collectedAtUtc.isBefore(before), isFalse);
    expect(saved!.utcOffsetMinutes, DateTime.now().timeZoneOffset.inMinutes);
  });

  testWidgets('저장이 실패하면 재시도를 띄우고 돌아가기를 주지 않는다', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async {
        attempts++;
        if (attempts == 1) throw StateError('디스크 오류');
      },
    )));
    await tester.pump();
    await tester.pump();
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('지도로 돌아가기'), findsNothing,
        reason: '기록되지 않았는데 돌아가게 두면 안 된다');

    // **버튼만 숨기는 것으로는 부족하다.** 시스템 뒤로가기와 X 로도 나갈 수
    // 있었다 — 긁은 것이 그대로 버려진다 (Codex 16회차).
    expect(canPopNow(tester), isFalse, reason: '실패 상태에서 뒤로가기가 열려 있다');
    expect(closeButtonEnabled(tester), isFalse, reason: '실패 상태에서 X 가 열려 있다');

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.text('지도로 돌아가기'), findsOneWidget);
    expect(canPopNow(tester), isTrue);
    expect(closeButtonEnabled(tester), isTrue);
  });

  testWidgets('다 긁기 전에는 언제든 나갈 수 있다', (tester) async {
    // 진행 중 이탈은 원래 허용이다. 잠그는 것은 "다 긁었는데 기록 안 됨" 뿐이다.
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async {},
    )));
    await tester.pump();
    await tester.pump();

    expect(canPopNow(tester), isTrue);
    expect(closeButtonEnabled(tester), isTrue);
  });

  testWidgets('재시도해도 수집 시각이 바뀌지 않는다', (tester) async {
    // 갱신하면 "실제로 긁은 때" 가 아니라 "저장에 성공한 때" 가 된다.
    final seen = <DateTime>[];
    var attempts = 0;
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async {
        seen.add(u.collectedAtUtc);
        if (++attempts == 1) throw StateError('디스크 오류');
      },
    )));
    await tester.pump();
    await tester.pump();
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(seen.length, 2);
    expect(seen[0], seen[1]);
  });

  testWidgets('저장하는 동안에는 나갈 수 없다', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) => gate.future,
    )));
    await tester.pump();
    await tester.pump();
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('기록하는 중…'), findsOneWidget);
    expect(canPopNow(tester), isFalse, reason: '저장 중에 뒤로가기가 열려 있다');

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(canPopNow(tester), isTrue);
  });
}
