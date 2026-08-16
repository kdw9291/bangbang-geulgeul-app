import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';

/// M5 한 줄 메모 입력.
///
/// **앱을 통째로 띄워** 실제 배선으로 연다 — 편집 시트만 따로 만들어 검사하면
/// `_RegionSheet` 가 넘기는 값이 바뀌어도 통과한다(M4 에서 정한 방식).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData realMap;
  setUpAll(() async => realMap = await MapData.load());

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3.0;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// 경주시를 미리 수집해 둔 저장 파일.
  String savedWith({String? memo}) => encodeCollection(
        CollectionSnapshot.empty.collect(CollectedUnit(
          scratchUnitId: '47130',
          collectedAtUtc: DateTime.parse('2026-08-14T15:30:00Z'),
          utcOffsetMinutes: 540,
          memo: memo,
        )),
      );

  late _MemStorage storage;

  Future<void> openApp(WidgetTester tester, String? saved) async {
    storage = _MemStorage(saved);
    await tester.pumpWidget(MapScratchApp(
      mapLoader: () async => realMap,
      storeOpener: () async {
        final store = CollectionStore(storage);
        return (store, await store.load());
      },
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  Future<void> openRegion(WidgetTester tester, String name) async {
    await tester.tap(find.text('지역 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, name).first);
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('regionMemoEdit')));
    await tester.pumpAndSettle();
  }

  /// 저장을 누르고 **저장 완료까지** 기다린다. `runAsync` 와 `pump` 를 섞으면
  /// setState 가 렌더되지 않으므로 기다리는 것과 그리는 것을 나눈다.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('memoSave')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pumpAndSettle();
  }

  group('버튼 노출', () {
    testWidgets('미수집에는 메모 버튼이 없다', (tester) async {
      // 메모는 **수집한 지역의 기록**이다. 안 긁은 곳에 열어 주면
      // 수집하지 않은 레코드를 만들어야 한다.
      await openApp(tester, null);
      await openRegion(tester, '경주시');

      expect(find.byKey(const Key('regionMemoEdit')), findsNothing);
      expect(find.text('지역 긁기'), findsOneWidget);
    });

    testWidgets('메모가 없으면 남기기다', (tester) async {
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');
      expect(find.text('메모 남기기'), findsOneWidget);
      expect(find.text('메모 고치기'), findsNothing);
    });

    testWidgets('메모가 있으면 고치기다', (tester) async {
      await openApp(tester, savedWith(memo: '이미 있는 메모'));
      await openRegion(tester, '경주시');
      expect(find.text('메모 고치기'), findsOneWidget);
      expect(find.text('메모 남기기'), findsNothing);
    });

    testWidgets('공백뿐인 메모는 남기기다', (tester) async {
      // 본문은 그 메모를 숨기므로, 버튼만 "고치기" 면 고칠 것이 안 보인다.
      // 저장 경로가 정규화하므로 이런 값은 **밖에서 쓴 파일**로만 들어온다.
      await openApp(tester, savedWith(memo: '   '));
      await openRegion(tester, '경주시');
      expect(find.byKey(const Key('regionMemo')), findsNothing);
      expect(find.text('메모 남기기'), findsOneWidget);
    });
  });

  group('입력과 저장', () {
    testWidgets('저장하면 파일과 화면에 모두 반영된다', (tester) async {
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('memoField')), '비 오는 날의 첨성대');
      await tapSave(tester);

      // **팝업을 닫았다 열지 않아도** 그 자리에서 보여야 한다.
      expect(find.byKey(const Key('regionMemo')), findsOneWidget);
      expect(find.text('비 오는 날의 첨성대'), findsOneWidget);
      expect(find.text('메모 고치기'), findsOneWidget,
          reason: '버튼이 고치기로 바뀌지 않았다');

      expect(decodeCollection(storage.contents!)['47130']!.memo,
          '비 오는 날의 첨성대');
    });

    testWidgets('비우고 저장하면 지워진다', (tester) async {
      // 별도 삭제 버튼을 두지 않는다는 결정의 핵심이다.
      await openApp(tester, savedWith(memo: '지울 메모'));
      await openRegion(tester, '경주시');
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('memoField')), '   ');
      await tapSave(tester);

      expect(find.byKey(const Key('regionMemo')), findsNothing);
      expect(find.text('메모 남기기'), findsOneWidget);
      expect(decodeCollection(storage.contents!)['47130']!.memo, isNull);
    });

    testWidgets('취소하면 아무것도 바뀌지 않는다', (tester) async {
      await openApp(tester, savedWith(memo: '원래 메모'));
      await openRegion(tester, '경주시');
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('memoField')), '바꾼 내용');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.text('원래 메모'), findsOneWidget);
      expect(decodeCollection(storage.contents!)['47130']!.memo, '원래 메모');
    });

    testWidgets('기존 메모가 입력창에 채워져 있다', (tester) async {
      // 고치기인데 빈 칸이 나오면 지우고 다시 쓰라는 뜻이 된다.
      await openApp(tester, savedWith(memo: '고칠 메모'));
      await openRegion(tester, '경주시');
      await openEditor(tester);

      final field =
          tester.widget<TextField>(find.byKey(const Key('memoField')));
      expect(field.controller!.text, '고칠 메모');
    });

    testWidgets('상한을 넘겨 칠 수 없다', (tester) async {
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');
      await openEditor(tester);

      await tester.enterText(
          find.byKey(const Key('memoField')), '가' * (kMemoMaxLength + 20));
      await tester.pump();

      final field =
          tester.widget<TextField>(find.byKey(const Key('memoField')));
      expect(field.controller!.text.characters.length, kMemoMaxLength);
    });
  });

  group('저장 실패', () {
    testWidgets('오류를 시트 안에 보여 주고 입력을 지키지 않는다면 안 된다',
        (tester) async {
      // SnackBar 로 띄우면 모달 시트 뒤에 깔려 보이지 않을 수 있다 (Codex 21회차).
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');
      await openEditor(tester);

      storage.failWrite = true;
      await tester.enterText(find.byKey(const Key('memoField')), '실패할 메모');
      await tapSave(tester);

      expect(find.byKey(const Key('memoError')), findsOneWidget);
      final field =
          tester.widget<TextField>(find.byKey(const Key('memoField')));
      expect(field.controller!.text, '실패할 메모', reason: '입력을 버렸다');

      // 다시 시도하면 저장된다.
      storage.failWrite = false;
      await tapSave(tester);
      expect(find.text('실패할 메모'), findsOneWidget);
      expect(decodeCollection(storage.contents!)['47130']!.memo, '실패할 메모');
    });

    testWidgets('저장 중에는 뒤로가기로 나갈 수 없다', (tester) async {
      // 나가 버리면 저장은 됐는데 바깥 팝업이 갱신되지 않는 경로가 생긴다.
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');
      await openEditor(tester);

      final gate = Completer<void>();
      storage.gate = gate;
      await tester.enterText(find.byKey(const Key('memoField')), '느린 저장');
      await tester.tap(find.byKey(const Key('memoSave')));
      await tester.pump();

      expect(canPopNow(tester), isFalse, reason: '저장 중인데 나갈 수 있다');
      expect(find.text('저장 중…'), findsOneWidget);

      gate.complete();
      await tester.runAsync(() => Future<void>.value());
      await tester.pumpAndSettle();
      expect(find.text('느린 저장'), findsOneWidget);
    });

    testWidgets('저장 중 아래로 끌어도 닫히지 않는다', (tester) async {
      // **`PopScope` 로는 부족하다.** 하단 시트의 드래그는 `Navigator.pop` 을
      // 직접 부르므로 `canPop` 을 우회한다 (Codex 21회차). 닫혀 버리면 저장은
      // 됐는데 바깥 팝업이 결과를 못 받고, 실패했다면 입력과 오류가 함께 사라진다.
      await openApp(tester, savedWith());
      await openRegion(tester, '경주시');
      await openEditor(tester);

      final gate = Completer<void>();
      storage.gate = gate;
      await tester.enterText(find.byKey(const Key('memoField')), '끌어도 남는다');
      await tester.tap(find.byKey(const Key('memoSave')));
      await tester.pump();

      await tester.drag(find.byKey(const Key('memoField')), const Offset(0, 500));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('memoField')), findsOneWidget,
          reason: '저장 중인데 끌어서 닫혔다');

      gate.complete();
      await tester.runAsync(() => Future<void>.value());
      await tester.pumpAndSettle();
      expect(find.text('끌어도 남는다'), findsOneWidget);
    });
  });

  testWidgets('키보드가 올라와도 저장 버튼을 누를 수 있다', (tester) async {
    // **여기가 `isScrollControlled` 가 필요한 진짜 이유다.** 없으면 시트가 화면의
    // 9/16 까지만 쓸 수 있어, 키보드 높이만큼 밀어 올릴 자리가 없다.
    // 짧은 화면 테스트만으로는 이걸 못 잡는다 — 그 시트는 9/16 안에 들어간다.
    await openApp(tester, savedWith());
    await openRegion(tester, '경주시');
    await openEditor(tester);

    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.viewInsets = const FakeViewPadding(bottom: 900); // 물리 픽셀
    addTearDown(view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '키보드가 올라오자 넘쳤다');
    await tester.enterText(find.byKey(const Key('memoField')), '키보드 위에서');
    await tapSave(tester);

    expect(find.byKey(const Key('memoSave')), findsNothing,
        reason: '저장 버튼이 키보드에 가려 눌리지 않았다');
    expect(find.text('키보드 위에서'), findsOneWidget);
  });

  testWidgets('세로가 짧아도 저장 버튼을 누를 수 있다', (tester) async {
    // 스크롤로 끌어올려 누르면 화면 밖이어도 통과한다 (M4 에서 배운 것).
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 1400);
    view.devicePixelRatio = 3.0;

    await openApp(tester, savedWith());
    await openRegion(tester, '경주시');
    await openEditor(tester);

    expect(tester.takeException(), isNull, reason: '편집 시트가 넘쳤다');
    await tester.enterText(find.byKey(const Key('memoField')), '짧은 화면');
    await tapSave(tester);

    expect(find.byKey(const Key('memoSave')), findsNothing,
        reason: '저장 버튼이 화면 밖이라 눌리지 않았다');
    expect(find.text('짧은 화면'), findsOneWidget);
  });
}

/// 편집 시트의 `PopScope`. 제네릭이라 `find.byType` 이 잡지 못한다.
bool canPopNow(WidgetTester tester) {
  final found = tester
      .widgetList(find.byWidgetPredicate((w) => w is PopScope))
      .cast<PopScope>()
      .toList();
  expect(found, isNotEmpty, reason: 'PopScope 가 트리에 없다');
  return found.last.canPop;
}

class _MemStorage implements CollectionStorage {
  _MemStorage(this.contents);
  String? contents;
  bool failWrite = false;
  Completer<void>? gate;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> writeAtomically(String c) async {
    if (gate != null) await gate!.future;
    if (failWrite) throw const FileSystemException('쓰기 실패');
    contents = c;
  }

  @override
  Future<String> quarantine() async {
    contents = null;
    return 'corrupt.json';
  }
}
