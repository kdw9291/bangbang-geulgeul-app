# -*- coding: utf-8 -*-
"""등록부·manifest 검증 로직의 반례 테스트.

## 왜 필요한가

앱 테스트는 **이미 만들어진 manifest** 만 본다. "생성기가 어긋난 등록부를
걸러내는가" 는 걸러지는 입력으로만 확인된다.

## 원본 파일을 건드리지 않는다

처음에는 실제 `unit_registry.json` 을 잠시 덮어썼다가 되돌렸다. **강제 종료나
디스크 오류가 끼면 등록부가 깨진 채 남는다.** `build_manifest` 를 순수 함수로
바꾼 뒤에는 그럴 이유가 없어졌다 — 값만 넘긴다. (Codex 지적)

`SystemExit` 대신 **`CatalogError` 의 `code`** 를 검사한다. 모든 예외를 정답으로
치면 엉뚱한 검사에서 실패해도 반례가 통과한다.

## golden vector

해시 규격은 **파이썬만 계산하고 Dart 는 읽기만 한다.** 다만 Java 가 재계산해야
할 때를 대비해, 규격을 바꾸면 깨지도록 **정답 문자열과 해시를 박아 둔다.**
지금 테스트는 "두 입력이 같다/다르다" 만 보므로 직렬화 규칙을 바꾸고 manifest 를
다시 만들면 전부 통과한다.

실행:
    python tool/map/test_catalog.py
"""
import copy
import os
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catalog  # noqa: E402


def check(name, fn):
    try:
        fn()
    except AssertionError as e:
        print('  실패: %s — %s' % (name, e))
        return False
    print('  통과: %s' % name)
    return True


def expect_error(code, fn):
    """[fn] 이 그 `code` 로 실패해야 한다."""
    try:
        fn()
    except catalog.CatalogError as e:
        assert e.code == code, '기대한 코드는 %s 인데 %s 였다: %s' % (code, e.code, e)
        return
    raise AssertionError('%s 로 막혔어야 하는데 통과했다' % code)


# ── golden vector ─────────────────────────────────────────────
#
# 일부러 까다로운 값을 넣었다 — 비ASCII, 따옴표, 역슬래시, 제어문자, 슬래시,
# 정렬을 흔드는 ID 순서. **이 값이 바뀌면 규격이 바뀐 것이다.**

GOLDEN_UNITS = [
    {'id': 'ZZ002', 'name': '따"옴표', 'sido': '경기도', 'status': 'retired'},
    {'id': 'AA001', 'name': '역\\슬래시', 'sido': '강원특별자치도', 'status': 'active'},
    {'id': 'MM003', 'name': '탭\t문자', 'sido': '제주특별자치도', 'status': 'active'},
    {'id': 'BB004', 'name': '슬래시/와 한글', 'sido': '서울특별시', 'status': 'active'},
]

GOLDEN_JSON = (
    '[{"id":"AA001","name":"역\\\\슬래시","sido":"강원특별자치도","status":"active"},'
    '{"id":"BB004","name":"슬래시/와 한글","sido":"서울특별시","status":"active"},'
    '{"id":"MM003","name":"탭\\t문자","sido":"제주특별자치도","status":"active"},'
    '{"id":"ZZ002","name":"따\\"옴표","sido":"경기도","status":"retired"}]'
)


def test_golden_json():
    """**직렬화 결과가 정확히 이 문자열이어야 한다.**"""
    got = catalog.canonical_json(catalog.canonical_units(GOLDEN_UNITS))
    assert got == GOLDEN_JSON, '\n  기대: %s\n  실제: %s' % (GOLDEN_JSON, got)


def test_golden_hash():
    import hashlib
    want = hashlib.sha256(GOLDEN_JSON.encode('utf-8')).hexdigest()
    got = catalog.canonical_hash(catalog.canonical_units(GOLDEN_UNITS))
    assert got == want, got


def test_no_ascii_escape():
    """비ASCII 는 **raw UTF-8** 이어야 한다. `\\uXXXX` 로 나가면 Java 와 갈린다."""
    j = catalog.canonical_json(catalog.canonical_units(GOLDEN_UNITS))
    assert '\\u' not in j, j
    assert '한글' in j


def test_no_whitespace():
    j = catalog.canonical_json(catalog.canonical_units(GOLDEN_UNITS))
    assert j == j.strip(), '앞뒤 공백이 있다'
    assert ', ' not in j and ': ' not in j, '구분자에 공백이 있다'
    assert not j.startswith('﻿'), 'BOM 이 있다'


# ── canonical 규칙 ────────────────────────────────────────────

U = [
    {'id': '26000', 'name': '부산광역시', 'sido': '부산광역시', 'status': 'active'},
    {'id': '11000', 'name': '서울특별시', 'sido': '서울특별시', 'status': 'active'},
]


def test_order_does_not_matter():
    a = catalog.canonical_hash(catalog.canonical_units(U))
    b = catalog.canonical_hash(catalog.canonical_units(list(reversed(U))))
    assert a == b, '정렬이 안 된다'


def test_content_changes_hash():
    a = catalog.canonical_hash(catalog.canonical_units(U))
    v = copy.deepcopy(U)
    v[0]['status'] = 'retired'
    assert a != catalog.canonical_hash(catalog.canonical_units(v))


def test_nfc_normalized():
    """**자모가 분리된 한글도 같은 값이어야 한다.**"""
    nfd = copy.deepcopy(U)
    nfd[0]['name'] = unicodedata.normalize('NFD', nfd[0]['name'])
    assert nfd[0]['name'] != U[0]['name'], '이 파이썬에서 NFD 가 안 만들어졌다'
    assert catalog.canonical_hash(catalog.canonical_units(U)) == \
        catalog.canonical_hash(catalog.canonical_units(nfd))


def test_non_string_rejected():
    """**자동 형변환을 하지 않는다.** 숫자가 조용히 문자열이 되면 안 된다."""
    for bad in (None, 26000, True, ['x']):
        v = copy.deepcopy(U)
        v[0]['sido'] = bad
        expect_error('not-a-string', lambda: catalog.canonical_units(v))


def test_missing_field():
    v = copy.deepcopy(U)
    del v[0]['sido']
    expect_error('missing-field', lambda: catalog.canonical_units(v))


# ── 등록부와 지도 대조 ────────────────────────────────────────

def real():
    """실제 등록부·지도·이력. **읽기만 한다.**"""
    return (catalog.load_registry(), catalog.load_asset(),
            catalog.load_history())


def build(registry, asset, history=None):
    return catalog.build_manifest(registry, asset, history)


def test_normal():
    reg, asset, hist = real()
    m = build(reg, asset, hist)
    assert m['spec'] == catalog.SPEC
    assert len(m['hash']) == 64
    active = [u for u in m['units'] if u['status'] == 'active']
    assert len(active) == 193, len(active)


def test_active_missing_from_map():
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    reg['units'].append({'id': '99999', 'name': '없는곳', 'sido': '경기도',
                         'status': 'active'})
    expect_error('active-mismatch', lambda: build(reg, asset))


def test_map_unit_missing_from_registry():
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    for u in reg['units']:
        if u['id'] == '26000':
            u['status'] = 'retired'
    expect_error('active-mismatch', lambda: build(reg, asset))


def test_name_drift():
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    for u in reg['units']:
        if u['id'] == '26000':
            u['name'] = '부산시'
    expect_error('name-drift', lambda: build(reg, asset))


def test_duplicate_id():
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    reg['units'].append(copy.deepcopy(reg['units'][0]))
    expect_error('duplicate-id', lambda: build(reg, asset))


def test_bad_status():
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    reg['units'][0]['status'] = 'deleted'
    expect_error('bad-status', lambda: build(reg, asset))


def test_non_ascii_id():
    """파이썬 `isalnum()` 은 한글도 통과시킨다. 앱 계약은 ASCII 다."""
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    reg['units'].append({'id': '부산', 'name': 'x', 'sido': '경기도',
                         'status': 'retired'})
    expect_error('bad-id', lambda: build(reg, asset))


def test_unknown_field():
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    reg['units'][0]['note'] = '메모'
    expect_error('unknown-field', lambda: build(reg, asset))


# ── append-only 와 버전 불변 ──────────────────────────────────

def test_retired_cannot_be_removed():
    """**과거 스냅샷의 ID 를 지우면 막힌다.**"""
    reg, asset, hist = real()
    assert hist, '버전 이력이 없다 — python tool/map/catalog.py 로 만든다'
    reg = copy.deepcopy(reg)
    reg['units'] = [u for u in reg['units'] if u['id'] != '11680']
    expect_error('id-removed', lambda: build(reg, asset, hist))


def test_past_name_cannot_change():
    reg, asset, hist = real()
    reg = copy.deepcopy(reg)
    for u in reg['units']:
        if u['id'] == '11680':
            u['name'] = '딴이름'
    expect_error('past-changed', lambda: build(reg, asset, hist))


def test_retired_cannot_be_revived():
    """되살리려면 새 ID 다. 옛 ID 를 다시 쓰면 과거 기록이 옮겨간다.

    **지도에도 넣어야 뜻이 있다.** 등록부만 바꾸면 `active-mismatch` 가 먼저
    걸려, `revived` 검사를 지워도 이 테스트가 통과한다 (Codex 지적).
    """
    reg, asset, hist = real()
    reg = copy.deepcopy(reg)
    asset = copy.deepcopy(asset)
    old = next(u for u in reg['units'] if u['id'] == '11680')
    old['status'] = 'active'
    # 지도에도 같은 이름·시도로 넣어 대조를 통과시킨다.
    sido = asset['sidos'].index(old['sido'])
    asset['regions'].append({'c': old['id'], 'n': old['name'], 's': sido,
                             'r': [[0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0]]})
    expect_error('revived', lambda: build(reg, asset, hist))


def test_version_cannot_be_reused():
    """**같은 version 에 다른 목록이 오면 막힌다.**"""
    reg, asset, hist = real()
    reg = copy.deepcopy(reg)
    # 지도와 어긋나지 않게 retired 하나만 더한다 → 목록이 달라진다
    reg['units'].append({'id': 'ZZ999', 'name': '가짜', 'sido': '경기도',
                         'status': 'retired'})
    expect_error('version-reused', lambda: build(reg, asset, hist))


def test_new_version_ok():
    """version 을 새로 주면 통과한다 — 다음 개편의 정상 경로다."""
    reg, asset, hist = real()
    reg = copy.deepcopy(reg)
    reg['units'].append({'id': 'ZZ999', 'name': '가짜', 'sido': '경기도',
                         'status': 'retired'})
    reg['version'] = '9999-12-31'
    m = build(reg, asset, hist)
    assert m['version'] == '9999-12-31'


def test_bad_version():
    """**version 이 그대로 스냅샷 파일 이름이 된다.**

    형식을 안 박던 때는 `../escape` 가 통과해 이력 디렉토리 밖에 파일을 만들었다.
    """
    reg, asset, _ = real()
    for bad in ('../escape', '..' + os.sep + 'escape', '2026/09/01', '..', '.',
                '2026-13-01', '2026-02-30', 'v1', '', 20260820):
        r = copy.deepcopy(reg)
        r['version'] = bad
        expect_error('bad-version', lambda: build(r, asset))


def test_snapshot_path_stays_inside():
    for bad in ('../escape', '2026/09/01'):
        expect_error('bad-version', lambda: catalog.snapshot_path(bad))
    # 정상 버전은 이력 디렉토리 안이다.
    p = catalog.snapshot_path('2026-08-20')
    assert os.path.dirname(p) == os.path.abspath(catalog.HISTORY), p


def test_empty_history_rejected():
    """빈 이력을 조용히 넘기면 불변성 검사가 통째로 생략된다."""
    reg, asset, _ = real()
    reg = copy.deepcopy(reg)
    reg['units'].append({'id': 'ZZ999', 'name': '가짜', 'sido': '경기도',
                         'status': 'retired'})
    expect_error('no-history', lambda: build(reg, asset, {}))
    # `--init-history` 로는 열린다.
    m = catalog.build_manifest(reg, asset, {}, allow_empty_history=True)
    assert m['hash']


def test_history_corruption_detected():
    """**스냅샷을 손으로 고치면 걸린다.** 임시 디렉토리에서만 검사한다."""
    import json
    import shutil
    import tempfile
    src = catalog.HISTORY
    cases = {
        'history-spec': lambda d: d.update({'spec': 'other'}),
        'history-hash': lambda d: d.update({'hash': '0' * 64}),
        'history-not-canonical': lambda d: d['units'].sort(
            key=lambda u: u['id'], reverse=True),
    }
    for code, mutate in cases.items():
        tmp = tempfile.mkdtemp()
        try:
            for name in os.listdir(src):
                shutil.copy(os.path.join(src, name), tmp)
            name = sorted(os.listdir(tmp))[0]
            where = os.path.join(tmp, name)
            doc = json.load(open(where, encoding='utf-8'))
            mutate(doc)
            with open(where, 'w', encoding='utf-8') as f:
                json.dump(doc, f, ensure_ascii=False)
            expect_error(code, lambda: catalog.load_history(tmp))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    # 파일 이름과 안의 version 이 다른 경우
    tmp = tempfile.mkdtemp()
    try:
        for name in os.listdir(src):
            shutil.copy(os.path.join(src, name), tmp)
        name = sorted(os.listdir(tmp))[0]
        os.rename(os.path.join(tmp, name), os.path.join(tmp, '2020-01-01.json'))
        expect_error('history-name', lambda: catalog.load_history(tmp))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_retired_kept():
    reg, asset, hist = real()
    m = build(reg, asset, hist)
    retired = {u['id'] for u in m['units'] if u['status'] == 'retired'}
    assert len(retired) == 71, len(retired)
    for gone in ('11680', '26350', '27140', '50110'):
        assert gone in retired, '%s 가 등록부에서 사라졌다' % gone


def main():
    print('catalog 반례 검증')
    ok = all([
        check('golden — 직렬화 문자열', test_golden_json),
        check('golden — 해시', test_golden_hash),
        check('비ASCII 를 이스케이프하지 않는다', test_no_ascii_escape),
        check('공백·BOM 이 없다', test_no_whitespace),
        check('입력 순서가 해시를 바꾸지 않는다', test_order_does_not_matter),
        check('내용이 바뀌면 해시가 바뀐다', test_content_changes_hash),
        check('NFD 한글도 같은 해시', test_nfc_normalized),
        check('문자열이 아니면 거부', test_non_string_rejected),
        check('필드 누락 거부', test_missing_field),
        check('정상', test_normal),
        check('지도에 없는 active', test_active_missing_from_map),
        check('등록부에 없는 지도 단위', test_map_unit_missing_from_registry),
        check('이름 불일치', test_name_drift),
        check('중복 ID', test_duplicate_id),
        check('이상한 status', test_bad_status),
        check('비ASCII ID', test_non_ascii_id),
        check('모르는 필드', test_unknown_field),
        check('retired 를 지울 수 없다', test_retired_cannot_be_removed),
        check('과거 이름을 바꿀 수 없다', test_past_name_cannot_change),
        check('retired 를 되살릴 수 없다', test_retired_cannot_be_revived),
        check('같은 version 재사용 거부', test_version_cannot_be_reused),
        check('version 형식', test_bad_version),
        check('스냅샷 경로가 밖으로 안 나간다', test_snapshot_path_stays_inside),
        check('빈 이력 거부', test_empty_history_rejected),
        check('스냅샷 손상 검출', test_history_corruption_detected),
        check('새 version 은 통과', test_new_version_ok),
        check('폐지 ID 71개 보존', test_retired_kept),
    ])
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
