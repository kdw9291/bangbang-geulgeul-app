import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_info.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/collection_store.dart';
import 'package:mapscratch/main.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/settings.dart';
import 'package:mapscratch/settings_store.dart';

/// M12 설정 화면. **앱을 통째로 띄워** 실제 배선으로 연다.
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

  late _MemSettings settings;
  late int mapLoads;
  late int storeOpens;

  Future<void> openApp(WidgetTester tester, {String? saved}) async {
    settings = _MemSettings(saved);
    mapLoads = 0;
    storeOpens = 0;
    await tester.pumpWidget(MapScratchApp(
      mapLoader: () async {
        mapLoads++;
        return realMap;
      },
      storeOpener: () async {
        storeOpens++;
        final store = CollectionStore(_NullCollection());
        return (store, await store.load());
      },
      settingsOpener: () async {
        final s = SettingsStore(settings);
        await s.load();
        return s;
      },
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pump();
    await tester.pump();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
  }

  /// 설정은 `ListView` 라 화면 밖 항목이 **아직 만들어지지도 않았다.**
  /// 그냥 찾으면 "없다" 가 나오므로 보일 때까지 굴린다.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
  }

  Future<void> pickSea(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('sea_$name')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.value());
    await tester.pumpAndSettle();
  }

  group('진입', () {
    testWidgets('지도 화면에서 설정으로 들어간다', (tester) async {
      await openApp(tester);
      expect(find.byKey(const Key('openSettings')), findsOneWidget);

      await openSettings(tester);
      expect(find.text('설정'), findsOneWidget);
      expect(find.text('지도 데이터 출처'), findsOneWidget);
    });

    testWidgets('설정 버튼이 검색을 밀어내지 않는다', (tester) async {
      await openApp(tester);
      expect(find.text('지역 검색'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
      // 320px 은 지금도 쓰이는 가장 좁은 안드로이드 폭이다.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(320, 800);
      view.devicePixelRatio = 1.0;

      await openApp(tester);
      expect(tester.takeException(), isNull, reason: '검색줄이 넘쳤다');

      await openSettings(tester);
      expect(tester.takeException(), isNull, reason: '설정 화면이 넘쳤다');
    });
  });

  group('출처 표시 — CC BY 4.0 의무', () {
    testWidgets('저작자·라이선스·변경 고지·링크가 모두 있다', (tester) async {
      // **하나라도 빠지면 라이선스 위반이라 출시할 수 없다.**
      // 변경 고지는 내 초안에서 빠져 있었다 (Codex 22회차).
      await openApp(tester);
      await openSettings(tester);

      // **`textContaining` 을 쓰지 않는다.** 'vuski/admdongkor' 는 본문과 URL
      // 양쪽에 있어 finder 가 둘을 잡는다.
      await scrollTo(tester, find.text(kMapAttributionBody));
      expect(kMapAttributionBody, contains('vuski/admdongkor'),
          reason: '저작자 표시가 없다');
      expect(kMapAttributionBody, contains('CC BY 4.0'),
          reason: '라이선스 명시가 없다');

      await scrollTo(tester, find.text(kMapAttributionChanges));
      expect(find.text(kMapAttributionChanges), findsOneWidget,
          reason: '변경 고지가 화면에 없다');

      await scrollTo(tester, find.text(kMapLicenseUrl));
      expect(find.text(kMapDistributionUrl), findsOneWidget,
          reason: '자료 링크가 없다');
      expect(find.text(kMapLicenseUrl), findsOneWidget,
          reason: '라이선스 링크가 없다');

      await scrollTo(tester, find.text(kMapSourceUrl));
      expect(find.text(kMapSourceUrl), findsOneWidget, reason: '원자료 링크가 없다');
    });

    testWidgets('URL 은 복사할 수 있다', (tester) async {
      // `url_launcher` 를 넣지 않는 대신 선택 가능해야 한다.
      await openApp(tester);
      await openSettings(tester);
      await scrollTo(tester, find.text(kMapSourceUrl));
      // 셋이 한 화면에 다 보이지 않을 수 있으므로 마지막 것으로 확인한다.
      expect(
        tester.widget<SelectableText>(find.ancestor(
          of: find.text(kMapSourceUrl),
          matching: find.byType(SelectableText),
        )),
        isA<SelectableText>(),
      );
    });
  });

  group('바다 색 선택', () {
    testWidgets('고르면 앱 테마가 즉시 바뀐다', (tester) async {
      await openApp(tester);
      await openSettings(tester);

      final before = AppThemeScope.of(
              tester.element(find.byType(Scaffold).first))
          .brightness;
      expect(before, Brightness.light, reason: '기본은 밝은 바다다');

      await pickSea(tester, 'deep');

      final after = AppThemeScope.of(
              tester.element(find.byType(Scaffold).first))
          .brightness;
      expect(after, Brightness.dark, reason: '깊은 바다는 어두운 화면이다');
    });

    testWidgets('고른 값이 파일에 남는다', (tester) async {
      await openApp(tester);
      await openSettings(tester);
      await pickSea(tester, 'sunset');

      expect(decodeSettings(settings.contents!).seaName, 'sunset');
    });

    testWidgets('저장된 값으로 시작한다', (tester) async {
      await openApp(tester, saved: encodeSettings(const AppSettings(seaName: 'deep')));

      final t =
          AppThemeScope.of(tester.element(find.byType(Scaffold).first));
      expect(t.brightness, Brightness.dark);
    });

    testWidgets('바다를 바꿔도 지도와 저장소를 다시 읽지 않는다', (tester) async {
      // 팔레트를 `key` 에 묶으면 State 가 새로 생겨 확대 위치·선택이 초기화된다
      // (Codex 22회차).
      await openApp(tester);
      expect(mapLoads, 1);
      expect(storeOpens, 1);

      await openSettings(tester);
      await pickSea(tester, 'deep');
      await pickSea(tester, 'sunset');

      expect(mapLoads, 1, reason: '지도를 다시 읽었다');
      expect(storeOpens, 1, reason: '저장소를 다시 열었다');
    });

    testWidgets('고른 뒤 체크 표시가 그 항목으로 옮겨간다', (tester) async {
      // **개수만 세면 부족하다.** 체크가 옛 항목에 남아 있어도 통과한다 —
      // 설정 화면이 Stateless 였을 때 실제로 그랬다 (Codex 22회차).
      await openApp(tester);
      await openSettings(tester);

      Finder checkIn(String name) => find.descendant(
            of: find.byKey(Key('sea_$name')),
            matching: find.byIcon(Icons.check),
          );

      expect(checkIn('cerulean'), findsOneWidget);
      expect(checkIn('deep'), findsNothing);

      await pickSea(tester, 'deep');

      expect(checkIn('deep'), findsOneWidget, reason: '고른 항목에 표시가 없다');
      expect(checkIn('cerulean'), findsNothing,
          reason: '체크가 옛 항목에 남아 있다');
    });

    testWidgets('저장에 실패하면 알린다', (tester) async {
      // 조용히 버리면 사용자가 저장된 줄 알고, 앱을 껐다 켜면 되돌아간다.
      await openApp(tester);
      await openSettings(tester);
      settings.failWrite = true;

      await pickSea(tester, 'deep');
      await tester.pump();

      expect(find.textContaining('저장하지 못했습니다'), findsOneWidget);
    });

    testWidgets('색만으로 구분하지 않는다 — 이름과 선택 표시가 있다', (tester) async {
      await openApp(tester);
      await openSettings(tester);

      expect(find.text('맑은 바다'), findsOneWidget);
      expect(find.text('노을 바다'), findsOneWidget);
      expect(find.text('깊은 바다'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget,
          reason: '지금 고른 것이 무엇인지 표시가 없다');
    });

    testWidgets('flat 은 목록에 없다', (tester) async {
      await openApp(tester);
      await openSettings(tester);
      expect(find.byKey(const Key('sea_flat')), findsNothing);
    });
  });

  group('첫 프레임', () {
    testWidgets('이미 읽어 둔 설정이면 첫 프레임부터 어둡다', (tester) async {
      // `main()` 이 설정을 읽고 나서 `runApp` 하는 이유다. 화면을 먼저 띄우면
      // 어두운 바다를 고른 사용자가 **흰 화면이 번쩍이는 것**을 본다
      // (Codex 22회차).
      final store = SettingsStore(
          _MemSettings(encodeSettings(const AppSettings(seaName: 'deep'))));
      await store.load();

      await tester.pumpWidget(MapScratchApp(
        settings: store,
        mapLoader: () async => realMap,
        storeOpener: () async {
          final s = CollectionStore(_NullCollection());
          return (s, await s.load());
        },
      ));
      // **`pump` 한 번뿐이다.** 첫 프레임에서 이미 어두워야 한다.
      final t =
          AppThemeScope.of(tester.element(find.byType(Scaffold).first));
      expect(t.brightness, Brightness.dark,
          reason: '첫 프레임이 밝게 나왔다 — 테마 플래시가 생긴다');
    });
  });

  group('앱 정보', () {
    testWidgets('버전과 오픈소스 라이선스 진입점이 있다', (tester) async {
      await openApp(tester);
      await openSettings(tester);

      await scrollTo(tester, find.byKey(const Key('openSourceLicenses')));
      expect(find.byKey(const Key('appVersion')), findsOneWidget);
      expect(find.text(appVersionLabel), findsOneWidget);
      expect(find.byKey(const Key('openSourceLicenses')), findsOneWidget);
    });
  });

  group('여기 없어야 하는 것', () {
    testWidgets('계정·로그인은 S3 다', (tester) async {
      // M12 범위를 못 박는다. 동작하지 않는 UI 를 미리 만들지 않기로 했다.
      await openApp(tester);
      await openSettings(tester);

      expect(find.textContaining('로그인'), findsNothing);
      expect(find.textContaining('회원'), findsNothing);
      expect(find.textContaining('계정'), findsNothing);
    });

    testWidgets('데이터 초기화·백업은 출시 후 결정이다', (tester) async {
      await openApp(tester);
      await openSettings(tester);

      expect(find.textContaining('초기화'), findsNothing);
      expect(find.textContaining('백업'), findsNothing);
    });
  });
}

class _MemSettings implements SettingsStorage {
  _MemSettings([this.contents]);
  String? contents;
  bool failWrite = false;

  @override
  Future<String?> read() async => contents;
  @override
  Future<void> writeAtomically(String c) async {
    if (failWrite) throw StateError('쓰기 실패');
    contents = c;
  }
}

/// 수집 기록은 이 테스트의 관심사가 아니다. 빈 상태로 둔다.
class _NullCollection implements CollectionStorage {
  String? contents;

  @override
  Future<String?> read() async => contents;
  @override
  Future<void> writeAtomically(String c) async => contents = c;
  @override
  Future<String> quarantine() async => 'corrupt.json';
}
