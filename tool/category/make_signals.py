# -*- coding: utf-8 -*-
"""지도 에셋에서 카테고리 배정용 신호를 뽑는다.

## 왜 생겼나 (2026-08-20)

`region-signals.json` 은 손으로 유지하던 파일이었다. 광역시 통합(232 → 193)에서
44개 행이 사라지고 5개가 생기는데, 손으로 고치면 `coast` 를 옛 값에서 합산하게
된다. **통합 도형은 내부 구 경계가 사라져 해안 비율이 달라지므로 합산이 틀린다.**
그래서 최종 에셋에서 다시 뽑는다. (Codex 30회차 설계 검토 지적)

## 값의 뜻

- `area`  — 링 면적의 합 (km²)
- `rings` — 링 개수
- `coast` — **다른 지역과 맞닿지 않는 경계 정점의 비율.** 해안 비율이 아니다.
  휴전선 접경도 여기 잡힌다 — 북한 쪽 인접 지역이 긁기 단위에 없기 때문이다.
  그래서 "내륙인데 바다" 만 잡고 반대는 잡지 않는다.
- `land`  — 면적 / bounds 넓이. 다도해처럼 흩어진 지역이 낮게 나온다.

`coast` 계산은 `test/region_category_test.dart` 의 `_unsharedRatio` 와 같은
격자·허용오차를 쓴다. **둘 중 하나를 바꾸면 다른 하나도 바꾼다.**

## 실행

    python tool/category/make_signals.py           # 생성
    python tool/category/make_signals.py --check   # 최신인지만 확인

`--check` 가 없으면 **지역 코드가 그대로인 채 도형만 바뀔 때 오래된
`coast`·`area`·`land` 가 조용히 통과한다** — 카테고리 생성기는 코드 집합만
비교하기 때문이다 (Codex 30회차 코드 리뷰).
"""
import io
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.join(HERE, '..', '..', 'assets', 'map', 'korea_sgg.json')
OUT = os.path.join(HERE, 'region-signals.json')

CELL = 0.6           # 격자 한 칸 (지도 좌표 = km)
EPS2 = 0.35 * 0.35   # "맞닿았다" 로 볼 거리의 제곱


def ring_area(ring):
    """신발끈 공식. [ring] 은 x, y 가 번갈아 든 평면 배열이다."""
    s = 0.0
    n = len(ring) // 2
    for i in range(n):
        j = (i + 1) % n
        s += ring[i * 2] * ring[j * 2 + 1] - ring[j * 2] * ring[i * 2 + 1]
    return abs(s) / 2


def main():
    data = json.load(io.open(MAP, encoding='utf-8'))
    regions = data['regions']

    # 모든 정점을 격자에 담아 이웃 탐색을 상수 시간으로 만든다.
    grid = defaultdict(list)
    for r in regions:
        for ring in r['r']:
            for i in range(0, len(ring), 2):
                x, y = ring[i], ring[i + 1]
                grid[(int(x // CELL), int(y // CELL))].append((x, y, r['c']))

    out = []
    for r in regions:
        total = free = 0
        for ring in r['r']:
            for i in range(0, len(ring), 2):
                x, y = ring[i], ring[i + 1]
                total += 1
                gx, gy = int(x // CELL), int(y // CELL)
                near = False
                for a in (-1, 0, 1):
                    for b in (-1, 0, 1):
                        for px, py, pc in grid.get((gx + a, gy + b), ()):
                            if pc == r['c']:
                                continue
                            if (px - x) ** 2 + (py - y) ** 2 < EPS2:
                                near = True
                                break
                        if near:
                            break
                    if near:
                        break
                if not near:
                    free += 1

        area = sum(ring_area(ring) for ring in r['r'])
        xs = [x for ring in r['r'] for x in ring[0::2]]
        ys = [y for ring in r['r'] for y in ring[1::2]]
        box = (max(xs) - min(xs)) * (max(ys) - min(ys))
        out.append({
            'c': r['c'],
            'n': r['n'],
            's': data['sidos'][r['s']],
            'area': round(area, 1),
            'rings': len(r['r']),
            'coast': round(free / total if total else 0.0, 3),
            'land': round(area / box if box else 0.0, 3),
        })

    text = json.dumps(out, ensure_ascii=False, indent=1) + '\n'

    if '--check' in sys.argv:
        current = io.open(OUT, encoding='utf-8').read() \
            if os.path.exists(OUT) else ''
        if current != text:
            sys.exit('region-signals.json 이 지도 에셋보다 낡았다. '
                     'python tool/category/make_signals.py 로 다시 만든다.')
        print('신호 %d개 · 최신' % len(out))
        return

    io.open(OUT, 'w', encoding='utf-8', newline='').write(text)
    print('신호 %d개 → %s' % (len(out), os.path.relpath(OUT)))


if __name__ == '__main__':
    main()
