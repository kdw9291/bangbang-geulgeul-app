# -*- coding: utf-8 -*-
"""병합 전후 GeoJSON 을 대조해 **구성원 유실**을 잡는다.

## 왜 이것이 따로 필요한가

`make_asset.py` 의 검사 둘로는 부족하다.

- **최종 코드 집합**은 시도별로 어떤 단위가 나왔는지만 본다.
- **`EXPECTED_UNITS`** 는 최종 피처 개수만 본다.

둘 다 병합 **그룹 안에서** 구성원 하나가 사라진 경우를 못 잡는다. 부산 16곳
중 하나가 dissolve 입력에서 빠져도 부산 결과는 여전히 피처 하나이고 코드도
`26000` 하나라, 개수는 193 그대로다. 지도에는 구멍이 뚫린 채로 남는다.
(Codex 30회차 재검토 지적, 재현해 확인함)

여기서는 **병합 전 원본과 대조**한다. 셋을 본다.

1. **면적** — 병합은 합집합이라 내부 경계가 사라져도 면적 합이 보존된다.
   구성원이 빠지면 그만큼 줄어든다.
2. **bounds** — 면적만 보면 *빠진 만큼 다른 자리가 늘어난* 도형을 못 가른다.
   실제로 부산 전체를 경도 +0.05 옮겨 보니 면적 차이가 1.17e-11 이라 통과했다
   (Codex 30회차 3차 지적).
3. **구성원 대표점** — 병합 전 각 구성원 안의 점 하나가 병합 후 도형 안에
   들어 있는지 본다. 어느 구가 빠졌는지까지 이름으로 알려 준다.

## 한계

경위도 좌표에서 잰 값이라 실제 km² 가 아니다. **상대 비교에만 쓴다.**
단순화는 2단계 이전에 이미 끝나 있어 병합 전후에 추가로 일어나지 않는다.

## 실행

    python tool/map/verify_merge.py                     # 기본 경로
    python tool/map/verify_merge.py 전.geojson 후.geojson
"""
import io
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from merge_spec import MERGE, unit_for  # noqa: E402

BEFORE = os.path.join(HERE, 'sgg_simplified.geojson')
AFTER = os.path.join(HERE, 'sgg_merged.geojson')

#: 면적 비교 허용 오차(상대).
#
# **잡음과 신호 사이에서 고른 값이다.** dissolve2 는 위상 연산이라 병합하지 않는
# 지역도 미세하게 달라진다 — 2026-08-20 측정에서 비교 단위 192개 중 191개가
# 정확히 0, 가장 큰 것이 창원시마산합포구의 **0.00102%** 였다.
#
# 잡으려는 것은 구성원 유실이고, 병합군에서 **가장 작은 구성원이 전체의
# 0.43%** 다(부산 중구). 아래 값은 잡음의 약 10배이면서 그 신호의 1/43 이라
# 둘을 확실히 가른다.
TOLERANCE = 1e-4

#: bounds 비교 허용 오차(좌표 단위 = 도). 4% 단순화 뒤 정점 간격보다 훨씬 작다.
BOUNDS_TOLERANCE = 1e-4


def ring_area(ring):
    s = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


def area_of(geom):
    """폴리곤·멀티폴리곤의 면적. 구멍은 뺀다."""
    t = geom['type']
    if t == 'Polygon':
        polys = [geom['coordinates']]
    elif t == 'MultiPolygon':
        polys = geom['coordinates']
    else:
        raise SystemExit('알 수 없는 geometry: %s' % t)
    total = 0.0
    for poly in polys:
        for i, ring in enumerate(poly):
            a = ring_area(ring)
            total += a if i == 0 else -a
    return total


def polygons(geom):
    """폴리곤 목록. 각 폴리곤은 `[외곽링, 구멍링...]`."""
    t = geom['type']
    if t == 'Polygon':
        return [geom['coordinates']]
    if t == 'MultiPolygon':
        return geom['coordinates']
    raise SystemExit('알 수 없는 geometry: %s' % t)


def bounds_of(geom):
    xs, ys = [], []
    for poly in polygons(geom):
        for x, y in poly[0]:
            xs.append(x)
            ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def union_bounds(a, b):
    if a is None:
        return b
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def _in_ring(ring, px, py):
    """단순 ray casting. 경계 위의 점은 결과가 흔들리므로 쓰지 않는다."""
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > py) != (y2 > py):
            x = x1 + (py - y1) * (x2 - x1) / (y2 - y1)
            if px < x:
                inside = not inside
    return inside


def contains(geom, px, py):
    for poly in polygons(geom):
        if not _in_ring(poly[0], px, py):
            continue
        if any(_in_ring(hole, px, py) for hole in poly[1:]):
            continue
        return True
    return False


def representative_point(geom):
    """도형 **안**의 점 하나.

    중심점은 오목한 지역에서 밖으로 나간다(부산·통영). 가장 큰 외곽링의
    중간 높이에서 가로줄을 그어 **가장 긴 내부 구간의 중점**을 고른다.
    """
    best = None
    for poly in polygons(geom):
        a = ring_area(poly[0])
        if best is None or a > best[0]:
            best = (a, poly[0])
    ring = best[1]
    ys = [y for _, y in ring]
    py = (min(ys) + max(ys)) / 2
    xs = []
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > py) != (y2 > py):
            xs.append(x1 + (py - y1) * (x2 - x1) / (y2 - y1))
    xs.sort()
    if len(xs) < 2:
        # 가로줄이 도형을 못 지나는 극단적 모양. 정점 하나로 물러선다.
        return ring[0][0], ring[0][1]
    widest = max(zip(xs[0::2], xs[1::2]), key=lambda p: p[1] - p[0])
    return (widest[0] + widest[1]) / 2, py


def load(path):
    return json.load(io.open(path, encoding='utf-8'))['features']


def main():
    # **인자는 0개 또는 2개만 받는다.** 하나만 주면 조용히 무시하고 기본 파일을
    # 검사해 "통과" 를 찍는다 — 검증 도구가 그러면 안 된다 (Codex 30회차).
    args = sys.argv[1:]
    if len(args) not in (0, 2):
        sys.exit('사용법: verify_merge.py [병합전.geojson 병합후.geojson]')
    before_path, after_path = args if args else (BEFORE, AFTER)

    before = load(before_path)
    after = load(after_path)

    # 병합 전 원본을 **명세대로 묶어** 기대 면적을 만든다.
    want = defaultdict(float)
    want_bounds = {}
    members = defaultdict(list)
    points = defaultdict(list)
    for f in before:
        p = f['properties']
        sidonm, sgg, sggnm = p['sidonm'], str(p['sgg']), p['sggnm']
        m = MERGE.get(sidonm)
        if m is None:
            code = sgg
        elif sggnm in m.get('exclude', {}):
            code = sgg
        else:
            code = m['code']
        want[code] += area_of(f['geometry'])
        want_bounds[code] = union_bounds(
            want_bounds.get(code), bounds_of(f['geometry']))
        members[code].append(sggnm)
        points[code].append((sggnm, representative_point(f['geometry'])))

    got = defaultdict(float)
    got_bounds = {}
    got_geoms = defaultdict(list)
    for f in after:
        p = f['properties']
        code, _ = unit_for(p['sidonm'], str(p['sgg']), p['sggnm'], p['unit'])
        got[code] += area_of(f['geometry'])
        got_bounds[code] = union_bounds(
            got_bounds.get(code), bounds_of(f['geometry']))
        got_geoms[code].append(f['geometry'])

    errors = []
    missing = set(want) - set(got)
    extra = set(got) - set(want)
    if missing:
        errors.append('병합 뒤 사라진 단위: %s' % sorted(missing))
    if extra:
        errors.append('병합 뒤 새로 생긴 단위: %s' % sorted(extra))

    for code in sorted(set(want) & set(got)):
        w, g = want[code], got[code]
        if w == 0:
            continue
        if abs(g - w) / w > TOLERANCE:
            errors.append(
                '%s 면적이 %.6f 다. 병합 전 구성원 %d곳 합은 %.6f '
                '(차이 %.4f%%) — 구성원이 빠졌거나 잘못 묶였다.\n     구성원: %s'
                % (code, g, len(members[code]), w, (g - w) / w * 100,
                   ' '.join(members[code])))

        # **면적만 보면 빠진 만큼 다른 자리가 늘어난 도형을 못 가른다.**
        wb, gb = want_bounds[code], got_bounds[code]
        off = max(abs(a - b) for a, b in zip(wb, gb))
        if off > BOUNDS_TOLERANCE:
            errors.append('%s 의 bounds 가 %.6f 만큼 어긋났다 — 도형이 옮겨졌거나 '
                          '다른 곳이 섞였다.' % (code, off))

        lost = [name for name, (px, py) in points[code]
                if not any(contains(g, px, py) for g in got_geoms[code])]
        if lost:
            errors.append('%s 에서 병합 뒤 사라진 구성원: %s'
                          % (code, ' '.join(lost)))

    if errors:
        print('병합 검증 실패:')
        for e in errors:
            print('  -', e)
        sys.exit(1)

    merged = {c for c in want if len(members[c]) > 1}
    # 독도는 `make_asset.py` 가 뒤에 더하므로 여기서는 192개다.
    print('병합 검증 통과 — 단위 %d개 (그중 병합 %d개) · 면적·bounds·구성원 '
          '일치 (독도 제외)' % (len(want), len(merged)))


if __name__ == '__main__':
    main()
