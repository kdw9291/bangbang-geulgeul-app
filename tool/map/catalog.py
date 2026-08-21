# -*- coding: utf-8 -*-
"""긁기 단위 **등록부**와 서버 **manifest**.

## 왜 등록부가 따로 필요한가

지도 에셋은 **지금 있는 단위**만 담는다. 그런데 `SYNC_CONTRACT.md` 5.4 는 폐지된
ID 를 영구 보존하라고 한다 — ID 를 재사용하면 과거 기록이 엉뚱한 지역으로 옮겨가고,
구버전 앱이 옛 ID 로 보낸 수집을 판정할 수도 없기 때문이다.

**현재 지도만으로는 사라진 ID 의 옛 이름·시도를 복원할 수 없다.** 그래서 원본을
나눈다.

| 파일 | 성격 |
|---|---|
| `unit_registry.json` | **추가만 된다.** 한 번 들어온 ID 는 지우지 않고 `retired` 로 바꾼다 |
| `catalog_history/<version>.json` | **버전별 불변 스냅샷.** 그 버전에서 무엇이 active 였는지 |
| `assets/map/korea_sgg.json` | 지금 있는 단위(도형 포함) |

버전 스냅샷이 따로 있는 이유는, 등록부의 **현재 status 만으로는 과거 버전에서
무엇이 active 였는지 알 수 없기** 때문이다. 232 시절 광역시 44곳은 지금 `retired`
지만 그때는 `active` 였다. 계약 5.4 는 "요청이 선언한 버전에서 active 였으면
받는다" 이므로 그 이력이 필요하다. (Codex 지적)

## 경로 I/O 를 함수에 넣지 않는다

`build_manifest(registry, asset)` 는 **넘겨받은 값만** 본다. 처음에는 고정 경로의
에셋을 읽었는데, 그러면 `make_asset.py` 가 **새로 만든 지도가 아니라 디스크의 옛
에셋**과 대조하게 된다. 다음 개편에서 등록부를 먼저 고치면 에셋을 못 만들고,
에셋을 먼저 만들려 해도 쓰기 전에 옛 에셋과 비교해 실패한다. **재현해서
확인했다.** (Codex 지적)

## canonical hash 규격 — 말로 적으면 갈린다

**해시 대상은 manifest 전체가 아니라 정규화된 `units` 배열뿐이다.**

- 인코딩 **UTF-8**, 유니코드 **NFC** 정규화
- `id` 오름차순 (코드포인트 기준)
- 각 항목은 `id, name, sido, status` **넷뿐**이고 전부 문자열이다
- **null·자동 형변환 금지.** 숫자나 boolean 이 오면 실패한다
- JSON 은 **공백·개행 없이**, 키 정렬, 비ASCII 는 **raw UTF-8**(`\\uXXXX` 이스케이프 없음)
- BOM 없음. 앞뒤 공백 없음
- **SHA-256**

규격 ID 는 `mapscratch-catalog-json-v1` 이다. 규격을 바꾸면 이 이름도 바꾼다.

> `json.dumps(sort_keys=True)` 를 쓰므로 **`FIELDS` 의 나열 순서 자체는 해시에
> 영향이 없다.** 지금 알파벳순과 우연히 같을 뿐이다. 순서가 계약인 것은
> *직렬화된 결과*이지 파이썬 dict 의 삽입 순서가 아니다.

**해시는 파이썬만 계산한다.** Dart 는 에셋에 박힌 값을 읽어 전달만 하고 다시
계산하지 않는다. Java 가 재계산해야 하면 `test_catalog.py` 의 golden vector 를
그대로 통과해야 한다.

## 실행

    python tool/map/catalog.py                 # manifest 생성 + 버전 스냅샷 기록
    python tool/map/catalog.py --check         # 최신인지만 확인
    python tool/map/catalog.py --init-history  # **최초 1회만.** 빈 이력을 허용한다
"""
import datetime
import hashlib
import io
import json
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(os.path.dirname(HERE))

REGISTRY = os.path.join(HERE, 'unit_registry.json')
ASSET = os.path.join(APP, 'assets', 'map', 'korea_sgg.json')
MANIFEST = os.path.join(HERE, 'catalog_manifest.json')
HISTORY = os.path.join(HERE, 'catalog_history')

#: 직렬화 규격의 이름. 규격을 바꾸면 이 값도 바꾼다.
SPEC = 'mapscratch-catalog-json-v1'

#: manifest 한 항목의 필드. 넷뿐이고 전부 문자열이다.
FIELDS = ('id', 'name', 'sido', 'status')

STATUSES = ('active', 'retired')

#: ID 는 **ASCII 영숫자**다. 파이썬 `isalnum()` 은 한글도 통과시켜 앱 계약과 어긋난다.
ID_RE = re.compile(r'^[A-Za-z0-9]+$')

#: version 은 `YYYY-MM-DD` 이고, 같은 날 두 번 개편하면 `.2` 처럼 뒤에 붙인다.
#
# **형식을 안 박으면 경로가 된다.** version 이 그대로 스냅샷 파일 이름이 되는데,
# 문자열이고 비어 있지 않은지만 보던 때는 `../escape` 가 통과해
# `tool/map/escape.json` 을 만들었다. 재현해서 확인했다. (Codex 지적)
VERSION_RE = re.compile(r'^(\d{4})-(\d{2})-(\d{2})(?:\.(\d+))?$')


class CatalogError(Exception):
    """검증 실패. `code` 로 어느 검사인지 구분한다."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message

    def __str__(self):
        return '[%s] %s' % (self.code, self.message)


def nfc(text):
    return unicodedata.normalize('NFC', text)


# ── canonical 직렬화 ──────────────────────────────────────────

def canonical_units(units):
    """해시와 manifest 가 함께 쓰는 **정규화된 목록**."""
    out = []
    for u in units:
        row = {}
        for f in FIELDS:
            if f not in u:
                raise CatalogError('missing-field', '%s 에 %s 가 없다'
                                   % (u.get('id'), f))
            v = u[f]
            # **자동 형변환을 하지 않는다.** `str(v)` 로 감싸면 숫자나 boolean 이
            # 조용히 문자열이 되어 manifest 에 들어간다.
            if not isinstance(v, str):
                raise CatalogError('not-a-string', '%s 의 %s 가 문자열이 아니다: %r'
                                   % (u.get('id'), f, v))
            row[f] = nfc(v)
        out.append(row)
    out.sort(key=lambda r: r['id'])
    return out


def canonical_json(units):
    """해시의 preimage. **이 문자열이 규격이다.**"""
    return json.dumps(units, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':'))


def canonical_hash(units):
    """[units] 는 `canonical_units` 를 거친 것이어야 한다."""
    return hashlib.sha256(canonical_json(units).encode('utf-8')).hexdigest()


# ── 검증 ─────────────────────────────────────────────────────

def check_version(version):
    """`YYYY-MM-DD` 또는 `YYYY-MM-DD.N`. **실제 달력 날짜여야 한다.**"""
    if not isinstance(version, str):
        raise CatalogError('bad-version', 'version 이 문자열이 아니다: %r' % version)
    m = VERSION_RE.match(version)
    if not m:
        raise CatalogError('bad-version',
                           'version 형식이 YYYY-MM-DD[.N] 이 아니다: %r' % version)
    try:
        datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError as e:
        raise CatalogError('bad-version', '없는 날짜다: %s (%s)' % (version, e))
    return version


def snapshot_path(version, history_dir=None):
    """그 버전의 스냅샷 경로. **디렉토리 밖으로 나가지 않는지 다시 본다.**

    `check_version` 이 이미 막지만, 경로를 만드는 자리에서 한 번 더 확인한다 —
    형식 규칙이 나중에 느슨해져도 여기서 걸린다.
    """
    check_version(version)
    root = os.path.abspath(history_dir or HISTORY)
    path = os.path.abspath(os.path.join(root, '%s.json' % version))
    if os.path.dirname(path) != root:
        raise CatalogError('bad-version', '스냅샷 경로가 이력 밖으로 나간다: %r'
                           % version)
    return path


def check_registry(registry):
    """등록부 자체의 형식."""
    check_version(registry.get('version'))

    seen = set()
    for u in registry['units']:
        # **필드 형식을 여기서 본다.** 예전에는 `canonical_units` 가 봤는데,
        # 그것은 지도 대조 **뒤에** 돌아서 active 단위의 `name=123` 이
        # `CatalogError` 가 아니라 raw `TypeError` 로 죽었다 (Codex 지적).
        for f in FIELDS:
            if f not in u:
                raise CatalogError('missing-field', '%s 에 %s 가 없다'
                                   % (u.get('id'), f))
            if not isinstance(u[f], str):
                raise CatalogError('not-a-string', '%s 의 %s 가 문자열이 아니다: %r'
                                   % (u.get('id'), f, u[f]))
        extra = set(u) - set(FIELDS)
        if extra:
            raise CatalogError('unknown-field', '%s 에 모르는 필드가 있다: %s'
                               % (u.get('id'), ' '.join(sorted(extra))))
        uid = u.get('id')
        if not isinstance(uid, str) or not ID_RE.match(uid):
            raise CatalogError('bad-id', 'ID 가 ASCII 영숫자가 아니다: %r' % uid)
        if u.get('status') not in STATUSES:
            raise CatalogError('bad-status', '%s 의 status 가 이상하다: %r'
                               % (uid, u.get('status')))
        # **NFC 로 접은 뒤에 중복을 다시 본다.** 눈에 같은 두 ID 가 다른 코드
        # 포인트로 들어오면 해시에서는 하나로 접힌다.
        key = nfc(uid)
        if key in seen:
            raise CatalogError('duplicate-id', '등록부에 ID 가 두 번 있다: %s' % uid)
        seen.add(key)


def check_against_map(registry, asset):
    """등록부의 active 집합이 **지도와 정확히 같은지.**

    [asset] 은 파일이 아니라 **메모리의 지도 데이터**다.
    """
    regions = asset['regions']
    in_map = {r['c']: r for r in regions}
    if len(in_map) != len(regions):
        raise CatalogError('duplicate-map-id', '지도에 같은 ID 가 두 번 있다')

    want = {u['id'] for u in registry['units'] if u['status'] == 'active'}
    got = set(in_map)
    if want != got:
        missing = sorted(want - got)
        extra = sorted(got - want)
        msg = ['등록부의 active 집합과 지도가 다르다']
        if missing:
            msg.append('  지도에 없는 active: %s' % ' '.join(missing))
        if extra:
            msg.append('  등록부에 없는 지도 단위: %s' % ' '.join(extra))
        raise CatalogError('active-mismatch', '\n'.join(msg))

    sidos = asset['sidos']
    for u in registry['units']:
        if u['status'] != 'active':
            continue
        r = in_map[u['id']]
        if nfc(u['name']) != nfc(r['n']):
            raise CatalogError('name-drift', '%s 이름이 다르다 — 등록부 %s / 지도 %s'
                               % (u['id'], u['name'], r['n']))
        if nfc(u['sido']) != nfc(sidos[r['s']]):
            raise CatalogError('sido-drift', '%s 시도가 다르다 — 등록부 %s / 지도 %s'
                               % (u['id'], u['sido'], sidos[r['s']]))


def check_append_only(units, history):
    """**과거 스냅샷의 ID 가 하나도 사라지지 않았는지.**

    [history] 는 `{version: units}` 다. 등록부는 추가만 된다는 계약을 여기서
    기계적으로 강제한다 — 그러지 않으면 retired 를 지우거나 이름을 바꿔도
    통과한다. (Codex 지적)
    """
    now = {u['id']: u for u in units}
    for version, past in sorted(history.items()):
        for old in past:
            cur = now.get(old['id'])
            if cur is None:
                raise CatalogError(
                    'id-removed',
                    '%s 에 있던 %s 가 등록부에서 사라졌다' % (version, old['id']))
            # 이름·시도는 그 단위의 정체다. 바뀌면 과거 기록의 뜻이 달라진다.
            for f in ('name', 'sido'):
                if cur[f] != old[f]:
                    raise CatalogError(
                        'past-changed',
                        '%s 의 %s 가 %s 에서와 다르다 — %s → %s'
                        % (old['id'], f, version, old[f], cur[f]))
            # 한 번 retired 가 된 것을 다시 살리지 않는다. 되살리려면 새 ID 다.
            if old['status'] == 'retired' and cur['status'] == 'active':
                raise CatalogError(
                    'revived',
                    '%s 가 %s 에서 retired 였는데 다시 active 다' % (old['id'], version))


def check_version_stable(manifest, history):
    """**같은 version 에 다른 목록이 오면 실패한다.**

    version 과 hash 는 일대일이다. 같은 날 두 번 개편하면 날짜만으로는 충돌한다.
    """
    past = history.get(manifest['version'])
    if past is None:
        return
    if canonical_hash(past) != manifest['hash']:
        raise CatalogError(
            'version-reused',
            '%s 는 이미 다른 목록으로 기록돼 있다. version 을 새로 준다.'
            % manifest['version'])


# ── 조립 ─────────────────────────────────────────────────────

def build_manifest(registry, asset, history=None, allow_empty_history=False):
    """등록부와 **메모리의 지도**를 대조해 manifest 를 만든다.

    경로를 읽지 않는다. 파일에서 읽는 것은 `load_*` 와 CLI 의 몫이다.
    """
    check_registry(registry)
    check_against_map(registry, asset)
    units = canonical_units(registry['units'])
    manifest = {
        'spec': SPEC,
        'version': registry['version'],
        'hash': canonical_hash(units),
        'units': units,
    }
    # **빈 이력을 조용히 넘기지 않는다.** `if history:` 로 두었더니 이력이 없을 때
    # 불변성 검사가 통째로 생략됐다 — 같은 version 에 항목을 더해도 통과했다
    # (Codex 지적). 최초 한 번만 `--init-history` 로 연다.
    if history is None:
        return manifest
    if not history and not allow_empty_history:
        raise CatalogError(
            'no-history',
            '버전 이력이 없다. 최초 1회면 '
            'python tool/map/catalog.py --init-history 로 만든다.')
    check_append_only(units, history)
    check_version_stable(manifest, history)
    return manifest


def load_registry(path=REGISTRY):
    return json.load(io.open(path, encoding='utf-8'))


def load_asset(path=ASSET):
    return json.load(io.open(path, encoding='utf-8'))


def load_history(path=HISTORY):
    """`{version: canonical units}`. **스냅샷 자체도 검증한다.**

    예전에는 `version` 과 `units` 만 꺼내고 나머지를 버렸다. 그러면 스냅샷의
    `hash` 나 `spec` 을 바꿔도, 파일 이름과 안의 version 이 달라도, 같은 version
    파일이 둘이어도 조용히 넘어간다 (Codex 지적).
    """
    out = {}
    if not os.path.isdir(path):
        return out
    for name in sorted(os.listdir(path)):
        if not name.endswith('.json'):
            continue
        where = os.path.join(path, name)
        doc = json.load(io.open(where, encoding='utf-8'))

        version = doc.get('version')
        check_version(version)
        if name[:-len('.json')] != version:
            raise CatalogError('history-name',
                               '파일 이름과 version 이 다르다: %s / %s'
                               % (name, version))
        if version in out:
            raise CatalogError('history-duplicate',
                               'version 이 두 번 있다: %s' % version)
        if doc.get('spec') != SPEC:
            raise CatalogError('history-spec',
                               '%s 의 spec 이 다르다: %r' % (version, doc.get('spec')))

        # **저장된 해시를 다시 계산해 대조한다.** 스냅샷을 손으로 고치면 걸린다.
        units = canonical_units(doc['units'])
        if units != doc['units']:
            raise CatalogError('history-not-canonical',
                               '%s 의 units 가 정규형이 아니다' % version)
        if canonical_hash(units) != doc.get('hash'):
            raise CatalogError('history-hash',
                               '%s 의 hash 가 units 와 맞지 않는다' % version)
        out[version] = units
    return out


def render(manifest):
    return json.dumps(manifest, ensure_ascii=False, indent=1) + '\n'


def write_atomically(path, text):
    """임시 파일에 다 쓴 뒤 바꿔 끼운다.

    스냅샷을 쓰다 중단되면 잘린 파일이 남고, 다음 실행에서는 "이미 있다" 로
    보여 자동으로 낫지 않는다.
    """
    tmp = path + '.tmp'
    with io.open(tmp, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def main():
    # **최초 1회만** 빈 이력을 허용한다. 평소에 빈 이력을 조용히 넘기면
    # 불변성 검사가 통째로 생략된다.
    init = '--init-history' in sys.argv
    try:
        registry = load_registry()
        asset = load_asset()
        history = load_history()
        manifest = build_manifest(registry, asset, history,
                                  allow_empty_history=init)
    except CatalogError as e:
        sys.exit(str(e))

    text = render(manifest)
    n_active = sum(1 for u in manifest['units'] if u['status'] == 'active')
    n_retired = len(manifest['units']) - n_active
    snapshot = snapshot_path(manifest['version'])

    if '--check' in sys.argv:
        current = io.open(MANIFEST, encoding='utf-8').read()             if os.path.exists(MANIFEST) else ''
        if current != text:
            sys.exit('catalog_manifest.json 이 낡았다. '
                     'python tool/map/catalog.py 로 다시 만든다.')
        if not os.path.exists(snapshot):
            sys.exit('%s 버전 스냅샷이 없다. python tool/map/catalog.py 로 만든다.'
                     % manifest['version'])
        print('카탈로그 %s · 단위 %d개 (active %d) · 이력 %d개 · 최신'
              % (manifest['version'], len(manifest['units']), n_active,
                 len(history)))
        return

    write_atomically(MANIFEST, text)

    # **버전 스냅샷은 한 번 쓰면 바꾸지 않는다.** 이미 있으면
    # `check_version_stable` 이 같은 목록인지 확인했으므로 다시 쓰지 않는다.
    os.makedirs(HISTORY, exist_ok=True)
    if not os.path.exists(snapshot):
        write_atomically(snapshot, json.dumps(
            {'spec': SPEC, 'version': manifest['version'],
             'hash': manifest['hash'], 'units': manifest['units']},
            ensure_ascii=False, indent=1) + '\n')
        print('버전 스냅샷 기록 → %s' % os.path.relpath(snapshot))

    print('카탈로그 %s · hash %s…' % (manifest['version'], manifest['hash'][:8]))
    print('단위 %d개 (active %d · retired %d) → %s'
          % (len(manifest['units']), n_active, n_retired,
             os.path.relpath(MANIFEST)))


if __name__ == '__main__':
    main()
