# -*- coding: utf-8 -*-
"""`verify_merge.py` 가 **잘못된 병합을 실제로 거부하는지** 검사한다.

## 왜 필요한가

앱 테스트는 정상 파일에 검증기를 돌려 종료코드 0 만 본다. 그러면
`area_of()` 가 늘 0 을 돌려주거나 `TOLERANCE` 가 1 로 바뀌어도 통과한다.
**검증기가 무엇을 거부하는지는 거부당하는 입력으로만 확인할 수 있다.**
(Codex 30회차 3차 지적)

손으로 부산 중구를 지워 확인한 적은 있지만 그것은 회귀 방어선이 아니다.

## 어떻게

실제 지도가 아니라 **합성 도형**을 쓴다. 작고 결정적이며, 진짜 에셋이
바뀌어도 이 테스트의 뜻이 흔들리지 않는다. 시도 이름만 명세에 있는 것을
빌린다(`부산광역시` 는 제외가 없는 통합, `인천광역시` 는 제외가 있는 통합).

실행:
    python tool/map/test_verify_merge.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
VERIFY = os.path.join(HERE, 'verify_merge.py')


def square(x, y, w, h):
    """반시계 방향 사각 링."""
    return [[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]]


def feature(sidonm, sggnm, sgg, unit, rings):
    """[rings] 는 `[외곽, 구멍...]` 목록의 목록 = 멀티폴리곤."""
    return {
        'type': 'Feature',
        'properties': {
            'sidonm': sidonm, 'sggnm': sggnm, 'sgg': sgg, 'unit': unit},
        'geometry': {'type': 'MultiPolygon', 'coordinates': rings},
    }


def fc(features):
    return {'type': 'FeatureCollection', 'features': features}


#: 부산 세 구가 가로로 붙어 있는 모양. 합치면 3×1 직사각형이다.
BEFORE = fc([
    feature('부산광역시', '중구', '26110', '26110', [[square(0, 0, 1, 1)]]),
    feature('부산광역시', '서구', '26140', '26140', [[square(1, 0, 1, 1)]]),
    feature('부산광역시', '동구', '26170', '26170', [[square(2, 0, 1, 1)]]),
])

AFTER_OK = fc([
    feature('부산광역시', '중구', '26110', '부산광역시', [[square(0, 0, 3, 1)]]),
])


def run(before, after):
    """검증기를 돌려 `(종료코드, 출력)`."""
    paths = []
    for data in (before, after):
        fd, path = tempfile.mkstemp(suffix='.geojson')
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
        paths.append(path)
    try:
        r = subprocess.run([sys.executable, VERIFY] + paths,
                           capture_output=True, text=True, encoding='utf-8')
        return r.returncode, (r.stdout or '') + (r.stderr or '')
    finally:
        for p in paths:
            os.unlink(p)


def check(name, fn):
    try:
        fn()
    except AssertionError as e:
        print('  실패: %s — %s' % (name, e))
        return False
    print('  통과: %s' % name)
    return True


# ── 통과해야 하는 것 ──────────────────────────────────────────

def test_ok():
    code, out = run(BEFORE, AFTER_OK)
    assert code == 0, out


def test_hole_is_subtracted():
    """구멍은 면적에서 빼야 한다.

    병합 후 도형에 없던 구멍을 뚫으면 면적이 줄어 실패해야 한다. 구멍을
    더하는 버그가 있으면 오히려 늘어나므로 어느 쪽이든 통과하지 않는다.
    """
    holed = fc([
        feature('부산광역시', '중구', '26110', '부산광역시',
                [[square(0, 0, 3, 1), square(1.2, 0.2, 0.6, 0.6)]]),
    ])
    code, out = run(BEFORE, holed)
    assert code != 0, '구멍이 뚫린 도형이 통과했다\n' + out
    assert '면적' in out, out


# ── 막혀야 하는 것 ────────────────────────────────────────────

def test_member_missing():
    """구성원 하나가 병합에서 빠진 경우."""
    partial = fc([
        feature('부산광역시', '중구', '26110', '부산광역시', [[square(0, 0, 2, 1)]]),
    ])
    code, out = run(BEFORE, partial)
    assert code != 0, '구성원 유실이 통과했다\n' + out
    assert '동구' in out, '어느 구가 빠졌는지 알려주지 않는다\n' + out


def test_same_area_moved():
    """**면적은 같은데 자리가 틀린 경우.** 면적만 보면 못 가른다."""
    moved = fc([
        feature('부산광역시', '중구', '26110', '부산광역시',
                [[square(10, 10, 3, 1)]]),
    ])
    code, out = run(BEFORE, moved)
    assert code != 0, '옮겨진 도형이 통과했다\n' + out
    assert 'bounds' in out, out


def test_excluded_absorbed():
    """제외 대상(강화군)이 병합에 딸려 들어간 경우."""
    before = fc([
        feature('인천광역시', '중구', '28110', '28110', [[square(0, 0, 1, 1)]]),
        feature('인천광역시', '강화군', '28710', '28710', [[square(1, 0, 1, 1)]]),
    ])
    after = fc([
        feature('인천광역시', '중구', '28110', '인천광역시', [[square(0, 0, 2, 1)]]),
    ])
    code, out = run(before, after)
    assert code != 0, '강화군 흡수가 통과했다\n' + out


def test_bad_arg_count():
    """인자를 하나만 주면 조용히 기본 파일을 검사하면 안 된다."""
    r = subprocess.run([sys.executable, VERIFY, 'nope.geojson'],
                       capture_output=True, text=True, encoding='utf-8')
    assert r.returncode != 0, '인자 1개가 통과했다'
    assert '사용법' in (r.stdout or '') + (r.stderr or '')


def main():
    print('verify_merge 반례 검증')
    ok = all([
        check('정상 병합', test_ok),
        check('구멍은 면적에서 뺀다', test_hole_is_subtracted),
        check('구성원 유실', test_member_missing),
        check('면적은 같고 자리가 틀림', test_same_area_moved),
        check('제외 대상이 흡수됨', test_excluded_absorbed),
        check('인자 개수', test_bad_arg_count),
    ])
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
