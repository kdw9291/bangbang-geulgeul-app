import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_theme.dart';
import 'package:mapscratch/map_data.dart';
import 'package:mapscratch/region_search.dart';
import 'package:mapscratch/search_sheet.dart';

/// M3 검색 시트. 순수 매칭은 `region_search_test.dart` 가 본다.
///
/// 여기서 막는 것은 **화면이 결과를 잘못 보여주는 일**이다 —
/// 동명 지역을 구분 못 하게 하거나, 고른 것을 돌려주지 않거나.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  late RegionSearcher searcher;
  setUpAll(() async {
    data = await MapData.load();
    searcher = RegionSearcher(data);
  });

  Region? picked;

  Widget wrap({Set<String> scratched = const {}}) {
    picked = null;
    return AppThemeScope(
      theme: kThemeLight,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showModalBottomSheet<Region>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      SearchSheet(searcher: searcher, scratched: scratched),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    Set<String> scratched = const {},
  }) async {
    await tester.pumpWidget(wrap(scratched: scratched));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pumpAndSettle();
  }

  testWidgets('처음에는 안내만 보이고 결과가 없다', (tester) async {
    await open(tester);
    expect(find.textContaining('초성만 쳐도'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('초성으로 치면 결과가 나온다', (tester) async {
    await open(tester);
    await type(tester, 'ㅅㅊ');

    // 첫 화면에 보이는 것부터 전부 초성이 맞아야 한다.
    expect(find.text('사천시'), findsOneWidget);

    // `ㅅㅊ` 는 여러 곳이 걸리므로 순천시는 목록 아래에 있다.
    // **스크롤해서 닿는지**까지 봐야 검색이 쓸모 있다고 할 수 있다.
    await tester.scrollUntilVisible(
      find.text('순천시'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('순천시'), findsOneWidget);
  });

  testWidgets('고른 지역을 돌려준다', (tester) async {
    await open(tester);
    await type(tester, '경주');
    await tester.tap(find.text('경주시'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.name, '경주시');
  });

  testWidgets('동명 지역은 시도명을 함께 보여준다', (tester) async {
    // 시도명이 없으면 `고성군` 두 곳 중 어디인지 고를 수 없다.
    // (2026-08-20 광역시 통합 전에는 `중구` 여섯 곳으로 검사했다.)
    await open(tester);
    await type(tester, '고성군');

    final rows = find.byType(ListTile);
    expect(tester.widgetList(rows).length, greaterThan(1));
    // 각 행에 서로 다른 시도명이 붙어 있어야 한다.
    expect(find.text('강원특별자치도'), findsOneWidget);
    expect(find.text('경상남도'), findsOneWidget);
  });

  testWidgets('지역명과 시도명이 같으면 한 번만 쓴다', (tester) async {
    // 통합 단위는 이름이 시도명과 같다. 그대로 이으면 "서울특별시 서울특별시".
    await open(tester);
    await type(tester, '서울');
    expect(find.text('서울특별시'), findsOneWidget);
  });

  testWidgets('수집한 지역에 표시가 붙는다', (tester) async {
    await open(tester, scratched: {'47130'}); // 경주시
    await type(tester, '경주');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('수집하지 않았으면 표시가 없다', (tester) async {
    await open(tester);
    await type(tester, '경주');
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('결과 개수를 항상 보여준다', (tester) async {
    // 조용히 자르면 찾는 곳이 없는 것인지 잘린 것인지 알 수 없다.
    await open(tester);
    await type(tester, '경주');
    expect(find.textContaining('곳'), findsWidgets);
  });

  testWidgets('결과가 많으면 좁히는 법을 안내한다', (tester) async {
    await open(tester);
    await type(tester, '시');
    expect(find.textContaining('시도 이름을 함께'), findsOneWidget);
  });

  testWidgets('결과가 적으면 안내를 띄우지 않는다', (tester) async {
    await open(tester);
    await type(tester, '경주시');
    expect(find.textContaining('시도 이름을 함께'), findsNothing);
  });

  testWidgets('없는 이름은 없다고 알린다', (tester) async {
    await open(tester);
    await type(tester, '없는지역이름');
    expect(find.text('찾는 지역이 없습니다.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('자음과 모음이 떨어져 있으면 그렇게 알린다', (tester) async {
    // 그냥 "없습니다" 라고만 하면 사용자는 빠져나올 방법을 모른다.
    // IME 조합이 끊긴 실제 상태다 (2026-08-15 실기기에서 재현).
    await open(tester);
    await type(tester, 'ㅅㅓ');
    expect(find.textContaining('자음과 모음이 떨어져'), findsOneWidget);
    expect(find.text('찾는 지역이 없습니다.'), findsNothing);
  });

  testWidgets('지우면 안내로 돌아간다', (tester) async {
    await open(tester);
    await type(tester, '경주');
    expect(find.byType(ListTile), findsWidgets);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.textContaining('초성만 쳐도'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
