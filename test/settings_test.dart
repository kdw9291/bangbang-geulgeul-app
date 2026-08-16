import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/settings.dart';
import 'package:mapscratch/settings_store.dart';

/// M12 설정 저장.
///
/// **수집 기록과 실패 정책이 다르다는 것**이 여기서 검증할 핵심이다.
/// 설정은 깨져도 앱이 돌아야 하고, 격리하거나 쓰기를 막지 않는다.
class _MemStorage implements SettingsStorage {
  _MemStorage([this.contents]);

  String? contents;
  int writes = 0;
  bool failWrite = false;
  bool failRead = false;
  Completer<void>? gate;

  /// 쓰기마다 다른 지연을 준다. **앞선 쓰기를 더 느리게** 만들어야
  /// 직렬화가 없을 때 순서가 뒤집히는 것이 드러난다.
  final List<Duration> delays = [];

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('읽기 실패');
    return contents;
  }

  @override
  Future<void> writeAtomically(String c) async {
    if (gate != null) await gate!.future;
    if (delays.isNotEmpty) await Future<void>.delayed(delays.removeAt(0));
    writes++;
    if (failWrite) throw StateError('쓰기 실패');
    contents = c;
  }
}

void main() {
  group('codec', () {
    test('왕복한다', () {
      const s = AppSettings(seaName: 'deep');
      expect(decodeSettings(encodeSettings(s)), s);
    });

    test('읽을 수 없으면 기본값이다 — 예외를 던지지 않는다', () {
      // 수집 기록은 여기서 던지고 격리한다. 설정은 취향 하나라 그럴 이유가 없다.
      expect(decodeSettings('{'), AppSettings.defaults);
      expect(decodeSettings('[]'), AppSettings.defaults);
      expect(decodeSettings('"문자열"'), AppSettings.defaults);
      expect(decodeSettings('{"version":0,"seaName":"deep"}'),
          AppSettings.defaults);
    });

    test('모르는 팔레트 이름은 기본값으로 떨어진다', () {
      expect(decodeSettings('{"version":1,"seaName":"무지개"}').seaName,
          kDefaultSeaName);
    });

    test('flat 은 고를 수 없다', () {
      // 성능 측정용(`--dart-define=SEA=flat`)이라 저장 값으로 들어오면 안 된다.
      expect(kSelectableSeaNames.contains('flat'), isFalse);
      expect(decodeSettings('{"version":1,"seaName":"flat"}').seaName,
          kDefaultSeaName);
    });

    test('더 새로운 버전이라도 막지 않는다', () {
      // 수집 기록은 여기서 쓰기를 막는다. 설정은 덮어써도 잃는 것이 취향 하나다.
      final raw = jsonEncode({'version': 99, 'seaName': 'sunset'});
      expect(decodeSettings(raw).seaName, 'sunset');
    });

    test('고를 수 있는 이름이 셋이다', () {
      expect(kSelectableSeaNames, ['cerulean', 'sunset', 'deep']);
    });
  });

  group('SettingsStore', () {
    test('파일이 없으면 기본값이다', () async {
      final store = SettingsStore(_MemStorage());
      expect((await store.load()).seaName, kDefaultSeaName);
      expect(store.recovered, isFalse);
    });

    test('읽기가 실패해도 기본값으로 뜬다', () async {
      // 설정을 못 읽었다고 앱이 안 뜨면 안 된다.
      final store = SettingsStore(_MemStorage()..failRead = true);
      await expectLater(store.load(), throwsA(anything));
      expect(store.current, AppSettings.defaults);
    });

    test('손상된 파일을 곧바로 덮어쓰지 않는다', () async {
      // 메모리에서만 기본값을 쓰고, 사용자가 다음에 고를 때 덮인다 (Codex 22회차).
      final storage = _MemStorage('깨진 내용');
      final store = SettingsStore(storage);

      await store.load();
      expect(store.current, AppSettings.defaults);
      expect(store.recovered, isTrue);
      expect(storage.writes, 0, reason: '손상 파일을 자동으로 덮어썼다');
      expect(storage.contents, '깨진 내용');
    });

    test('기본값이 적힌 정상 파일은 복구가 아니다', () async {
      final storage = _MemStorage(encodeSettings(AppSettings.defaults));
      final store = SettingsStore(storage);
      await store.load();
      expect(store.recovered, isFalse);
    });

    test('고르면 저장된다', () async {
      final storage = _MemStorage();
      final store = SettingsStore(storage);
      await store.load();

      await store.setSea('deep');
      expect(store.current.seaName, 'deep');
      expect(decodeSettings(storage.contents!).seaName, 'deep');
    });

    test('저장이 실패해도 화면 값은 바뀐 채로 둔다', () async {
      // 수집 기록과 반대다. 실패는 예외로 올려 호출부가 알리게 한다.
      final storage = _MemStorage()..failWrite = true;
      final store = SettingsStore(storage);
      await store.load();

      await expectLater(store.setSea('sunset'), throwsA(anything));
      expect(store.current.seaName, 'sunset');

      // 큐가 막히지 않아 다음 선택이 저장된다.
      storage.failWrite = false;
      await store.setSea('deep');
      expect(decodeSettings(storage.contents!).seaName, 'deep');
    });

    test('빠르게 연속으로 고르면 마지막 것이 파일에 남는다', () async {
      // 직렬화하지 않으면 쓰기가 역순으로 끝나 **마지막 선택이 사라진다**
      // (Codex 22회차).
      // **앞선 쓰기를 더 느리게 만든다.** 둘을 같은 속도로 두면 직렬화가
      // 없어도 우연히 순서가 맞아 통과한다 — 처음 쓴 테스트가 그랬다.
      final storage = _MemStorage()
        ..delays.addAll(const [Duration(milliseconds: 60), Duration.zero]);
      final store = SettingsStore(storage);
      await store.load();

      final a = store.setSea('sunset');
      final b = store.setSea('deep');
      await Future.wait([a, b]);

      expect(decodeSettings(storage.contents!).seaName, 'deep',
          reason: '앞선 쓰기가 나중 선택을 덮어썼다');
      expect(store.current.seaName, 'deep');
    });
  });
}
