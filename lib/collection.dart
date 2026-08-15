import 'dart:convert';

/// 수집 기록의 **순수 모델과 직렬화**. 파일 I/O 는 `collection_store.dart` 에 있다.
///
/// 둘을 나눈 이유는 테스트가 프로덕션 로직을 복제하지 않게 하기 위해서다 —
/// `ScratchProgress` 를 순수 클래스로 뽑았던 것과 같다(Codex 4회차). 테스트용
/// 메모리 저장소는 **문자열 읽기와 원자적 교체만 흉내 내고**, 파싱·병합·직렬화는
/// 반드시 이 파일의 코드를 통과한다.

/// 저장 스키마 버전. **의미 있는 영속 필드를 더하거나 바꾸면 올린다.**
const int kCollectionVersion = 1;

/// 수집한 긁기 단위 하나.
class CollectedUnit {
  const CollectedUnit({
    required this.scratchUnitId,
    required this.collectedAtUtc,
    required this.utcOffsetMinutes,
    this.memo,
  });

  /// 긁기 단위 식별자. **불투명 ID 로 다룬다** — 자릿수나 접미사를 해석하지 않는다.
  final String scratchUnitId;

  /// 수집 시각(UTC). 서버 동기화와 순서 비교에는 절대 시각이 필요하다.
  final DateTime collectedAtUtc;

  /// **수집 당시** 기기의 UTC 오프셋(분).
  ///
  /// UTC 만으로는 "수집 날짜" 를 복원할 수 없다. 한국에서 8월 15일 00:30 에 수집한
  /// 기록은 UTC 로 8월 14일 15:30 이라, 다른 시간대에서 보면 날짜가 하루 어긋난다.
  /// 여행 앱이라 시간대 이동이 실제로 잦으므로 오프셋을 함께 남긴다.
  final int utcOffsetMinutes;

  /// 수집 후 남기는 짧은 한 줄. **입력 UI 는 M5 에서 만든다.**
  ///
  /// M1 이 이 필드를 읽고 그대로 다시 쓰는 이유는, 없이 두면 M5 가 쓴 파일을
  /// 구버전 앱이 읽고 다시 쓸 때 메모가 조용히 사라지기 때문이다(Codex 15회차).
  final String? memo;

  /// **수집 당시 사용자의 날짜.** 지금 기기의 시간대가 아니라 [utcOffsetMinutes] 로 푼다.
  DateTime get localDate {
    final t = collectedAtUtc.add(Duration(minutes: utcOffsetMinutes));
    return DateTime(t.year, t.month, t.day);
  }

  // `copyWith` 는 두지 않는다. `memo: null` 로 **메모를 지울 수 없는** 형태가 되어
  // M5 에서 삭제를 지원할 때 곧바로 함정이 된다. 소비자가 생기는 M5 에서
  // 지움과 안 바꿈을 구분할 수 있는 형태로 만든다 (Codex 16회차).

  @override
  bool operator ==(Object other) =>
      other is CollectedUnit &&
      other.scratchUnitId == scratchUnitId &&
      other.collectedAtUtc == collectedAtUtc &&
      other.utcOffsetMinutes == utcOffsetMinutes &&
      other.memo == memo;

  @override
  int get hashCode =>
      Object.hash(scratchUnitId, collectedAtUtc, utcOffsetMinutes, memo);

  @override
  String toString() => 'CollectedUnit($scratchUnitId, $collectedAtUtc)';
}

/// 수집 기록 전체. **불변이며 원본 상태다.**
///
/// 지도 painter 가 쓰는 `Set<String>` 은 여기서 파생된다 — 반대가 아니다.
/// Set 을 원본으로 두면 수집일시·메모를 담을 곳이 없고, **현재 카탈로그에 없는
/// ID 가 다음 저장에서 조용히 사라진다**(Codex 15회차).
class CollectionSnapshot {
  CollectionSnapshot(Map<String, CollectedUnit> units)
      : _units = Map.unmodifiable(units);

  static final empty = CollectionSnapshot(const {});

  final Map<String, CollectedUnit> _units;

  int get length => _units.length;
  bool get isEmpty => _units.isEmpty;

  Iterable<CollectedUnit> get units => _units.values;

  CollectedUnit? operator [](String scratchUnitId) => _units[scratchUnitId];
  bool contains(String scratchUnitId) => _units.containsKey(scratchUnitId);

  /// 화면과 달성률이 쓰는 파생 집합. **현재 카탈로그에 있는 것만** 남긴다.
  ///
  /// 알 수 없는 ID 는 여기서 빠지지만 [units] 에는 그대로 남아 다시 저장된다.
  Set<String> idsIn(Iterable<String> catalog) {
    final known = catalog.toSet();
    return {
      for (final id in _units.keys)
        if (known.contains(id)) id,
    };
  }

  /// 카탈로그에 없는 ID 들. 진단·보고용이다.
  Set<String> unknownIds(Iterable<String> catalog) {
    final known = catalog.toSet();
    return {
      for (final id in _units.keys)
        if (!known.contains(id)) id,
    };
  }

  /// [unit] 을 더한 **새 스냅샷**. 제자리에서 고치지 않는다.
  ///
  /// 이미 있는 ID 면 **최초 수집 시각을 유지한다.** 다시 긁었다고 기록이
  /// 새것으로 바뀌면 "언제 처음 갔는가" 라는 정보가 사라진다.
  CollectionSnapshot collect(CollectedUnit unit) {
    final existing = _units[unit.scratchUnitId];
    if (existing != null) return this;
    return CollectionSnapshot({..._units, unit.scratchUnitId: unit});
  }

  @override
  String toString() => 'CollectionSnapshot(${_units.length}개)';
}

/// 저장 파일을 읽을 수 없을 때. 격리 대상이다.
class CollectionFormatException implements Exception {
  const CollectionFormatException(this.message);
  final String message;
  @override
  String toString() => '수집 기록을 읽을 수 없다: $message';
}

/// 이 앱이 모르는 **더 새로운** 버전. **격리하지 않는다.**
///
/// 손상이 아니라 구버전 앱으로 내려온 상황이다. 덮어쓰면 최신 앱이 만든
/// 기록을 지우게 되므로, 읽기를 막고 사용자에게 업데이트를 안내한다.
class UnsupportedCollectionVersionException implements Exception {
  const UnsupportedCollectionVersionException(this.found);
  final int found;
  @override
  String toString() =>
      '수집 기록 버전 $found 은 이 앱이 모른다 (지원 $kCollectionVersion)';
}

/// [snapshot] 을 저장 문자열로. **ID 오름차순으로 고정**해 결정적이다.
String encodeCollection(CollectionSnapshot snapshot) {
  final ids = snapshot.units.map((u) => u.scratchUnitId).toList()..sort();
  return jsonEncode({
    'version': kCollectionVersion,
    'units': [
      for (final id in ids)
        () {
          final u = snapshot[id]!;
          return {
            'scratchUnitId': u.scratchUnitId,
            'collectedAtUtc': u.collectedAtUtc.toUtc().toIso8601String(),
            'utcOffsetMinutes': u.utcOffsetMinutes,
            'memo': u.memo,
          };
        }(),
    ],
  });
}

/// 저장 문자열을 스냅샷으로.
///
/// **일부만 조용히 버리지 않는다.** 한 행이라도 깨져 있으면 전체를 오류로 본다 —
/// 그래야 사용자가 기록이 사라진 것을 알아차릴 수 있다.
CollectionSnapshot decodeCollection(String raw) {
  final Object? root;
  try {
    root = jsonDecode(raw);
  } on FormatException catch (e) {
    throw CollectionFormatException('JSON 이 아니다: ${e.message}');
  }
  if (root is! Map) throw const CollectionFormatException('최상위가 객체가 아니다');

  final version = root['version'];
  if (version is! int) throw const CollectionFormatException('version 이 정수가 아니다');
  if (version > kCollectionVersion) {
    throw UnsupportedCollectionVersionException(version);
  }
  if (version < 1) throw CollectionFormatException('version 이 범위 밖이다: $version');
  // version < kCollectionVersion 이면 여기서 순차 마이그레이션을 돈다.
  // 아직 v1 뿐이라 변환할 것이 없다.

  final list = root['units'];
  if (list is! List) throw const CollectionFormatException('units 가 배열이 아니다');

  final units = <String, CollectedUnit>{};
  for (var i = 0; i < list.length; i++) {
    final row = list[i];
    if (row is! Map) throw CollectionFormatException('units[$i] 가 객체가 아니다');

    final id = row['scratchUnitId'];
    if (id is! String || id.isEmpty) {
      throw CollectionFormatException('units[$i].scratchUnitId 가 비었다');
    }

    final at = row['collectedAtUtc'];
    if (at is! String) {
      throw CollectionFormatException('units[$i].collectedAtUtc 가 문자열이 아니다');
    }
    // **시간대가 없는 문자열은 거부한다.**
    //
    // `DateTime.parse` 는 `2026-08-14T12:00:00` 를 **기기의 로컬 시간대**로 읽는다.
    // 그러면 같은 파일이 기기마다 다른 순간을 가리키게 된다(Codex 16회차).
    // 쓰는 쪽은 항상 `Z` 를 붙이므로 계약을 그대로 강제한다.
    final DateTime parsed;
    try {
      parsed = DateTime.parse(at);
    } on FormatException {
      throw CollectionFormatException('units[$i].collectedAtUtc 를 읽을 수 없다: $at');
    }
    if (!parsed.isUtc) {
      throw CollectionFormatException(
          'units[$i].collectedAtUtc 에 시간대가 없다 (Z 가 필요하다): $at');
    }

    final offset = row['utcOffsetMinutes'];
    if (offset is! int || offset < -18 * 60 || offset > 18 * 60) {
      throw CollectionFormatException('units[$i].utcOffsetMinutes 가 범위 밖이다');
    }

    final memo = row['memo'];
    if (memo != null && memo is! String) {
      throw CollectionFormatException('units[$i].memo 가 문자열이 아니다');
    }

    final unit = CollectedUnit(
      scratchUnitId: id,
      collectedAtUtc: parsed,
      utcOffsetMinutes: offset,
      memo: memo as String?,
    );

    // 같은 ID 가 두 번 있으면 **먼저 수집한 쪽**을 남긴다.
    final prev = units[id];
    if (prev == null || unit.collectedAtUtc.isBefore(prev.collectedAtUtc)) {
      units[id] = unit;
    }
  }
  return CollectionSnapshot(units);
}
