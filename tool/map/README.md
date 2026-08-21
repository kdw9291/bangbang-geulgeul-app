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
| `merge_spec.py` | 긁기 단위 명세 — 병합 7곳과 신설(독도 `DK001`) |
| `make_asset.py` | 투영·정규화·에셋 생성 |
| `verify_merge.py` | 병합 전후 면적 대조 — **구성원 유실을 잡는다** |
| `unit_registry.json` | **긁기 단위 등록부 — 추가만 된다.** 폐지 ID 를 지우지 않고 `retired` 로 남긴다 |
| `catalog.py` | 등록부와 지도를 대조해 서버용 `catalog_manifest.json` 과 canonical hash 를 만든다 |
| `catalog_manifest.json` | **서버용 산출물.** 앱 에셋이 아니다 |
| `catalog_history/` | **버전별 불변 스냅샷.** 그 버전에서 무엇이 active 였는지. **지우거나 고치지 않는다** |
| `test_catalog.py` | 등록부·해시·이력 검증의 반례 27종 |
| `test_merge_spec.py` | 병합 판정·검증 로직의 반례 8종 |
| `sgg_simplified.geojson` | 시군구 256개 (mapshaper 4% 단순화 결과) |
| `sgg_merged.geojson` | 통합 후 192개 — **2단계 산출물** (독도 전) |
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

### 2. 서울·제주·광역시 통합 (256 → 192)

`-dissolve2` 로 내부 경계까지 없애야 한다. 링을 이어 붙이면 서울 링이 25개로 남고
아트가 통합 지역이 아니라 가장 큰 구(서초구)에 놓인다.

```bash
npx -y mapshaper@0.7.52 sgg_simplified.geojson -each "unit = ((sidonm=='서울특별시' || sidonm=='제주특별자치도' || sidonm=='부산광역시' || sidonm=='대구광역시' || sidonm=='대전광역시' || sidonm=='울산광역시' || (sidonm=='인천광역시' && sggnm!='강화군' && sggnm!='옹진군')) ? sidonm : sgg)" -dissolve2 unit copy-fields=sgg,sggnm,sidonm -o format=geojson precision=0.0001 sgg_merged.geojson
```

> **병합 명세는 `merge_spec.py` 가 원본이다.** 카테고리 생성기도 2026-08-14 부터
> 그 파일을 import 한다. **다만 위 mapshaper 명령만은 시도 이름을 하드코딩한다** —
> mapshaper 가 파이썬을 읽지 못해 구조적으로 합칠 수 없다. 병합 대상을 바꾸면
> 둘을 함께 고친다. 한쪽만 고치면 `make_asset.py` 의 검사에 걸려 실패한다.
>
> **인천은 시도 전체가 아니라 9개 구만 합친다** — `sggnm` 조건이 그것이다. 이 단계의
> `sggnm` 은 아직 병합 전이라 믿을 수 있다. 병합 뒤에는 믿을 수 없어져서
> 판정도 검증도 mapshaper 가 남긴 **`unit` 필드**로 한다.

병합이 끝나면 **바로 검증한다.** 에셋을 만들고 나서는 늦다.

```bash
python tool/map/verify_merge.py
python tool/map/test_merge_spec.py
```

`verify_merge.py` 는 병합 전 원본과 **면적을 대조해 구성원 유실을 잡는다.**
`make_asset.py` 의 코드 집합 검사와 개수 트립와이어로는 병합 **그룹 안에서**
한 곳이 빠지는 것을 못 잡는다 — 부산 16곳 중 하나가 빠져도 결과는 여전히 피처
하나라 최종 개수가 193 그대로다. `test_merge_spec.py` 는 그 검증 로직 자체의
반례 8종을 검사한다. 둘 다 앱 테스트가 함께 실행한다.

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

결과: 긁기 단위 **193개** · 시도선 16개 · 489 × 623 km.
(2026-08-20 광역시 통합 전에는 313KB · 232개 · 정점 18,058 이었다.)

### 독도는 여기서 만들어 넣는다 (2026-08-14)

원본 GeoJSON 에 독도가 없어 모양과 위치를 `merge_spec.py` 의 `DOKDO` 가 직접 준다.
실제 0.187km² 는 전국 뷰에서 약 0.5px 라 어찌해도 그릴 수 없다 — 폭 **8km** 로
과장하고, **오른쪽 끝을 울릉군 오른쪽 끝에 맞춰** 울릉도 아래로 3km 띄운다.

오른쪽 끝을 맞추는 이유는 **지도 프레임이 긁기 단위 좌표에서 계산되기 때문**이다.
울릉군보다 오른쪽에 놓으면 지도 폭이 늘고 **남한 전체가 화면에서 작아진다.**
`make_asset.py` 가 이를 검사해 위반하면 실패하며, `test/dokdo_test.dart` 가 생성물 쪽에서
다시 한 번 막는다 (둘 다 일부러 깨뜨려 걸리는 것을 확인했다).

#### 크기를 8km 로 정한 근거 (2026-08-14 실기기)

기준은 사용자가 고른 **"전국 뷰에서 약 6px"** 이다. 지도 폭이 화면 폭에 맞춰지므로
Galaxy S25(360 logical px) 기준 1km 가 약 **0.74 logical px** 다. 처음 잡은 5km 는
실기기에서 **약 3.3px 밖에 안 됐고**, 8km 가 되어야 6px 가 나온다.
울릉도(11.4km)의 70% 라 위계는 유지된다. **화면 폭에 따라 달라지는 값**이므로
더 좁은 기기에서는 더 작게 보인다.

#### 두 섬 간격을 벌리지 않는다 (2026-08-14 실기기)

처음에는 동도·서도 간격을 섬 폭만큼 벌려 놓았는데, 배치 B 가 지역 bounds 를 창으로
쓰기 때문에 **긁기 화면에서 아트가 두 섬에 파편으로 잘려 오른쪽 섬이 거의 단색으로만
보였다.** 다도해에서 겪은 것과 같은 유형이다. 실제 독도는 간격이 151m 로 **섬 폭(각 약
450m)의 3분의 1**이라, 실측 비율을 따르니 지리적으로도 정확해지고 아트도 읽힌다.

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

### 4. 카테고리 신호와 배정 재생성

**지도를 바꿨으면 반드시 함께 돌린다.** 신호는 최종 에셋에서 뽑는다 — 통합
도형은 내부 경계가 사라져 해안 비율이 달라지므로 옛 값을 합산할 수 없다.

```bash
python tool/category/make_signals.py
python tool/category/make_category_map.py
```

두 생성물의 최신성은 앱 테스트가 `--check` 로 확인한다.

### 5. 긁기 단위 등록부와 카탈로그 manifest

**단위가 늘거나 사라지면 `unit_registry.json` 을 먼저 손으로 고친다.**

- 새 단위: `status: "active"` 로 **추가**한다
- 사라진 단위: **지우지 않고** `status` 를 `"retired"` 로 바꾼다.
  ID 를 재사용하면 과거 기록이 엉뚱한 지역으로 옮겨간다
- `version` 을 새 값으로 바꾼다. **version 과 목록은 일대일**이다

그다음 3단계(에셋 생성)를 다시 돌리고 manifest 를 만든다.

```bash
python tool/map/catalog.py
python tool/map/test_catalog.py
```

`version` 은 **`YYYY-MM-DD`** 이고 같은 날 두 번 개편하면 `2026-08-20.2` 처럼 붙인다.
**형식이 계약이다** — 이 값이 그대로 스냅샷 파일 이름이 되므로, 자유 문자열로 두면
`../escape` 같은 값이 이력 디렉토리 밖에 파일을 만든다.

`catalog.py` 는 버전마다 **`catalog_history/<version>.json` 을 한 번 쓰고 다시 쓰지
않는다.** 등록부의 현재 status 만으로는 과거 버전에서 무엇이 active 였는지 알 수
없기 때문이다 — 232 시절 광역시 44곳은 지금 `retired` 지만 그때는 `active` 였다.
**이력 파일을 지우거나 고치면 검사에 걸린다.**

`catalog.py` 는 **지도의 ID 집합이 등록부의 active 집합과 정확히 같은지** 검증한다.
한쪽만 고치면 여기서 실패한다. 에셋 생성기도 이 값을 읽어 `catalogVersion` 과
`catalogHash` 를 에셋에 넣으므로, **등록부가 어긋나면 에셋 자체가 안 만들어진다.**

규칙의 원본은 [`source/backend/SYNC_CONTRACT.md`](../../../backend/SYNC_CONTRACT.md) 5절이다.

## 재현성

**mapshaper 0.7.52 로 2·3단계를 재실행해 최종 에셋이 바이트 단위로 동일함을 확인했다**
(2026-08-14). 파이프라인을 이 디렉토리로 옮긴 뒤에도 같은 결과를 확인했다.

현재 에셋: sha256 `8efe3ca9…` · 306,927 바이트 · 193개 (독도 포함).
2026-08-21 에 `catalogVersion`·`catalogHash` 가 더해져 값이 바뀌었다.
2026-08-20 광역시 통합 전 232개 기준값은 `8858329c…` · 320,378 바이트였다.
**2단계 산출물 `sgg_merged.geojson` 은 독도와 무관하다** — 독도는 3단계에서
`merge_spec.py` 가 만들어 넣는다. 그래서 mapshaper 재현성 검증은 여전히 유효하다.

**`@latest` 를 쓰지 않는다** — 재현성을 보장하지 않는다. 결과가 달라지면 먼저 버전을
0.7.52 로 고정해 비교한다. 참고로 0.7.52 는 `-dissolve2` 를 deprecated 로 경고한다.
