# -*- coding: utf-8 -*-
"""북한 경계를 Natural Earth 에서 뽑아 배경용 GeoJSON 으로 저장한다.

## 왜 별도 소스인가

앱의 지도 데이터(`vuski/admdongkor`)는 **남한만** 담는다. 북한은 어디서든 새로
가져와야 한다. Natural Earth 를 쓰는 이유는 **완전한 public domain** 이기 때문이다 —
상업 이용·수정·재배포에 제약이 없고 출처 표시도 필요 없다. 저자들이 재정적 권리를
명시적으로 포기했다. 이미 배제한 GADM(재배포 금지)과 정반대다.

## 왜 미리 뽑아 두는가

원본 `ne_50m_admin_0_countries.geojson` 은 242개국 2.9MB 다. 북한 하나만 필요하고,
저장소에 2.9MB 를 넣을 이유가 없다. 뽑은 결과는 수십 KB 다.

**선택 불가한 배경 실루엣**이라 1:50m 정밀도로 충분하다.

실행 (`source/android` 에서, 원본을 받아 둔 뒤):
    python tool/map/extract_nk.py <ne_50m_admin_0_countries.geojson> tool/map/nk.geojson
"""
import io
import json
import sys

SRC, OUT = sys.argv[1], sys.argv[2]

src = json.load(open(SRC, encoding='utf-8'))
hits = [f for f in src['features']
        if (f['properties'].get('ISO_A3') == 'PRK'
            or f['properties'].get('NAME') == 'North Korea')]

if len(hits) != 1:
    sys.exit('북한 피처를 정확히 하나 찾지 못했다: %d개' % len(hits))

geom = hits[0]['geometry']
polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]

# 배경이라 구멍(내부 링)은 쓰지 않는다. 바깥 링만 남긴다.
rings = [poly[0] for poly in polys]
pts = sum(len(r) for r in rings)

out = {
    'type': 'FeatureCollection',
    'note': 'Natural Earth 1:50m — public domain. 배경 실루엣 전용, 선택 불가.',
    'features': [{
        'type': 'Feature',
        'properties': {'name': 'North Korea', 'source': 'Natural Earth 1:50m'},
        'geometry': {'type': 'MultiPolygon', 'coordinates': [[r] for r in rings]},
    }],
}
io.open(OUT, 'w', encoding='utf-8').write(
    json.dumps(out, ensure_ascii=False, separators=(',', ':')))

import os
print('북한 링 %d개 · 정점 %d개 · %.0fKB → %s'
      % (len(rings), pts, os.path.getsize(OUT) / 1024, OUT))
