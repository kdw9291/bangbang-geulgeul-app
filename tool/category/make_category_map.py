# -*- coding: utf-8 -*-
"""231개 긁기 단위 카테고리 배정표 — 단일 원본.

배정 대상은 시군구가 아니라 **긁기 단위**(`scratchUnitId`)다. 대부분은 통계청
시군구 코드 5자리와 같지만, 2026-08-14 통합으로 서울 `11000` · 제주 `50000` 은
통계청 코드가 아닌 합성 ID 다. 병합 명세는 `design/tools/merge_spec.py` 이나
**이 파일이 그것을 import 하지는 않는다** — 아래 두 코드는 여기에도 적혀 있다.

카테고리는 **여행자가 떠올리는 대표 이미지**다 (2026-08-13 사용자 결정).
객관적 지형 분류가 아니다. 그래서 지도 기하 신호는 후보를 좁히고 모순을 잡는 데만 쓰고,
배정 자체는 근거를 적으며 손으로 정한다.

지도 에셋에는 고도·토지이용·인구·하천 데이터가 없다. 산과 들판을 가를 신호가
아예 없으므로 자동 분류가 불가능하다는 것이 Codex 검토(2026-08-13)의 결론이다.

**이 파일은 앱 저장소 안에 있어야 한다.** 기획 문서 쪽(비 git 디렉토리)에 두었더니
앱 저장소만 clone 하면 배정을 재생성할 수도, 근거를 검토할 수도, 행정구역 개편 전후를
비교할 수도 없었다 (Codex 검토 2026-08-13).

실행:
    python tool/category/make_category_map.py           # 생성
    python tool/category/make_category_map.py --check   # 생성물이 최신인지만 확인
산출:
    tool/category/assignment.md      검토용 표 (근거 포함)
    lib/region_category.g.dart       앱이 쓰는 최종 맵
"""
import io
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(os.path.dirname(HERE))  # source/android
ASSET = os.path.join(APP, 'assets/map/korea_sgg.json')
SIGNALS = os.path.join(HERE, 'region-signals.json')
MD_OUT = os.path.join(HERE, 'assignment.md')
DART_OUT = os.path.join(APP, 'lib/region_category.g.dart')

# 아이콘 8종
CATS = ['mountain', 'sea', 'island', 'city', 'heritage', 'hotspring', 'river', 'field']

# 계획된 랜드마크 36개. `design/art-landmark-candidates.md` 와 같아야 한다.
# 여기 두는 이유는 **최종 220개 기준 분포**를 기계로 검사하기 위해서다.
# 랜드마크가 있는 지역도 카테고리를 폴백으로 가지므로 배정에서 빼지는 않는다.
# 서울(11170 용산구)·제주(50110 제주시)는 통합으로 코드가 바뀌었다.
PLANNED_LANDMARKS = '''
11000 28710 28720 41115 41670 51210 51760 43720 43800 44760 44150 30200 30110
36110 52190 52800 12150 12210 47130 47170 27140 27710 48220 48890 26410 26350
31710 31170 50000 41610 41830 41820 28245 26200 48170 47940
'''.split()

# code -> (category, reason)
A = {}


def put(codes, cat, reason):
    for c in codes.split():
        if c in A:
            raise SystemExit('중복 배정: %s' % c)
        A[c] = (cat, reason)


# ── 서울특별시 1 ───────────────────────────────────────────────
# 2026-08-14 사용자 결정으로 25개 구를 하나의 긁기 단위로 합쳤다.
# 병합 명세는 `design/tools/merge_spec.py`, 코드는 `sgg` 가 아니라 합성 ID 다.
put('11000', 'city', '서울 도심 — 25개 구를 합친 긁기 단위')

# ── 인천광역시 11 ──────────────────────────────────────────────
put('28155', 'island', '영종도 — 완전 섬')
put('28710', 'island', '강화도 — 완전 섬')
put('28720', 'island', '옹진군 — 다도해')
put('28125', 'sea', '개항장·연안부두')
put('28185', 'city', '송도 신도시 — 해안이지만 도시 인상이 앞선다')
put('28177 28200 28237 28245 28275 28290', 'city', '인천 도심권')

# ── 경기도 47 ──────────────────────────────────────────────────
put('''41111 41113 41115 41117 41131 41133 41135 41150 41171 41173 41210 41250
       41281 41285 41287 41290 41310 41370 41410 41430 41463 41465 41593 41597
       41595 41192 41194 41196 41271''', 'city', '수도권 도심')
put('41273', 'island', '대부도 — 흩어진 섬')
put('41591', 'sea', '서해안 궁평항')
put('41390', 'sea', '시흥갯골 갯벌')
put('41360', 'river', '북한강·팔당 유원지가 대표 이미지')
put('41450', 'river', '한강변 — 미사·팔당')
put('41480', 'river', '임진강 — 해안이 아니라 강과 접경')
put('41800', 'river', '한탄강 — 해안이 아니라 강과 접경')
put('41670', 'river', '남한강 — 세종대왕릉 랜드마크의 폴백')
put('41820', 'river', '북한강·자라섬')
put('41830', 'river', '두물머리 — 남한강과 북한강이 만나는 곳')
put('41610', 'mountain', '남한산성 — 산성이 대표')
put('41650', 'mountain', '산정호수·백운계곡')
put('41220', 'field', '평택 평야')
put('41500', 'field', '이천 쌀과 도자기')
put('41550', 'field', '안성 평야와 안성맞춤')
put('41570', 'field', '김포평야')
put('41630', 'field', '양주 농촌')
put('41461', 'field', '용인 처인 농촌 — 기흥·수지와 성격이 다르다')

# ── 강원특별자치도 18 ──────────────────────────────────────────
put('51150', 'sea', '경포해변과 정동진')
put('51170', 'sea', '망상해변과 추암 촛대바위')
put('51230', 'sea', '삼척 해안과 죽서루')
put('51210', 'sea', '속초 해변과 항구 — 설악산 랜드마크의 폴백')
put('51820', 'sea', '화진포와 통일전망대')
put('51830', 'sea', '낙산해변과 서핑')
put('51190', 'mountain', '태백산과 고원')
put('51720', 'mountain', '홍천 산간 — 국내 최대 면적 시군구')
put('51760', 'mountain', '대관령 고원 — 월정사 랜드마크의 폴백')
put('51770', 'mountain', '정선 아우라지와 탄광 산간')
put('51800', 'mountain', '펀치볼과 두타연')
put('51810', 'mountain', '내설악과 내린천')
put('51730', 'mountain', '횡성 산간과 한우')
put('51110', 'river', '의암호·소양강이 도시의 얼굴')
put('51750', 'river', '동강 래프팅과 어라연')
put('51780', 'river', '한탄강 — 해안이 아니라 강과 접경')
put('51790', 'river', '북한강 — 해안이 아니라 강과 접경')
put('51130', 'mountain', '치악산과 구룡사')

# ── 충청북도 14 ────────────────────────────────────────────────
put('43111 43112 43113 43114', 'city', '청주 도심')
put('43130', 'hotspring', '수안보온천 — 국내 대표 온천지')
put('43150', 'river', '청풍호와 남한강 수계')
put('43730', 'river', '금강·대청호')
put('43800', 'river', '남한강 — 도담삼봉 랜드마크의 폴백')
put('43720', 'mountain', '속리산 — 법주사 랜드마크의 폴백')
put('43760', 'mountain', '괴산 산막이옛길과 산간')
put('43740', 'field', '영동 포도와 과수')
put('43750', 'field', '진천 농촌')
put('43770', 'field', '음성 농촌')
put('43745', 'field', '증평 농촌')

# ── 충청남도 16 ────────────────────────────────────────────────
put('44131 44133', 'city', '천안 도심')
put('44180', 'sea', '대천해수욕장')
put('44210', 'sea', '간월도와 서산 갯벌')
put('44270', 'sea', '당진 서해안과 왜목마을')
put('44770', 'sea', '춘장대해변과 장항')
put('44825', 'sea', '안면도와 꽃지해변')
put('44200', 'hotspring', '온양온천 — 국내 대표 온천지')
put('44150', 'heritage', '공산성·무령왕릉 — 백제 왕도')
put('44760', 'heritage', '정림사지·부소산성 — 백제 왕도')
put('44250', 'mountain', '계룡산 자락의 군사도시')
put('44790', 'mountain', '칠갑산과 장곡사')
put('44230', 'field', '논산평야와 딸기')
put('44710', 'field', '금산 인삼')
put('44800', 'field', '홍성 내포 들녘')
put('44810', 'field', '예당평야')

# ── 대전광역시 5 ───────────────────────────────────────────────
put('30200', 'hotspring', '유성온천 — 국내 대표 온천지')
put('30110 30140 30170 30230', 'city', '대전 도심')

# ── 세종특별자치시 1 ───────────────────────────────────────────
put('36110', 'city', '행정중심복합도시')

# ── 전북특별자치도 15 ─────────────────────────────────────────
put('52111', 'heritage', '전주한옥마을과 경기전')
# 한옥마을은 완산구다. 덕진구까지 같은 근거를 붙였던 것을 바로잡는다.
put('52113', 'city', '전북대·덕진공원 일대 시가지')
put('52140', 'heritage', '미륵사지 — 백제 유적')
put('52130', 'sea', '근대 항구')
put('52800', 'sea', '변산반도 — 채석강 랜드마크의 폴백')
put('52180', 'mountain', '내장산 단풍')
put('52710', 'mountain', '대둔산과 모악산')
put('52720', 'mountain', '마이산 탑사')
put('52730', 'mountain', '덕유산과 무주구천동')
put('52740', 'mountain', '장수 고랭지 산간')
put('52190', 'heritage', '광한루 — 랜드마크의 폴백')
put('52210', 'field', '김제평야 지평선')
put('52750', 'field', '임실 치즈마을')
put('52770', 'field', '순창 고추장마을')
put('52790', 'field', '고창 청보리밭')

# ── 전남광주통합특별시 27 ─────────────────────────────────────
put('12210 12240 12270 12300 12330', 'city', '광주 도심')
put('12110', 'sea', '목포항과 유달산')
put('12190', 'sea', '광양만과 매화마을')
put('12740', 'sea', '고흥 바다와 나로우주센터')
put('12790', 'sea', '땅끝마을')
put('12810', 'sea', '무안 갯벌')
put('12830', 'sea', '법성포와 굴비')
put('12130', 'island', '여수 — 다도해')
put('12850', 'island', '완도 — 다도해')
put('12860', 'island', '진도 — 다도해')
put('12870', 'island', '신안 — 다도해')
put('12720', 'river', '섬진강과 곡성 기차마을')
put('12730', 'mountain', '지리산 노고단')
put('12760', 'mountain', '화순 운주사와 산간')
put('12840', 'mountain', '백양사와 축령산')
put('12800', 'mountain', '월출산 기암괴석')
put('12150', 'field', '순천만 습지와 농촌 — 랜드마크의 폴백')
put('12170', 'field', '나주평야')
put('12710', 'field', '죽녹원 대숲과 메타세쿼이아길')
put('12750', 'field', '보성 녹차밭')
put('12770', 'field', '장흥 농촌과 정남진')
put('12820', 'field', '함평 나비축제와 들녘')
put('12780', 'heritage', '다산초당과 고려청자 도요지')

# ── 경상북도 23 ────────────────────────────────────────────────
put('47111', 'sea', '호미곶·영일만')
put('47113', 'city', '포항 북부 도심과 영일대')
put('47190', 'city', '구미 산업도시')
put('47290', 'city', '경산 대학도시')
put('47130', 'heritage', '신라 왕도 — 첨성대 랜드마크의 폴백')
put('47170', 'heritage', '하회마을 — 랜드마크의 폴백')
put('47210', 'heritage', '부석사·소수서원')
put('47830', 'heritage', '대가야 고분군')
put('47770', 'sea', '영덕 대게와 강구항')
put('47930', 'sea', '울진 해안과 후포항')
put('47940', 'island', '울릉도 — 완전 섬')
put('47150', 'mountain', '직지사와 황악산')
put('47280', 'mountain', '문경새재')
put('47750', 'mountain', '주왕산과 주산지')
put('47760', 'mountain', '일월산과 오지 산간')
put('47920', 'mountain', '봉화 백두대간과 청량산')
put('47230', 'field', '영천 과수 농촌')
put('47250', 'field', '상주 곶감과 평야')
put('47730', 'field', '의성 마늘 농촌')
put('47820', 'field', '청도 감과 소싸움')
put('47840', 'field', '성주 참외')
put('47850', 'field', '칠곡 낙동강변 농촌')
put('47900', 'field', '예천 농촌')

# ── 대구광역시 9 ───────────────────────────────────────────────
put('27110 27140 27170 27200 27230 27260 27290', 'city', '대구 도심')
put('27710', 'mountain', '비슬산 — 랜드마크의 폴백')
put('27720', 'field', '군위 농촌')

# ── 경상남도 22 ────────────────────────────────────────────────
put('48310', 'island', '거제도 — 완전 섬')
put('48840', 'island', '남해도 — 완전 섬')
put('48220', 'island', '통영 — 다도해. 한려수도 랜드마크의 폴백')
put('48240', 'sea', '사천 삼천포 바다와 케이블카')
put('48820', 'sea', '고성 공룡발자국 해안')
put('48125', 'sea', '마산만과 저도 연륙교')
put('48129', 'sea', '진해 군항과 바다')
put('48121 48123 48127 48250 48330', 'city', '창원·김해·양산 도심')
put('48170', 'heritage', '진주성 촉석루 — 랜드마크의 폴백')
put('48270', 'heritage', '영남루와 표충사')
put('48740', 'river', '우포늪 — 국내 최대 자연 늪')
put('48850', 'river', '섬진강·화개장터')
put('48860', 'mountain', '지리산 중산리')
put('48870', 'mountain', '지리산 함양 자락과 상림')
put('48880', 'mountain', '거창 덕유산 자락')
put('48890', 'mountain', '가야산 — 해인사 랜드마크의 폴백')
put('48720', 'field', '의령 농촌')
put('48730', 'field', '함안 농촌')

# ── 부산광역시 16 ──────────────────────────────────────────────
put('26140 26200 26290 26350 26380 26500 26710', 'sea', '부산 해안')
put('26260', 'hotspring', '동래온천 — 국내 대표 온천지')
put('26410', 'mountain', '금정산 — 범어사 랜드마크의 폴백')
# 을숙도는 사하구다. 강서구 소재로 근거를 바로잡는다.
put('26440', 'river', '낙동강 하구와 대저·맥도생태공원')
put('26110 26170 26230 26320 26470 26530', 'city', '부산 도심')

# ── 울산광역시 5 ───────────────────────────────────────────────
put('31140 31170 31200', 'sea', '울산 해안')
put('31110', 'city', '울산 도심')
put('31710', 'mountain', '영남알프스 — 반구대 랜드마크의 폴백')

# ── 제주특별자치도 1 ───────────────────────────────────────────
# 2026-08-14 사용자 결정으로 제주시·서귀포시를 하나로 합쳤다.
put('50000', 'island', '제주도 — 돌하르방 랜드마크의 폴백')


def main():
    data = json.load(io.open(ASSET, encoding='utf-8'))
    codes = [r['c'] for r in data['regions']]
    names = {r['c']: r['n'] for r in data['regions']}
    sidos = {r['c']: data['sidos'][r['s']] for r in data['regions']}
    signals = {r['c']: r for r in json.load(io.open(SIGNALS, encoding='utf-8'))}

    errors = []

    # 1. 지도 코드와 배정 코드가 정확히 일치해야 한다.
    missing = [c for c in codes if c not in A]
    extra = [c for c in A if c not in codes]
    if missing:
        errors.append('미배정 %d개: %s' % (len(missing), ' '.join(
            '%s(%s)' % (c, names[c]) for c in missing[:20])))
    if extra:
        errors.append('지도에 없는 코드 %d개: %s' % (len(extra), ' '.join(extra[:20])))

    # 2. 신호 데이터도 같은 코드 집합이어야 한다.
    #    빠진 행이 있으면 아래 모순 검사가 조용히 건너뛰어 버린다.
    if set(signals) != set(codes):
        errors.append('신호 데이터 코드 집합이 지도와 다르다 (신호 %d개)' % len(signals))

    # 3. 알 수 없는 카테고리가 없어야 한다.
    for c, (cat, _) in A.items():
        if cat not in CATS:
            errors.append('알 수 없는 카테고리 %s: %s' % (cat, c))

    # 4. **모든 행에 근거가 있어야 한다.**
    #    처음에는 온천·유적·강만 검사했는데, 사용자 결정은 모든 행마다 근거였다.
    for c, (cat, reason) in A.items():
        if len(reason.strip()) < 4:
            errors.append('%s(%s) %s 에 근거가 없다' % (c, names.get(c, '?'), cat))

    # 5. 계획된 랜드마크 코드가 지도에 실제로 있어야 한다.
    for c in PLANNED_LANDMARKS:
        if c not in codes:
            errors.append('랜드마크 코드가 지도에 없다: %s' % c)
    if len(set(PLANNED_LANDMARKS)) != len(PLANNED_LANDMARKS):
        errors.append('랜드마크 목록에 중복이 있다')

    # 6. 내륙인데 바다·섬이면 모순이다.
    #    반대(해안인데 내륙 카테고리)는 오류가 아니다 — 휴전선 접경이 해안처럼
    #    보이고, 카테고리 기준이 지형이 아니라 여행자 대표 이미지이기 때문이다.
    for c, (cat, _) in A.items():
        s = signals.get(c)
        if not s:
            continue
        if cat in ('sea', 'island') and s['coast'] < 0.05:
            errors.append('%s(%s) 는 미접촉 경계 %.3f 인데 %s' % (
                c, names.get(c, '?'), s['coast'], cat))

    # 경고: 외부 경계가 큰데 바다·섬이 아니면 근거를 확인하라는 뜻.
    # 처음에는 mountain/field/city 만 봤는데 그러면 river 로 간 부산 강서구가
    # 빠졌다. 바다·섬이 아닌 전부를 대상으로 한다.
    warns = []
    for c, (cat, reason) in A.items():
        s = signals.get(c)
        if not s:
            continue
        if cat not in ('sea', 'island') and s['coast'] >= 0.35:
            warns.append('%s %s(%s) coast=%.2f → %s : %s' % (
                sidos[c][:4], names[c], c, s['coast'], cat, reason))

    if errors:
        print('실패:')
        for e in errors:
            print('  -', e)
        sys.exit(1)

    dist = Counter(cat for cat, _ in A.values())
    main_only = Counter(A[c][0] for c in codes if c not in set(PLANNED_LANDMARKS))
    total_main = sum(main_only.values())

    check = '--check' in sys.argv
    md = _markdown(codes, names, sidos, signals, dist, main_only, total_main)
    dart = _dart(codes)

    if check:
        stale = []
        for path, want in ((MD_OUT, md), (DART_OUT, dart)):
            have = io.open(path, encoding='utf-8').read() if os.path.exists(path) else None
            if have != want:
                stale.append(os.path.relpath(path, APP))
        if stale:
            print('생성물이 최신이 아니다: %s' % ', '.join(stale))
            print('  python tool/category/make_category_map.py 를 실행할 것')
            sys.exit(1)
        print('생성물 최신 · 배정 %d개 · 검사 통과' % len(A))
        return

    print('배정 %d개 · 검사 통과' % len(A))
    print('전체 분포:', ' '.join('%s=%d' % (k, dist[k]) for k in CATS))
    print('주 노출 %d개 (랜드마크 %d개 제외): %s' % (
        total_main, len(PLANNED_LANDMARKS),
        ' '.join('%s=%d' % (k, main_only[k]) for k in CATS)))
    top = main_only.most_common(1)[0]
    print('  최다 %s %d개 (%.1f%%)' % (top[0], top[1], top[1] / total_main * 100))
    if warns:
        print('\n경고 %d건 (오류 아님 — 근거를 확인할 것):' % len(warns))
        for w in warns:
            print('  -', w)

    io.open(MD_OUT, 'w', encoding='utf-8').write(md)
    io.open(DART_OUT, 'w', encoding='utf-8').write(dart)
    print('→ tool/category/assignment.md')
    print('→ lib/region_category.g.dart')


def _markdown(codes, names, sidos, signals, dist, main_only, total_main):
    o = []
    w = o.append
    w('# %d개 긁기 단위 카테고리 배정 (확정)\n\n' % len(codes))
    w('> **이 파일은 자동 생성된다. 고치려면 `tool/category/make_category_map.py` 를\n')
    w('> 고치고 다시 실행한다.** 앱이 쓰는 맵도 같은 스크립트가 만든다.\n')
    w('> `--check` 로 생성물이 최신인지 확인할 수 있다.\n\n')
    w('카테고리는 **여행자가 떠올리는 대표 이미지**다 (2026-08-13 사용자 결정).\n')
    w('객관적 지형 분류가 아니므로 "바다에 접하지만 농촌 인상" 인 곳은 들판으로 간다.\n\n')
    w('`미접촉경계` 는 **해안 비율이 아니다.** 다른 지역과 맞닿지 않는 경계 정점의 비율이며,\n')
    w('북한 쪽 인접 지역이 데이터에 없어 **휴전선 접경도 여기 잡힌다**.\n\n')
    w('## 분포\n\n')
    w('| 카테고리 | 전체 256 | 주 노출 %d |\n|---|---|---|\n' % total_main)
    for k in CATS:
        w('| %s | %d | %d |\n' % (k, dist[k], main_only[k]))
    w('\n주 노출은 계획된 랜드마크 %d개를 뺀 값이다. 그 지역들은 카테고리를 폴백으로만 쓴다.\n\n'
      % len(PLANNED_LANDMARKS))
    w('## 배정표\n\n')
    bysido = defaultdict(list)
    for c in codes:
        bysido[sidos[c]].append(c)
    lm = set(PLANNED_LANDMARKS)
    for s in bysido:
        w('### %s (%d)\n\n' % (s, len(bysido[s])))
        w('| 코드 | 지역 | 카테고리 | 근거 | 미접촉경계 | 랜드마크 |\n')
        w('|---|---|---|---|---|---|\n')
        for c in bysido[s]:
            cat, reason = A[c]
            sig = signals.get(c, {})
            w('| %s | %s | `%s` | %s | %.2f | %s |\n' % (
                c, names[c], cat, reason, sig.get('coast', 0),
                '있음' if c in lm else ''))
        w('\n')
    return ''.join(o)


def _dart(codes):
    o = []
    w = o.append
    w('// 자동 생성 파일 — 직접 고치지 말 것.\n')
    w('// 원본: tool/category/make_category_map.py\n')
    w('// 다시 만들기: python tool/category/make_category_map.py\n')
    w('// 최신 확인:  python tool/category/make_category_map.py --check\n')
    w('//\n')
    w('// 카테고리는 여행자가 떠올리는 대표 이미지다 (2026-08-13 사용자 결정).\n')
    w('// 배정 근거는 tool/category/assignment.md 에 있다.\n\n')
    w("import 'art_category.dart';\n\n")
    w('/// `Region.scratchUnitId` → 카테고리. 랜드마크가 있는 지역도 폴백으로 가진다.\n')
    w('///\n')
    w('/// 키는 통계청 시군구 코드와 대부분 같지만 전부는 아니다 —\n')
    w('/// 서울 `11000` · 제주 `50000` 은 통합으로 생긴 합성 ID 다.\n')
    w('const Map<String, ArtCategory> kRegionCategory = {\n')
    for c in codes:
        cat, reason = A[c]
        w("  '%s': ArtCategory.%s, // %s\n" % (c, cat, reason))
    w('};\n\n')
    w('/// 계획된 랜드마크 %d개. 분포 검사에서 주 노출을 계산할 때 쓴다.\n'
      % len(PLANNED_LANDMARKS))
    w('const Set<String> kPlannedLandmarks = {\n')
    for c in PLANNED_LANDMARKS:
        w("  '%s',\n" % c)
    w('};\n')
    return ''.join(o)


if __name__ == '__main__':
    main()
