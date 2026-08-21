import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/map_data.dart';

/// 긁기 단위 **카탈로그 버전·해시** (S3 N1 계약 5절).
///
/// 수집 레코드에 "어느 카탈로그에서 수집했는가" 를 남기려면 앱이 이 값을 알아야
/// 한다. 긁기 단위는 이미 두 번 바뀌었고(256 → 232 → 193) 출시 뒤에 또 바뀌면
/// **버전 없이는 옛 기록을 재해석할 수 없다.**
///
/// 값을 만드는 것은 `tool/map/catalog.py` 이고 등록부가 원본이다. **앱은 읽기만
/// 한다** — 두 곳에서 계산하면 조용히 갈린다. 그래서 여기서는 *계산이 맞는지* 가
/// 아니라 *제대로 읽어 오는지* 와 *서버 manifest 와 같은지* 를 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapData data;
  setUpAll(() async => data = await MapData.load());

  group('앱이 카탈로그를 읽는다', () {
    test('버전과 해시가 들어 있다', () {
      expect(data.catalogVersion, isNotEmpty);
      expect(data.catalogHash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(data.catalogHash), isTrue,
          reason: 'SHA-256 16진 문자열이 아니다: ${data.catalogHash}');
    });

    test('없거나 형식이 틀리면 실패한다', () async {
      // **"현재 에셋에 키가 있다" 만 보면 뜻이 없다.** 없을 때 정말 실패하는지는
      // 없는 값을 직접 넣어 봐야 안다 (Codex 지적).
      final raw = await rootBundle.loadString('assets/map/korea_sgg.json');
      final good = jsonDecode(raw) as Map<String, dynamic>;
      expect(readCatalog(good), (data.catalogVersion, data.catalogHash));

      Map<String, dynamic> broken(void Function(Map<String, dynamic>) f) {
        final m = Map<String, dynamic>.from(good);
        f(m);
        return m;
      }

      final cases = <String, void Function(Map<String, dynamic>)>{
        '버전 없음': (m) => m.remove('catalogVersion'),
        '버전이 빈 문자열': (m) => m['catalogVersion'] = '',
        '버전이 숫자': (m) => m['catalogVersion'] = 1,
        '해시 없음': (m) => m.remove('catalogHash'),
        // **길이만 검사하면 이게 통과한다.**
        '해시가 16진이 아님': (m) => m['catalogHash'] = 'z' * 64,
        '해시가 짧다': (m) => m['catalogHash'] = 'ab',
        '해시가 대문자': (m) => m['catalogHash'] = 'A' * 64,
      };
      for (final e in cases.entries) {
        expect(() => readCatalog(broken(e.value)), throwsStateError,
            reason: e.key);
      }
    });
  });

  group('서버 manifest 와 같다', () {
    test('버전·해시·active 집합이 일치한다', () {
      // **이것이 이 파일의 핵심이다.** 앱과 서버가 다른 카탈로그를 보면 서버가
      // 현재 ID 를 거부하거나 폐기된 ID 를 통과시킨다.
      final m = _manifest();

      expect(m['version'], data.catalogVersion);
      expect(m['hash'], data.catalogHash);

      final active = <String>{
        for (final u in m['units'] as List)
          if ((u as Map)['status'] == 'active') u['id'] as String,
      };
      final inMap = data.regions.map((r) => r.scratchUnitId).toSet();
      expect(active, inMap, reason: 'manifest 의 active 와 지도가 다르다');
    });

    test('폐지된 ID 는 지우지 않고 남긴다', () {
      // ID 를 재사용하면 과거 기록이 엉뚱한 지역으로 옮겨간다. 그래서 흡수된
      // ID 도 `retired` 로 남는다 — 2026-08-14 서울 25구·제주 2시,
      // 2026-08-20 광역시 44곳.
      final m = _manifest();
      final retired = <String>{
        for (final u in m['units'] as List)
          if ((u as Map)['status'] == 'retired') u['id'] as String,
      };
      expect(retired.length, 71);
      // 대표적으로 흡수된 것 넷.
      for (final gone in ['11680', '26350', '27140', '50110']) {
        expect(retired, contains(gone), reason: '$gone 이 사라졌다');
      }
      // **현재 지도와 겹치면 안 된다.**
      final inMap = data.regions.map((r) => r.scratchUnitId).toSet();
      expect(retired.intersection(inMap), isEmpty,
          reason: 'retired 인데 지도에도 있다');
    });
  });
}

/// 서버용 manifest. **앱 에셋이 아니다** — 앱은 버전과 해시만 알면 되고,
/// 264개 목록을 APK 에 넣을 이유가 없다. 빌드 산출물이라 파일에서 읽는다.
Map<String, dynamic> _manifest() {
  final f = File('tool/map/catalog_manifest.json');
  expect(f.existsSync(), isTrue,
      reason: 'python tool/map/catalog.py 로 만든다');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}
