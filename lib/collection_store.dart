import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'collection.dart';

/// 수집 기록의 **영속화**. 순수 모델과 직렬화는 `collection.dart` 에 있다.

/// 바이트를 다루는 최소 어댑터. 테스트는 메모리 구현으로 갈아 끼운다.
///
/// **일부러 좁게 둔다.** 넓히면 테스트용 구현이 프로덕션 로직을 복제하게 되고,
/// 본체가 바뀌어도 테스트가 통과한다(Codex 4회차에서 실제로 겪었다).
abstract class CollectionStorage {
  /// 없으면 `null`. 읽기 자체가 실패하면 예외를 던진다.
  Future<String?> read();

  /// **원자적으로 교체한다.** 중간 상태가 남으면 안 된다.
  Future<void> writeAtomically(String contents);

  /// 읽을 수 없는 파일을 **유일한 이름으로** 옮겨 보존한다.
  Future<String> quarantine();
}

/// 앱 문서 디렉토리의 파일 하나로 저장한다.
///
/// ## 왜 파일인가
///
/// **모르는 ID 도 보존하므로 행 수에 상한은 없다.** 현재 카탈로그가 193행이라 `sqflite` 는 과하고, `shared_preferences` 는 손상 파일
/// 격리·명시적 마이그레이션·내보내기를 다루기 불편하다. 파일이면 셋 다 자연스럽다.
///
/// ## 원자성의 범위
///
/// **같은 디렉토리**에 임시 파일을 쓰고(`flush: true`) `rename` 으로 교체한다.
/// 대상 파일을 먼저 지우지 않는다. 앱 강제 종료와 반쪽 JSON 은 이걸로 막힌다.
///
/// **전원 차단은 보장하지 않는다.** 순수 Dart 에는 부모 디렉토리를 `fsync` 하는
/// 수단이 없어, 물리적 전원 차단 직전의 마지막 1회 기록은 잔여 위험으로 남는다
/// (Codex 15회차). 그 수준까지 필요해지면 Android `AtomicFile` 을 네이티브로 부른다.
class FileCollectionStorage implements CollectionStorage {
  FileCollectionStorage(this.file);

  /// 앱 문서 디렉토리에 표준 이름으로 만든다.
  static Future<FileCollectionStorage> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return FileCollectionStorage(File('${dir.path}/collection.json'));
  }

  final File file;

  Directory get _dir => file.parent;

  @override
  Future<String?> read() async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeAtomically(String contents) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    // rename 은 같은 파일시스템 안에서 이름만 바꾼다. 대상이 있어도 덮어쓴다.
    await tmp.rename(file.path);
  }

  @override
  Future<String> quarantine() async {
    // **고정 이름을 쓰지 않는다.** 두 번째 손상에서 첫 번째 증거를 덮어쓴다.
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
    var n = 0;
    while (true) {
      final target = File('${_dir.path}/collection.corrupt.$stamp.$n.json');
      if (!await target.exists()) {
        await file.rename(target.path);
        return target.path;
      }
      n++;
    }
  }
}

/// 로드 결과의 상태.
enum CollectionLoadStatus {
  /// 정상. 파일이 없어 빈 상태인 것도 여기다.
  ok,

  /// 읽을 수 없어 격리했다. 빈 상태로 시작하되 사용자에게 알린다.
  quarantined,

  /// 더 새로운 버전이라 읽지 않았다. **덮어쓰면 안 된다.**
  unsupportedVersion,

  /// 읽기 I/O 가 실패했다. 원본은 그대로다. 재시도할 수 있다.
  readFailed,
}

class CollectionLoadResult {
  const CollectionLoadResult(this.status, this.snapshot,
      {this.detail, this.quarantinedPath});

  final CollectionLoadStatus status;
  final CollectionSnapshot snapshot;
  final String? detail;
  final String? quarantinedPath;

  /// 쓰기를 허용해도 되는 상태인가.
  ///
  /// 지원하지 않는 버전과 읽기 실패에서는 **쓰지 않는다** — 남의 기록을 지운다.
  bool get writable =>
      status == CollectionLoadStatus.ok ||
      status == CollectionLoadStatus.quarantined;
}

/// 수집 기록을 읽고 쓰는 작은 저장소.
///
/// 쓰기는 **직렬화**한다. 연속 완료에서 두 쓰기가 겹치면 나중 것이 앞의 것을
/// 덮어쓰거나 반쪽이 남을 수 있다.
class CollectionStore {
  CollectionStore(this._storage);

  final CollectionStorage _storage;

  CollectionSnapshot _snapshot = CollectionSnapshot.empty;
  CollectionSnapshot get snapshot => _snapshot;

  bool _writable = false;
  bool get writable => _writable;

  /// 진행 중인 쓰기. 실패해도 큐가 막히지 않도록 **오류를 삼킨 꼬리**를 잇는다.
  Future<void> _tail = Future.value();

  Future<CollectionLoadResult> load() async {
    String? raw;
    try {
      raw = await _storage.read();
    } catch (e) {
      _writable = false;
      return CollectionLoadResult(
          CollectionLoadStatus.readFailed, CollectionSnapshot.empty,
          detail: '$e');
    }

    if (raw == null) {
      _snapshot = CollectionSnapshot.empty;
      _writable = true;
      return CollectionLoadResult(CollectionLoadStatus.ok, _snapshot);
    }

    try {
      _snapshot = decodeCollection(raw);
      _writable = true;
      return CollectionLoadResult(CollectionLoadStatus.ok, _snapshot);
    } on UnsupportedCollectionVersionException catch (e) {
      // 격리하지 않는다. 구버전 앱이 최신 기록을 지우면 안 된다.
      _writable = false;
      return CollectionLoadResult(
          CollectionLoadStatus.unsupportedVersion, CollectionSnapshot.empty,
          detail: '$e');
    } on CollectionFormatException catch (e) {
      try {
        final path = await _storage.quarantine();
        _snapshot = CollectionSnapshot.empty;
        _writable = true;
        return CollectionLoadResult(
            CollectionLoadStatus.quarantined, _snapshot,
            detail: '$e', quarantinedPath: path);
      } catch (q) {
        // 격리조차 못 했으면 **새 파일을 쓰지 않는다.** 원본을 덮어쓸 위험이 있다.
        _writable = false;
        return CollectionLoadResult(
            CollectionLoadStatus.readFailed, CollectionSnapshot.empty,
            detail: '격리 실패: $q (원인: $e)');
      }
    }
  }

  /// [unit] 을 기록한다. **저장에 성공해야 스냅샷이 바뀐다.**
  ///
  /// 메모리에만 반영하고 저장이 실패하면 재시작 때 조용히 사라진다.
  Future<CollectionSnapshot> collect(CollectedUnit unit) async {
    if (!_writable) {
      throw StateError('지금은 쓸 수 없는 상태다 (load 결과를 확인할 것)');
    }
    // **큐 밖에서 중복을 걸러내지 않는다.**
    //
    // 그러면 앞서 큐에 들어간 쓰기를 기다리지 않고 **옛 스냅샷을 돌려주게 된다**
    // (Codex 16회차). 중복 검사도 큐 안에서 최신 상태를 보고 한다.
    final done = Completer<CollectionSnapshot>();
    _tail = _tail.then((_) async {
      try {
        // **다음 스냅샷을 큐 안에서 만든다.**
        //
        // 호출 시점에 미리 계산하면 앞선 쓰기가 반영되기 전의 상태를 기준으로
        // 삼게 되어, 연속 수집에서 **나중 것이 앞의 것을 덮어쓴다.** 테스트가
        // 실제로 이걸 잡았다.
        if (_snapshot.contains(unit.scratchUnitId)) {
          done.complete(_snapshot);
          return;
        }
        final next = _snapshot.collect(unit);
        await _storage.writeAtomically(encodeCollection(next));
        _snapshot = next;
        done.complete(next);
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    // 꼬리에는 오류를 남기지 않는다 — 한 번 실패하면 이후 쓰기가 전부 막힌다.
    _tail = _tail.catchError((_) {});
    return done.future;
  }

  /// [scratchUnitId] 의 메모를 바꾼다. 비우면 지운다. **저장에 성공해야 반영된다.**
  ///
  /// `collect` 와 **같은 큐**를 쓴다. 다른 큐로 두면 메모 저장과 수집 저장이
  /// 서로의 결과를 덮어쓴다. 다음 스냅샷도 마찬가지로 큐 안에서 만든다 —
  /// 호출 시점에 계산하면 앞선 쓰기가 반영되기 전 상태를 기준으로 삼는다.
  Future<CollectionSnapshot> setMemo(String scratchUnitId, String? memo) async {
    if (!_writable) {
      throw StateError('지금은 쓸 수 없는 상태다 (load 결과를 확인할 것)');
    }
    final done = Completer<CollectionSnapshot>();
    _tail = _tail.then((_) async {
      try {
        final next = _snapshot.setMemo(scratchUnitId, memo);
        // 값이 그대로면 쓰지 않는다. 같은 메모로 저장을 눌러도 디스크를 건드리지 않는다.
        if (identical(next, _snapshot)) {
          done.complete(_snapshot);
          return;
        }
        await _storage.writeAtomically(encodeCollection(next));
        _snapshot = next;
        done.complete(next);
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    _tail = _tail.catchError((_) {});
    return done.future;
  }

  @visibleForTesting
  set snapshotForTest(CollectionSnapshot s) => _snapshot = s;

  @visibleForTesting
  set writableForTest(bool v) => _writable = v;
}
