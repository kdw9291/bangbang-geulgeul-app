# 지도 에셋 재생성

`assets/map/korea_sgg.json` 을 만드는 절차다. **이 디렉토리만으로 완결된다** —
네트워크 없이도 3단계부터 다시 만들 수 있다.

## 왜 앱 저장소 안에 있는가

원래 `design/tools/` 에 있었다. 그곳은 git 저장소가 아니라 **앱 저장소만 clone 하면
에셋을 재생성할 수도, 근거를 검토할 수도, 개편 전후를 비교할 수도 없었다.**

카테고리 생성기(2026-08-13)와 `merge_spec.py`(2026-08-14)가 같은 이유로 지적받았고,
**세 번째 지적을 받고서야** 지도 파이프라인도 옮겼다 (2026-08-14).

## 담긴 파일

| 파일 | 역할 |
|---|---|
| `merge_spec.py` | 긁기 단위 병합 명세 (서울 25개 구 → `11000`, 제주 2개 시 → `50000`) |
| `make_asset.py` | 투영·정규화·에셋 생성 |
| `sgg_simplified.geojson` | 시군구 256개 (mapshaper 4% 단순화 결과) |
| `sgg_merged.geojson` | 서울·제주 통합 후 231개 — **2단계 산출물** |
| `sido_simplified.geojson` | 시도 16개 외곽선 |
| `extract_nk.py` | Natural Earth 에서 북한만 뽑는다 |
| `nk.geojson` | 북한 배경 (Natural Earth 1:50m, **public domain**) — 링 2개·정점 257 |

## 절차

### 1. 원본 (선택 — 이미 단순화본이 있으면 건너뛴다)

[vuski/admdongkor](https://github.com/vuski/admdongkor) `ver20260701` (CC BY 4.0).
**출처 표시가 의무**라 앱 내 정보 화면에 반드시 넣는다.

```bash
npx -y mapshaper@0.7.52 HangJeongDong_ver20260701.geojson -dissolve2 sgg copy-fields=sggnm,sidonm -simplify 4% keep-shapes -o format=geojson precision=0.0001 sgg_simplified.geojson
npx -y mapshaper@0.7.52 sgg_simplified.geojson -dissolve sidonm -o format=geojson precision=0.0001 sido_simplified.geojson
```

3,558개 → 256개, 33MB → 382KB.

### 2. 서울·제주 통합 (256 → 231)

`-dissolve2` 로 내부 경계까지 없애야 한다. 링을 이어 붙이면 서울 링이 25개로 남고
아트가 통합 지역이 아니라 가장 큰 구(서초구)에 놓인다.

```bash
npx -y mapshaper@0.7.52 sgg_simplified.geojson -each "unit = (sidonm=='서울특별시' || sidonm=='제주특별자치도') ? sidonm : sgg" -dissolve2 unit copy-fields=sgg,sggnm,sidonm -o format=geojson precision=0.0001 sgg_merged.geojson
```

> **병합 명세가 세 곳에 중복돼 있다** — `merge_spec.py` 의 `MERGE` · 위 명령의 시도 이름 ·
> `tool/category/make_category_map.py` 의 `11000`·`50000`. **바꾸려면 세 곳을 함께 고친다.**

### 3. 에셋 생성

`source/android` 에서 실행한다.

```bash
python tool/map/make_asset.py tool/map/sgg_merged.geojson tool/map/sido_simplified.geojson assets/map/korea_sgg.json tool/map/nk.geojson
```

> **북한 입력은 필수다.** 빠뜨리면 생성기가 실패한다. 예전에는 선택 인자라
> 문서 명령에 빠져 있어도 조용히 배경 없는 에셋이 나왔다.
> 정말 배경 없이 만들어야 하면 `--without-background` 를 명시한다.

경위도를 등장방형 투영으로 미리 평면화하고 원점을 0으로 옮긴다. 런타임에 삼각함수가 없다.
y 는 화면 좌표(아래로 증가) 기준으로 저장한다 — 렌더에서 y 만 뒤집으면 기울기가 어긋난다.
울릉군만 동해 안쪽으로 95km 당긴다(bbox 를 65km 넓히기 때문).

결과: 310KB · 긁기 단위 231개(정점 18,042) · 시도선 16개(정점 7,534) · 489 × 623 km.

### 3-1. 북한 배경 갱신 (선택 — 이미 `nk.geojson` 이 있으면 건너뛴다)

[Natural Earth](https://www.naturalearthdata.com/) `ne_50m_admin_0_countries` (**public domain** —
상업 이용·수정·재배포 제약 없음, 출처 표시 불필요). 원본 2.9MB 는 저장소에 넣지 않고
북한만 뽑아 6KB 로 둔다. **선택 불가한 배경 실루엣**이라 1:50m 로 충분하다.

```bash
curl -O https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
python tool/map/extract_nk.py ne_50m_admin_0_countries.geojson tool/map/nk.geojson
```

배경은 지도 프레임 계산에서 **제외**된다 — 넣으면 남한 좌표가 재계산되어 화면에서 작아진다.
결과 좌표는 y 가 음수이며(남한 위쪽), 렌더가 클리핑을 풀어야 보인다.

### 4. 카테고리 배정 재생성

에셋을 다시 만들었으면 카테고리 생성물도 갱신한다. Flutter 테스트가 `--check` 로 강제한다.

```bash
python tool/category/make_category_map.py
```

## 재현성

**mapshaper 0.7.52 로 2·3단계를 재실행해 최종 에셋이 바이트 단위로 동일함을 확인했다**
(2026-08-14, sha256 `881ed2bd…`, 317,017 바이트). 파이프라인을 이 디렉토리로 옮긴 뒤에도
같은 결과를 확인했다.

**`@latest` 를 쓰지 않는다** — 재현성을 보장하지 않는다. 결과가 달라지면 먼저 버전을
0.7.52 로 고정해 비교한다. 참고로 0.7.52 는 `-dissolve2` 를 deprecated 로 경고한다.
