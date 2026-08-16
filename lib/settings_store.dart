import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'settings.dart';

/// 설정의 **영속화**. 순수 모델과 직렬화는 `settings.dart` 에 있다.

/// 바이트만 다루는 최소 어댑터. 테스트는 메모리 구현으로 갈아 끼운다.
abstract class SettingsStorage {
  /// 없으면 `null`. 읽기 실패도 `null` 로 본다 — 설정은 없어도 앱이 돈다.
  Future<String?> read();

  Future<void> writeAtomically(String contents);
}

/// 앱 문서 디렉토리의 `settings.json`.
///
/// **`collection_store.dart` 의 원자 쓰기를 공통화하지 않았다.** 기계 부분은
/// 몇 줄뿐이고, M1 의 실질적인 복잡성은 직렬화·격리·미래 버전 차단이라
/// 설정과 공유할 것이 아니다. 두 번째 사용처 하나 때문에 이미 테스트로 덮인
/// M1 경로를 다시 여는 이득이 작다(Codex 22회차). 세 번째가 생기면 그때 뺀다.
class FileSettingsStorage implements SettingsStorage {
  FileSettingsStorage(this.file);

  static Future<FileSettingsStorage> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return FileSettingsStorage(File('${dir.path}/settings.json'));
  }

  final File file;

  @override
  Future<String?> read() async {
    try {
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      debugPrint('[SETTINGS] 읽기 실패 — 기본값으로 시작한다: $e');
      return null;
    }
  }

  @override
  Future<void> writeAtomically(String contents) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }
}

/// 설정을 읽고 쓰는 작은 저장소.
///
/// 쓰기는 **직렬화한다.** 테마를 빠르게 연속으로 누르면 쓰기가 역순으로 끝나
/// **마지막에 고른 것이 파일에 안 남을 수 있다**(Codex 22회차).
class SettingsStore {
  SettingsStore(this._storage);

  final SettingsStorage _storage;

  AppSettings _current = AppSettings.defaults;
  AppSettings get current => _current;

  /// 저장 파일이 깨져 기본값으로 시작했는가. 화면이 알릴지 판단한다.
  bool _recovered = false;
  bool get recovered => _recovered;

  Future<void> _tail = Future.value();

  /// 읽어서 현재 값을 채운다. **예외를 던지지 않는다.**
  Future<AppSettings> load() async {
    final raw = await _storage.read();
    if (raw == null) {
      _current = AppSettings.defaults;
      return _current;
    }
    final parsed = decodeSettings(raw);
    // **손상돼도 곧바로 덮어쓰지 않는다.** 메모리에서 기본값을 쓰고,
    // 사용자가 다음에 고를 때 그 값으로 덮인다(Codex 22회차).
    _recovered = parsed == AppSettings.defaults && !_looksDefault(raw);
    _current = parsed;
    return _current;
  }

  /// 원본이 "기본값을 그대로 적어 둔 정상 파일" 인지. 그렇다면 복구가 아니다.
  bool _looksDefault(String raw) => raw == encodeSettings(AppSettings.defaults);

  /// 바다를 바꾼다. **메모리는 곧바로 바뀌고 저장은 뒤따른다.**
  ///
  /// 수집 기록과 반대다 — 거기서는 저장에 성공해야 반영했다. 설정은 화면이
  /// 즉시 반응하는 편이 낫고, 실패해도 잃는 것이 취향 하나다. 실패는
  /// 예외로 올려 호출부가 "이번 선택은 저장되지 않았다" 고 알리게 한다.
  Future<AppSettings> setSea(String seaName) {
    final next = _current.withSea(seaName);
    _current = next;

    final done = Completer<AppSettings>();
    _tail = _tail.then((_) async {
      try {
        await _storage.writeAtomically(encodeSettings(next));
        done.complete(next);
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    // 한 번 실패해도 다음 쓰기가 막히지 않게 꼬리에는 오류를 남기지 않는다.
    _tail = _tail.catchError((_) {});
    return done.future;
  }

  @visibleForTesting
  set currentForTest(AppSettings s) => _current = s;
}
