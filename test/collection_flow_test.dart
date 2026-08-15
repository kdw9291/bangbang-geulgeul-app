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

  testWidgets('완료해도 긁기 영역 크기가 바뀌지 않는다', (tester) async {
    // 하단이 안내 문구에서 버튼으로 바뀌며 위쪽이 줄어들면 `LayoutBuilder` 가
    // 새 크기를 보고 준비를 다시 돌린다. 그 안의 `_strokes.clear()` 가
    // 긁은 자취를 버린다 — 신안군 기준 23ms 낭비이자 잠재 버그였다
    // (2026-08-14 실기기에서 발견, M9 에서 처리).
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async {},
    )));
    await tester.pump();
    await tester.pump();

    final before = tester.getSize(find.byKey(const Key('scratchArea')));
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('지도로 돌아가기'), findsOneWidget, reason: '완료 상태가 아니다');
    expect(tester.getSize(find.byKey(const Key('scratchArea'))), before,
        reason: '완료하면서 긁기 영역이 리사이즈됐다');
  });

  testWidgets('저장하는 중에도 크기가 그대로다', (tester) async {
    // 완료 직후 잠깐 지나가는 상태라 놓치기 쉽다 (Codex 19회차).
    final gate = Completer<void>();
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) => gate.future,
    )));
    await tester.pump();
    await tester.pump();

    final before = tester.getSize(find.byKey(const Key('scratchArea')));
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('기록하는 중…'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('scratchArea'))), before);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('scratchArea'))), before);
  });

  /// [scale] 배율에서 **하단 영역** 높이.
  ///
  /// 긁기 영역 높이로 재면 안 된다 — 위쪽 진행률 글자도 함께 커져서,
  /// 하단을 고정 픽셀로 막아 놓아도 긁기 영역은 줄어든다. 실제로 그 테스트가
  /// 고정 높이 구현을 통과시켰다.
  Future<double> footerHeightAt(WidgetTester tester, double scale) async {
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: wrap(ScratchPage(
        region: region,
        sidoName: '경상북도',
        onCollected: (u) async {},
      )),
    ));
    await tester.pump();
    await tester.pump();
    return tester.getSize(find.byKey(const Key('scratchFooter'))).height;
  }

  testWidgets('글꼴을 키우면 하단이 그만큼 커진다', (tester) async {
    // **고정 픽셀로 막지 않는다.** 처음에는 `height: 48` 로 못 박았는데,
    // 그러면 상태별 높이는 같아지지만 큰 글꼴에서 글자가 잘린다.
    // 상태 전환에는 안 변하고 글꼴 배율에는 따라가야 맞다 (Codex 19회차).
    // 2.0 에서는 가장 높은 상태도 최소 높이(48) 안에 들어가 차이가 안 난다.
    // 실제로 막히는지 보려면 그보다 키워야 한다.
    final small = await footerHeightAt(tester, 1.0);
    final large = await footerHeightAt(tester, 3.0);

    expect(small, 48.0, reason: '기본 배율에서는 최소 높이를 쓴다');
    expect(large, greaterThan(small),
        reason: '글꼴을 키웠는데 하단이 그대로다 — 고정 높이로 막고 있다');
  });

  testWidgets('큰 글꼴에서도 상태가 바뀌면 크기가 그대로다', (tester) async {
    // **배율 2.0 으로는 부족하다.** 그 배율에서는 모든 상태가 최소 높이 48 안에
    // 들어가서, 상태를 함께 레이아웃하지 않아도 통과한다 (Codex 19회차).
    var first = true;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
      child: wrap(ScratchPage(
        region: region,
        sidoName: '경상북도',
        onCollected: (u) async {
          if (first) {
            first = false;
            throw StateError('디스크 오류');
          }
        },
      )),
    ));
    await tester.pump();
    await tester.pump();

    // 하단만 재야 한다 — 위쪽 진행률 글자도 함께 커지므로 긁기 영역으로 재면
    // 고정 높이 구현도 통과한다.
    final footer = find.byKey(const Key('scratchFooter'));
    final hintHeight = tester.getSize(footer).height;

    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('다시 시도'), findsOneWidget);
    expect(tester.getSize(footer).height, hintHeight,
        reason: '큰 글꼴에서 실패 상태가 하단을 밀었다');
    expect(tester.takeException(), isNull, reason: '실패 상태에서 오버플로가 났다');

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(find.text('지도로 돌아가기'), findsOneWidget);
    expect(tester.getSize(footer).height, hintHeight,
        reason: '큰 글꼴에서 완료 상태가 하단을 밀었다');
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장 실패로 재시도가 떠도 크기가 그대로다', (tester) async {
    var first = true;
    await tester.pumpWidget(wrap(ScratchPage(
      region: region,
      sidoName: '경상북도',
      onCollected: (u) async {
        if (first) {
          first = false;
          throw StateError('디스크 오류');
        }
      },
    )));
    await tester.pump();
    await tester.pump();

    final before = tester.getSize(find.byKey(const Key('scratchArea')));
    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('다시 시도'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('scratchArea'))), before);
  });

  testWidgets('실제 뒤로가기로도 기록 전에는 못 나간다', (tester) async {
    // **`canPop` 속성만 읽으면 부족하다.** 시스템이 실제로 보내는 back 을
    // 흘려보내는지까지 봐야 "시스템 뒤로가기로 완료가 사라진다" 는 S1 결함이
    // 정말 닫혔다고 할 수 있다 (Codex 19회차).
    // **루트 라우트로 두면 안 된다.** Navigator 는 마지막 하나를 pop 하지 않아
    // "막혀서 안 나간 것" 과 구분되지 않는다. 아래에 화면을 하나 깔고 그 위에 쌓는다.
    var attempts = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(wrap(Scaffold(
      key: nav,
      body: const Center(child: Text('지도 자리')),
    )));
    await tester.pump();

    unawaited(Navigator.of(tester.element(find.text('지도 자리'))).push(
      MaterialPageRoute<void>(
        builder: (_) => ScratchPage(
          region: region,
          sidoName: '경상북도',
          onCollected: (u) async {
            if (++attempts == 1) throw StateError('디스크 오류');
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.pump();

    await scratchAll(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('다시 시도'), findsOneWidget);

    // 실패 상태에서 back → 화면이 남아 있어야 한다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget,
        reason: '기록되지 않았는데 뒤로가기로 빠져나갔다');

    // 막혔다는 안내(SnackBar)가 하단을 덮으므로 사라질 때까지 기다린다.
    // 시간만 넘기면 사라지는 애니메이션이 남아 여전히 탭을 가로챈다.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 재시도해 기록되면 그때는 나갈 수 있다.
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();
    expect(find.text('지도로 돌아가기'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('지도로 돌아가기'), findsNothing,
        reason: '기록됐는데도 못 나간다');
    expect(find.text('지도 자리'), findsOneWidget);
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
