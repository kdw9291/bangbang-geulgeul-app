import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/collection.dart';
import 'package:mapscratch/collection_store.dart';

/// M1 긁은 기록 영구 저장.
///
/// 저장 계층은 **눈으로 확인할 수 없는 실패**가 많다 — 반쪽 파일, 조용한 손실,
/// 큐 막힘. 그래서 방어선을 테스트로 못 박는다.

CollectedUnit _u(String id, String iso, {int offset = 540, String? memo}) =>
    CollectedUnit(
      scratchUnitId: id,
      collectedAtUtc: DateTime.parse(iso).toUtc(),
      utcOffsetMinutes: offset,
      memo: memo,
    );

/// 바이트만 흉내 내는 저장소. **파싱·직렬화는 프로덕션 코드를 그대로 쓴다.**
class _MemStorage implements CollectionStorage {
  _MemStorage([this.contents]);

  String? contents;
  final quarantined = <String>[];

  bool failRead = false;
  bool failWrite = false;
  bool failQuarantine = false;
  int writes = 0;

  /// 쓰기가 완료되기 전에 붙잡아 두는 문. 직렬화 검증에 쓴다.
  Completer<void>? gate;

  @override
  Future<String?> read() async {
    if (failRead) throw const FileSystemException('읽기 실패');
    return contents;
  }

  @override
  Future<void> writeAtomically(String c) async {
    if (gate != null) await gate!.future;
    writes++;
    // **실패해도 기존 내용을 건드리지 않는다.** 실제 rename 도 그렇다.
    if (failWrite) throw const FileSystemException('쓰기 실패');
    contents = c;
  }

  @override
  Future<String> quarantine() async {
    if (failQuarantine) throw const FileSystemException('격리 실패');
    quarantined.add(contents!);
    contents = null;
    return 'corrupt-${quarantined.length}';
  }
}

void main() {
  group('codec', () {
    test('빈 상태를 쓰고 다시 읽는다', () {
      final s = decodeCollection(encodeCollection(CollectionSnapshot.empty));
      expect(s.isEmpty, isTrue);
    });

    test('왕복해도 값이 보존된다 — 메모의 한글·이모지 포함', () {
      final before = CollectionSnapshot.empty
          .collect(_u('47130', '2026-08-14T12:00:00Z', memo: '첨성대 봤다 🌌'))
          .collect(_u('DK001', '2026-08-15T01:30:00Z', offset: -300));
      final after = decodeCollection(encodeCollection(before));

      expect(after.length, 2);
      expect(after['47130'], before['47130']);
      expect(after['DK001'], before['DK001']);
      expect(after['47130']!.memo, '첨성대 봤다 🌌');
      expect(after['DK001']!.utcOffsetMinutes, -300);
    });

    test('출력이 결정적이다 — 넣은 순서가 달라도 같은 문자열', () {
      final a = CollectionSnapshot.empty
          .collect(_u('47130', '2026-08-14T12:00:00Z'))
          .collect(_u('11000', '2026-08-13T12:00:00Z'));
      final b = CollectionSnapshot.empty
          .collect(_u('11000', '2026-08-13T12:00:00Z'))
          .collect(_u('47130', '2026-08-14T12:00:00Z'));
      expect(encodeCollection(a), encodeCollection(b));
    });

    test('v1 에 memo 자리가 있다', () {
      // 없으면 M5 가 memo 를 추가한 뒤 구버전 앱이 읽고 다시 쓸 때
      // 메모가 조용히 사라진다 (Codex 15회차).
      final json = jsonDecode(encodeCollection(
          CollectionSnapshot.empty.collect(_u('47130', '2026-08-14T12:00:00Z'))));
      expect((json['units'] as List).first, contains('memo'));
      expect(json['version'], kCollectionVersion);
    });

    test('수집 날짜는 지금 기기가 아니라 수집 당시 오프셋으로 푼다', () {
      // 한국에서 8월 15일 00:30 에 수집 → UTC 로는 8월 14일 15:30.
      // 오프셋을 안 쓰면 다른 시간대에서 하루 어긋난다.
      final u = _u('47130', '2026-08-14T15:30:00Z', offset: 540);
      expect(u.localDate, DateTime(2026, 8, 15));
    });

    test('같은 ID 가 두 번 있으면 먼저 수집한 쪽을 남긴다', () {
      final raw = jsonEncode({
        'version': 1,
        'units': [
          {
            'scratchUnitId': '47130',
            'collectedAtUtc': '2026-08-20T00:00:00.000Z',
            'utcOffsetMinutes': 540,
            'memo': null,
          },
          {
            'scratchUnitId': '47130',
            'collectedAtUtc': '2026-08-14T00:00:00.000Z',
            'utcOffsetMinutes': 540,
            'memo': null,
          },
        ],
      });
      expect(decodeCollection(raw)['47130']!.collectedAtUtc,
          DateTime.parse('2026-08-14T00:00:00.000Z'));
    });

    test('이미 수집한 지역을 다시 넣어도 최초 시각이 유지된다', () {
      final s = CollectionSnapshot.empty
          .collect(_u('47130', '2026-08-14T00:00:00Z'))
          .collect(_u('47130', '2026-08-20T00:00:00Z'));
      expect(s['47130']!.collectedAtUtc, DateTime.parse('2026-08-14T00:00:00Z'));
      expect(s.length, 1);
    });

    test('한 행이라도 깨지면 전체가 오류다 — 조용히 버리지 않는다', () {
      // 일부만 버리면 사용자는 기록이 줄어든 것을 알아차리지 못한다.
      final raw = jsonEncode({
        'version': 1,
        'units': [
          {
            'scratchUnitId': '47130',
            'collectedAtUtc': '2026-08-14T00:00:00.000Z',
            'utcOffsetMinutes': 540,
          },
          {'scratchUnitId': '', 'collectedAtUtc': 'x', 'utcOffsetMinutes': 540},
        ],
      });
      expect(() => decodeCollection(raw),
          throwsA(isA<CollectionFormatException>()));
    });

    test('망가진 형태들을 거부한다', () {
      for (final raw in [
        '{',
        '[]',
        '{"units":[]}',
        '{"version":"1","units":[]}',
        '{"version":1}',
        '{"version":1,"units":{}}',
        '{"version":0,"units":[]}',
      ]) {
        expect(() => decodeCollection(raw),
            throwsA(isA<CollectionFormatException>()),
            reason: raw);
      }
    });

    test('시간대 없는 시각 문자열은 거부한다', () {
      // `DateTime.parse` 는 이런 문자열을 **기기의 로컬 시간대**로 읽는다.
      // 그대로 두면 같은 파일이 기기마다 다른 순간을 가리킨다.
      final raw = jsonEncode({
        'version': 1,
        'units': [
          {
            'scratchUnitId': '47130',
            'collectedAtUtc': '2026-08-14T12:00:00',
            'utcOffsetMinutes': 540,
            'memo': null,
          },
        ],
      });
      expect(() => decodeCollection(raw),
          throwsA(isA<CollectionFormatException>()));
    });

    test('명시적 오프셋이 붙은 시각은 UTC 로 정규화한다', () {
      final raw = jsonEncode({
        'version': 1,
        'units': [
          {
            'scratchUnitId': '47130',
            'collectedAtUtc': '2026-08-15T00:30:00+09:00',
            'utcOffsetMinutes': 540,
            'memo': null,
          },
        ],
      });
      final u = decodeCollection(raw)['47130']!;
      expect(u.collectedAtUtc.isUtc, isTrue);
      expect(u.collectedAtUtc, DateTime.parse('2026-08-14T15:30:00Z'));
    });

    test('더 새로운 버전은 손상이 아니라 별도 오류다', () {
      expect(
          () => decodeCollection('{"version":99,"units":[]}'),
          throwsA(isA<UnsupportedCollectionVersionException>()));
    });
  });

  group('알 수 없는 ID', () {
    const catalog = ['47130', '11000'];

    test('화면용 집합에서는 빠진다', () {
      final s = CollectionSnapshot.empty
          .collect(_u('47130', '2026-08-14T00:00:00Z'))
          .collect(_u('99999', '2026-08-14T00:00:00Z'));
      expect(s.idsIn(catalog), {'47130'});
      expect(s.unknownIds(catalog), {'99999'});
    });

    test('로드 → 새 기록 추가 → 재저장 후에도 보존된다', () async {
      // 행정구역 개편이나 통합 롤백에서 실제로 생긴다. 버리면 사용자 기록이
      // 조용히 사라진다.
      final storage = _MemStorage(encodeCollection(CollectionSnapshot.empty
          .collect(_u('99999', '2026-08-01T00:00:00Z'))));
      final store = CollectionStore(storage);
      await store.load();

      await store.collect(_u('47130', '2026-08-14T00:00:00Z'));

      final reread = decodeCollection(storage.contents!);
      expect(reread.contains('99999'), isTrue, reason: '알 수 없는 ID 가 사라졌다');
      expect(reread.contains('47130'), isTrue);
    });
  });

  group('CollectionStore 로드', () {
    test('파일이 없으면 빈 상태이고 쓸 수 있다', () async {
      final store = CollectionStore(_MemStorage());
      final r = await store.load();
      expect(r.status, CollectionLoadStatus.ok);
      expect(r.writable, isTrue);
      expect(store.snapshot.isEmpty, isTrue);
    });

    test('손상 파일은 격리하고 빈 상태로 시작한다', () async {
      final storage = _MemStorage('깨진 내용');
      final store = CollectionStore(storage);
      final r = await store.load();

      expect(r.status, CollectionLoadStatus.quarantined);
      expect(r.writable, isTrue);
      expect(storage.quarantined.single, '깨진 내용', reason: '원본을 보존해야 한다');
    });

    test('격리조차 실패하면 쓰지 않는다', () async {
      // 원본이 그대로 남아 있는데 새 파일을 쓰면 사용자 기록을 덮어쓴다.
      final storage = _MemStorage('깨진 내용')..failQuarantine = true;
      final store = CollectionStore(storage);
      final r = await store.load();

      expect(r.writable, isFalse);
      expect(storage.contents, '깨진 내용');
    });

    test('더 새로운 버전은 격리하지 않고 쓰기를 막는다', () async {
      // 구버전 앱이 최신 앱의 기록을 지우면 안 된다.
      final storage = _MemStorage('{"version":99,"units":[]}');
      final store = CollectionStore(storage);
      final r = await store.load();

      expect(r.status, CollectionLoadStatus.unsupportedVersion);
      expect(r.writable, isFalse);
      expect(storage.quarantined, isEmpty);
      expect(storage.contents, '{"version":99,"units":[]}');
    });

    test('읽기 I/O 실패는 원본을 건드리지 않는다', () async {
      final storage = _MemStorage('원본')..failRead = true;
      final store = CollectionStore(storage);
      final r = await store.load();

      expect(r.status, CollectionLoadStatus.readFailed);
      expect(r.writable, isFalse);
      expect(storage.contents, '원본');
      expect(storage.quarantined, isEmpty);
    });

    test('쓸 수 없는 상태에서 collect 하면 예외가 난다', () async {
      final store = CollectionStore(_MemStorage('{"version":99,"units":[]}'));
      await store.load();
      expect(() => store.collect(_u('47130', '2026-08-14T00:00:00Z')),
          throwsA(isA<StateError>()));
    });
  });

  group('CollectionStore 쓰기', () {
    test('저장에 실패하면 스냅샷이 바뀌지 않는다', () async {
      // 메모리에만 반영하면 재시작 때 조용히 사라진다.
      final storage = _MemStorage()..failWrite = true;
      final store = CollectionStore(storage);
      await store.load();

      await expectLater(store.collect(_u('47130', '2026-08-14T00:00:00Z')),
          throwsA(isA<FileSystemException>()));
      expect(store.snapshot.isEmpty, isTrue);
      expect(storage.contents, isNull);
    });

    test('첫 쓰기가 실패해도 다음 쓰기가 실행된다', () async {
      // 실패한 Future 를 큐 꼬리에 그대로 두면 이후 쓰기가 전부 막힌다.
      final storage = _MemStorage()..failWrite = true;
      final store = CollectionStore(storage);
      await store.load();

      await expectLater(store.collect(_u('47130', '2026-08-14T00:00:00Z')),
          throwsA(isA<FileSystemException>()));

      storage.failWrite = false;
      await store.collect(_u('11000', '2026-08-15T00:00:00Z'));

      expect(store.snapshot.contains('11000'), isTrue);
      expect(storage.contents, isNotNull);
    });

    test('재시도해도 같은 수집 시각을 쓴다', () async {
      final storage = _MemStorage()..failWrite = true;
      final store = CollectionStore(storage);
      await store.load();
      final unit = _u('47130', '2026-08-14T00:00:00Z');

      await expectLater(store.collect(unit), throwsA(anything));
      storage.failWrite = false;
      await store.collect(unit);

      expect(store.snapshot['47130']!.collectedAtUtc,
          DateTime.parse('2026-08-14T00:00:00Z'));
    });

    test('연속 수집 둘이 최종 파일에 모두 남는다', () async {
      // 쓰기가 겹치면 나중 것이 앞의 것을 덮어써 하나가 사라질 수 있다.
      final storage = _MemStorage();
      final store = CollectionStore(storage);
      await store.load();

      final gate = Completer<void>();
      storage.gate = gate;
      final a = store.collect(_u('47130', '2026-08-14T00:00:00Z'));
      final b = store.collect(_u('11000', '2026-08-15T00:00:00Z'));
      gate.complete();
      await Future.wait([a, b]);

      final saved = decodeCollection(storage.contents!);
      expect(saved.contains('47130'), isTrue);
      expect(saved.contains('11000'), isTrue);
      expect(storage.writes, 2);
    });

    test('중복 수집도 앞선 쓰기를 기다린 뒤 최신 스냅샷을 준다', () async {
      // 큐 밖에서 중복을 걸러내면 **앞서 큐에 들어간 쓰기를 기다리지 않고
      // 옛 스냅샷을 돌려준다** (Codex 16회차).
      final storage = _MemStorage(encodeCollection(
          CollectionSnapshot.empty.collect(_u('47130', '2026-08-01T00:00:00Z'))));
      final store = CollectionStore(storage);
      await store.load();

      final gate = Completer<void>();
      storage.gate = gate;
      final first = store.collect(_u('11000', '2026-08-14T00:00:00Z'));
      final dup = store.collect(_u('47130', '2026-08-20T00:00:00Z'));
      gate.complete();

      await first;
      final got = await dup;
      expect(got.contains('11000'), isTrue,
          reason: '먼저 호출된 수집이 빠진 스냅샷을 돌려줬다');
      expect(got['47130']!.collectedAtUtc,
          DateTime.parse('2026-08-01T00:00:00Z'));
    });

    test('이미 수집한 지역은 다시 쓰지 않는다', () async {
      final storage = _MemStorage();
      final store = CollectionStore(storage);
      await store.load();
      await store.collect(_u('47130', '2026-08-14T00:00:00Z'));
      expect(storage.writes, 1);

      await store.collect(_u('47130', '2026-08-20T00:00:00Z'));
      expect(storage.writes, 1, reason: '중복 수집은 쓰기를 만들지 않는다');
    });
  });

  group('FileCollectionStorage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mapscratch_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('원자적으로 교체하고 임시 파일을 남기지 않는다', () async {
      final file = File('${dir.path}/collection.json');
      final s = FileCollectionStorage(file);

      await s.writeAtomically('첫 번째');
      expect(await s.read(), '첫 번째');

      await s.writeAtomically('두 번째');
      expect(await s.read(), '두 번째');

      final leftovers = dir
          .listSync()
          .map((e) => e.path)
          .where((p) => p.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty, reason: '임시 파일이 남았다');
    });

    test('없는 파일은 null 이다', () async {
      final s = FileCollectionStorage(File('${dir.path}/none.json'));
      expect(await s.read(), isNull);
    });

    test('격리는 원본을 유일한 이름으로 옮긴다', () async {
      final file = File('${dir.path}/collection.json');
      final s = FileCollectionStorage(file);

      await s.writeAtomically('깨진 1');
      final p1 = await s.quarantine();
      expect(await file.exists(), isFalse);
      expect(File(p1).readAsStringSync(), '깨진 1');

      await s.writeAtomically('깨진 2');
      final p2 = await s.quarantine();
      expect(p2, isNot(p1), reason: '두 번째 손상이 첫 증거를 덮어쓰면 안 된다');
      expect(File(p1).readAsStringSync(), '깨진 1');
      expect(File(p2).readAsStringSync(), '깨진 2');
    });

    test('쓰기가 실패해도 기존 파일이 남는다', () async {
      final file = File('${dir.path}/collection.json');
      final s = FileCollectionStorage(file);
      await s.writeAtomically('원본');

      // 임시 파일 경로를 디렉토리로 막아 rename 을 실패시킨다.
      Directory('${file.path}.tmp').createSync();
      await expectLater(s.writeAtomically('새 내용'), throwsA(anything));

      expect(await s.read(), '원본');
    });
  });
}
