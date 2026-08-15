import 'map_data.dart';

/// 지역 이름 검색. **순수 로직이라 UI 없이 테스트한다.**
///
/// 검색은 *접근* 문제를 푼다 — 이름을 아는 곳으로 바로 간다.
/// 지도에서 한눈에 보고 고르는 *표시* 문제는 인셋(M8)이 따로 푼다.

/// 한글 초성 19자. 유니코드 완성형 음절의 초성 인덱스 순서 그대로다.
const _choseong = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', //
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

const _hangulBase = 0xAC00; // '가'
const _hangulLast = 0xD7A3; // '힣'
const _jamoPerCho = 588; // 21 중성 × 28 종성

/// [text] 의 초성 문자열. 한글이 아닌 문자는 그대로 남긴다.
///
/// `순천시` → `ㅅㅊㅅ`
String choseongOf(String text) {
  final buf = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= _hangulBase && rune <= _hangulLast) {
      buf.write(_choseong[(rune - _hangulBase) ~/ _jamoPerCho]);
    } else {
      buf.writeCharCode(rune);
    }
  }
  return buf.toString();
}

/// [text] 가 **초성만으로** 이루어졌는가.
///
/// 완성형 음절이 하나라도 있으면 초성 질의가 아니다 — `서` 는 초성이 아니라
/// 이미 글자다. 빈 문자열은 초성 질의로 보지 않는다.
bool isChoseongQuery(String text) {
  if (text.isEmpty) return false;
  for (final rune in text.runes) {
    if (!_choseong.contains(String.fromCharCode(rune))) return false;
  }
  return true;
}

/// 호환 자모 영역(`U+3131`~`U+3163`). 조합되지 않은 낱자모 하나하나다.
bool _isCompatJamo(int rune) => rune >= 0x3131 && rune <= 0x3163;

/// 자음과 모음이 **조합되지 않은 채 섞여 있는가.**
///
/// `ㅅㅓ` 같은 상태다. 초성 질의도 아니고 지역 이름에도 없어서 반드시 0건이 되는데,
/// 화면이 "찾는 지역이 없습니다" 라고만 하면 사용자는 막다른 길에 놓인다.
///
/// **IME 조합이 끊기면 실제로 생긴다.** `ㅅㅊ` 로 찾다가 백스페이스로 `ㅊ` 만
/// 지우면 남은 `ㅅ` 이 확정 문자가 되고, 이어 친 모음이 새 글자로 시작한다.
/// 초성 검색을 쓰던 사용자가 이름 검색으로 옮겨 갈 때 밟는 흔한 경로다
/// (2026-08-15 실기기에서 재현).
bool hasLooseJamo(String text) {
  if (text.isEmpty) return false;
  if (isChoseongQuery(text)) return false; // 순수 초성은 정상 질의다
  return text.runes.any(_isCompatJamo);
}

/// 검색 결과 한 줄.
class RegionSearchResult {
  const RegionSearchResult({
    required this.region,
    required this.sidoName,
    required this.rank,
    required this.ambiguousName,
  });

  final Region region;
  final String sidoName;

  /// 정렬용. 작을수록 먼저 나온다.
  final int rank;

  /// **같은 이름을 가진 지역이 또 있는가.**
  ///
  /// `중구`·`서구`·`동구`·`남구`·`북구`·`고성군` 이 그렇다. 참이면 UI 가
  /// 시도명을 반드시 함께 보여야 어느 곳인지 알 수 있다.
  final bool ambiguousName;

  @override
  String toString() => '$sidoName ${region.name}(rank $rank)';
}

/// 232개 중 [query] 에 맞는 지역을 찾는다.
///
/// 규칙은 이렇다.
/// - 질의가 **초성만**이면 이름·시도명의 초성과 맞춰 본다 (`ㅅㅊ` → 순천시)
/// - 아니면 이름·시도명에 그대로 들어 있는지 본다 (`일산` → 고양시일산동구)
/// - **공백으로 나뉜 토막은 전부 맞아야 한다.** 각 토막이 이름이든 시도명이든
///   한쪽에는 걸려야 한다 — `부산 중구` 로 동명 여섯 곳 중 하나를 좁힐 수 있다.
///   `고양시 일산동구` 처럼 한 이름을 띄어 쓴 경우도 같은 규칙으로 걸린다
/// - 이름 쪽이 시도명 쪽보다, 앞에서 시작하는 쪽이 중간에 걸린 쪽보다 먼저다
/// - 같은 순위면 이름 오름차순
///
/// **초성 복합 질의에는 잡음이 섞인다.** 긴 시도명의 초성열에 짧은 토막이 우연히
/// 들어가기 때문이다 — `전남광주통합특별시`(ㅈㄴㄱㅈㅌㅎㅌㅂㅅ)에 `ㅂㅅ` 가 있어
/// `ㅂㅅ ㅈㄱ` 가 강진군까지 잡는다. 규칙상 맞는 결과라 없애지 않고 **순위로 뒤에
/// 둔다** — 걸러 내려면 시도 초성은 접두사만 허용해야 하는데, 그러면 `ㄱㅈ` 로
/// 전남광주 지역을 찾는 흐름이 함께 막힌다.
class RegionSearcher {
  RegionSearcher(this.data)
      : _entries = List.unmodifiable([
          for (final r in data.regions)
            _Entry(
              region: r,
              sidoName: data.sidoNames[r.sido],
              nameCho: choseongOf(r.name),
              sidoCho: choseongOf(data.sidoNames[r.sido]),
            ),
        ]),
        _ambiguous = _duplicateNames(data.regions);

  final MapData data;
  final List<_Entry> _entries;
  final Set<String> _ambiguous;

  static Set<String> _duplicateNames(List<Region> regions) {
    final seen = <String>{};
    final dup = <String>{};
    for (final r in regions) {
      if (!seen.add(r.name)) dup.add(r.name);
    }
    return dup;
  }

  /// 이름이 겹치는 지역들. 진단·테스트용이다.
  Set<String> get ambiguousNames => Set.unmodifiable(_ambiguous);

  /// 결과가 이보다 많으면 **더 좁히라고 안내한다.**
  ///
  /// `시` 는 171곳, `ㄱ` 은 219곳이 걸린다. 목록을 끝까지 내리게 두는 것은
  /// 답이 아니고, 시도명을 함께 치면 한 번에 좁혀진다는 걸 알려야 한다.
  static const crowded = 20;

  /// **자르지 않는다.** 예전에는 30개에서 조용히 끊었는데, 그러면 사용자는
  /// 찾는 곳이 없는 것인지 잘린 것인지 알 수 없다. 전부 돌려주고 개수를
  /// 화면에 보여준 뒤, 많으면 좁히는 법을 안내한다 (2026-08-15 사용자 결정).
  List<RegionSearchResult> search(String query) {
    final tokens = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return const [];

    // 초성 질의 판정은 **토막마다** 한다. 섞어 치는 경우는 없다고 보지만,
    // 한쪽만 초성인 질의도 각 토막이 알아서 맞는 쪽으로 걸린다.
    final out = <RegionSearchResult>[];

    for (final e in _entries) {
      var worst = -1;
      var ok = true;

      for (final token in tokens) {
        final cho = isChoseongQuery(token);
        final name = cho ? e.nameCho : e.region.name;
        final sido = cho ? e.sidoCho : e.sidoName;

        final int rank;
        if (name.startsWith(token)) {
          rank = 0;
        } else if (name.contains(token)) {
          rank = 1;
        } else if (sido.startsWith(token)) {
          rank = 2;
        } else if (sido.contains(token)) {
          rank = 3;
        } else {
          ok = false;
          break;
        }
        if (rank > worst) worst = rank;
      }
      if (!ok) continue;

      out.add(RegionSearchResult(
        region: e.region,
        sidoName: e.sidoName,
        rank: worst,
        ambiguousName: _ambiguous.contains(e.region.name),
      ));
    }

    out.sort((a, b) {
      final r = a.rank.compareTo(b.rank);
      return r != 0 ? r : a.region.name.compareTo(b.region.name);
    });
    return out;
  }
}

class _Entry {
  const _Entry({
    required this.region,
    required this.sidoName,
    required this.nameCho,
    required this.sidoCho,
  });

  final Region region;
  final String sidoName;
  final String nameCho;
  final String sidoCho;
}
