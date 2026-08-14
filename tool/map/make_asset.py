"""앱 번들용 지도 에셋 생성.

경위도를 미리 평면 좌표로 투영하고 원점을 0으로 옮긴다.
런타임에는 삼각함수도 오프셋 계산도 없이 곧바로 Path를 만들 수 있다.

**입력 SGG 는 이미 병합된 GeoJSON 이어야 한다.** 서울·제주를 하나로 합치는 일은
mapshaper `-dissolve2` 가 위상 연산으로 처리한다 (`README.md` 참고).
여기서는 병합된 피처에 코드와 이름을 붙이는 일만 한다 — 명세는 `merge_spec.py`.

## 이 파일은 앱 저장소 안에 있어야 한다

2026-08-14 에 `design/tools/` 에서 옮겼다. 그곳은 git 저장소가 아니라, 앱 저장소만
clone 하면 **에셋을 재생성할 수도 검증할 수도 없었다.** 카테고리 생성기(2026-08-13)와
`merge_spec.py`(2026-08-14)에 이어 **같은 지적을 세 번째 받고서야** 옮겼다.

중간 산출물(`sgg_simplified` · `sgg_merged` · `sido_simplified`)도 함께 두어
네트워크 없이도 에셋을 다시 만들 수 있다. 셋 합쳐 1MB 미만이다.

실행 (`source/android` 에서):
    python tool/map/make_asset.py tool/map/sgg_merged.geojson         tool/map/sido_simplified.geojson assets/map/korea_sgg.json
"""
import json, sys, io, math, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge_spec import unit_for, MERGED_SIDOS  # noqa: E402

SGG, SIDO, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
KX = 111.32 * math.cos(math.radians(36.5)); KY = 110.57
OFFSET = {"47940": (-95.0, 0.0)}          # 울릉군을 동해 안쪽으로 당긴다

SIDOS = ["서울특별시","인천광역시","경기도","강원특별자치도","충청북도","충청남도","대전광역시",
         "세종특별자치시","전북특별자치도","전남광주통합특별시","경상북도","대구광역시",
         "경상남도","부산광역시","울산광역시","제주특별자치도"]
SIDX = {s: i for i, s in enumerate(SIDOS)}

def rings(geom, dx, dy):
    out = []
    polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
    for poly in polys:
        for ring in poly:
            out.append([(c[0]*KX + dx, -c[1]*KY + dy) for c in ring])
    return out

raw = []
for f in json.load(open(SGG, encoding='utf-8'))['features']:
    p = f['properties']
    # 병합된 피처는 sgg/sggnm 이 합쳐진 구 중 하나의 값이라 믿을 수 없다.
    # 시도 이름으로 판단해 명세의 코드·이름을 붙인다.
    code, name = unit_for(p['sidonm'], str(p['sgg']), p['sggnm'])
    dx, dy = OFFSET.get(code, (0.0, 0.0))
    raw.append({'c': code, 'n': name, 's': SIDX[p['sidonm']],
                'rings': rings(f['geometry'], dx, dy)})

# 병합이 실제로 일어났는지 확인한다. mapshaper 단계를 빠뜨리면 서울 25개가
# 전부 같은 코드 '11000' 을 갖고 들어와 조용히 중복된다.
seen = {}
for r in raw:
    seen[r['c']] = seen.get(r['c'], 0) + 1
dup = {c: n for c, n in seen.items() if n > 1}
if dup:
    sys.exit('병합되지 않은 코드가 있다 (mapshaper -dissolve2 단계 확인): %s' % dup)
missing = MERGED_SIDOS - {SIDOS[r['s']] for r in raw}
if missing:
    sys.exit('병합 대상 시도가 입력에 없다: %s' % missing)

xs = [x for r in raw for ring in r['rings'] for x, _ in ring]
ys = [y for r in raw for ring in r['rings'] for _, y in ring]
PAD = 10.0
ox, oy = min(xs) - PAD, min(ys) - PAD
W, H = max(xs) - min(xs) + PAD*2, max(ys) - min(ys) + PAD*2

regions, npts = [], 0
for r in raw:
    rr = []
    for ring in r['rings']:
        flat = []
        for x, y in ring:
            flat.append(round(x - ox, 1)); flat.append(round(y - oy, 1))
        if len(flat) >= 8:              # 삼각형 미만은 버린다
            rr.append(flat); npts += len(flat)//2
    regions.append({'c': r['c'], 'n': r['n'], 's': r['s'], 'r': rr})

# 시도 외곽선 (울릉군 이동을 반영할 수 없어 그대로 둔다)
sido_lines = []
for f in json.load(open(SIDO, encoding='utf-8'))['features']:
    nm = f['properties']['sidonm']
    rr = []
    for ring in rings(f['geometry'], 0, 0):
        flat = []
        for x, y in ring:
            flat.append(round(x - ox, 1)); flat.append(round(y - oy, 1))
        if len(flat) >= 8: rr.append(flat)
    sido_lines.append({'s': SIDX[nm], 'r': rr})

data = {'w': round(W, 1), 'h': round(H, 1), 'sidos': SIDOS,
        'regions': regions, 'sidoLines': sido_lines}
io.open(OUT, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, separators=(',', ':')))

import os
print(f"지역 {len(regions)}개 · 링 {sum(len(r['r']) for r in regions)}개 · 정점 {npts:,}")
print(f"지도 크기 {W:.0f} x {H:.0f} km (가로:세로 = 1 : {H/W:.2f})")
print(f"에셋 {os.path.getsize(OUT)/1024:.0f}KB → {OUT}")
