# -*- coding: utf-8 -*-
"""병합 명세 검증 로직의 반례 테스트.

## 왜 파이썬 테스트가 따로 필요한가

앱 테스트는 **이미 만들어진 에셋**을 본다. 그래서 "생성기가 잘못된 병합을 잡아
내는가" 는 검사할 수 없다 — 잘못된 에셋이 만들어지면 그때는 이미 늦다.

여기 있는 반례들은 전부 **한때 통과하던 것**이다 (Codex 30회차 코드 리뷰·재검토).

## 여기서 잡지 않는 것

**병합 그룹 안에서 구성원이 빠지는 경우**는 여기서 못 잡는다. 이 함수들은
이미 dissolve 된 피처의 속성만 받아서, 그 도형이 몇 곳을 합친 것인지 모른다.
그것은 `verify_merge.py` 가 병합 전 원본과 면적을 대조해 잡는다.

실행:
    python tool/map/test_merge_spec.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge_spec import unit_for, expected_codes, MERGE  # noqa: E402


def codes_for(sidonm, features):
    """[features] 는 `(sggnm, sgg, unit)` 목록. `(실제, 기대)` 를 준다.

    `expected_codes` 가 명세 위반을 발견하면 `SystemExit` 를 올린다.
    """
    got = {unit_for(sidonm, sgg, nm, u)[0] for nm, sgg, u in features}
    residual = {nm: sgg for nm, sgg, u in features if u != sidonm}
    return got, expected_codes(sidonm, residual)


def blocked(sidonm, features):
    """이 산출물이 **막히는가.** 예외로 막히거나 코드 집합이 어긋나면 참."""
    try:
        got, want = codes_for(sidonm, features)
    except SystemExit:
        return True
    return got != want


def check(name, fn):
    try:
        fn()
    except AssertionError as e:
        print('  실패: %s — %s' % (name, e))
        return False
    print('  통과: %s' % name)
    return True


# ── 통과해야 하는 것 ──────────────────────────────────────────

def test_normal():
    """정상 병합. 실제 mapshaper 산출물과 같은 모양이다.

    병합 피처의 대표 속성이 `제물포구/28125` 인 것이 핵심이다 — 합쳐진 아홉 중
    아무거나 하나이며, 그래서 `sggnm` 으로는 판정할 수 없다.
    """
    got, want = codes_for('인천광역시', [
        ('제물포구', '28125', '인천광역시'),
        ('강화군', '28710', '28710'),
        ('옹진군', '28720', '28720'),
    ])
    assert got == want == {'28000', '28710', '28720'}, got


def test_full_merge_sido():
    """제외가 없는 시도는 정확히 한 코드가 된다."""
    got, want = codes_for('부산광역시', [('중구', '26110', '부산광역시')])
    assert got == want == {'26000'}, got


def test_unmerged_sido_untouched():
    """병합 대상이 아닌 시도는 원래 코드를 그대로 쓴다."""
    assert unit_for('경기도', '41111', '수원시장안구', '41111') == \
        ('41111', '수원시장안구')


# ── 막혀야 하는 것 ────────────────────────────────────────────

def test_swapped():
    """**병합 피처가 강화군 속성을 물고 도심 한 곳이 잘못 잔류한 경우.**

    `sggnm` 으로 판정하던 시절에는 앞뒤가 뒤바뀐 채로 코드 집합이 그대로
    `{28000, 28710, 28720}` 이 되어 통과했다.
    """
    assert blocked('인천광역시', [
        ('강화군', '28710', '인천광역시'),
        ('제물포구', '28125', '28125'),
        ('옹진군', '28720', '28720'),
    ]), '뒤바뀐 병합이 통과했다'


def test_all_merged():
    """시도 전체를 합쳐 버린 경우 — 강화군·옹진군이 사라진다."""
    assert blocked('인천광역시', [
        ('제물포구', '28125', '인천광역시'),
    ]), '전부 병합이 통과했다'


def test_not_merged():
    """병합 단계를 빠뜨린 경우 — 도심 구가 제 코드로 남는다."""
    assert blocked('인천광역시', [
        ('제물포구', '28125', '28125'),
        ('중구', '28110', '28110'),
        ('강화군', '28710', '28710'),
        ('옹진군', '28720', '28720'),
    ]), '병합 누락이 통과했다'


def test_wrong_residual_code():
    """**잔류 피처가 엉뚱한 코드를 단 경우.**

    기대값을 잔류 피처의 `sgg` 에서 만들던 시절에는 정답이 함께 틀어져 통과했다.
    지금은 명세의 `{이름: 코드}` 와 대조한다.
    """
    assert blocked('인천광역시', [
        ('제물포구', '28125', '인천광역시'),
        ('강화군', '99999', '99999'),
        ('옹진군', '28720', '28720'),
    ]), '잘못된 잔류 코드가 통과했다'


def test_spec_has_codes():
    """명세의 `exclude` 는 이름만이 아니라 코드까지 갖는다."""
    for sidonm, m in MERGE.items():
        ex = m.get('exclude')
        if ex is None:
            continue
        assert isinstance(ex, dict), '%s 의 exclude 가 이름 집합이다' % sidonm
        for name, code in ex.items():
            assert code.isdigit() and len(code) == 5, (sidonm, name, code)


def main():
    print('merge_spec 반례 검증 (병합 대상 %d개 시도)' % len(MERGE))
    ok = all([
        check('정상 병합', test_normal),
        check('제외 없는 시도', test_full_merge_sido),
        check('병합 대상 아닌 시도', test_unmerged_sido_untouched),
        check('병합 피처와 잔류가 뒤바뀜', test_swapped),
        check('시도 전체를 합쳐 버림', test_all_merged),
        check('병합 단계 누락', test_not_merged),
        check('잔류 피처의 코드가 틀림', test_wrong_residual_code),
        check('명세가 제외 코드를 갖는다', test_spec_has_codes),
    ])
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
