// 자동 생성 파일 — 직접 고치지 말 것.
// 원본: tool/category/make_category_map.py
// 다시 만들기: python tool/category/make_category_map.py
// 최신 확인:  python tool/category/make_category_map.py --check
//
// 카테고리는 여행자가 떠올리는 대표 이미지다 (2026-08-13 사용자 결정).
// 배정 근거는 tool/category/assignment.md 에 있다.

import 'art_category.dart';

/// `Region.scratchUnitId` → 카테고리. 랜드마크가 있는 지역도 폴백으로 가진다.
///
/// 키는 통계청 시군구 코드와 대부분 같지만 전부는 아니다 —
/// 서울 `11000` · 제주 `50000` 과 2026-08-20 광역시 통합으로 생긴
/// 부산 `26000` · 대구 `27000` · 인천 `28000` · 대전 `30000` ·
/// 울산 `31000` 은 합성 ID 이고, 독도 `DK001` 은 신설한 긁기 단위라
/// 통계청 네임스페이스 밖이다. 인천은 강화군 `28710` · 옹진군 `28720` 이
/// 통합에서 빠져 그대로 남는다.
const Map<String, ArtCategory> kRegionCategory = {
  '11000': ArtCategory.city, // 서울 도심 — 25개 구를 합친 긁기 단위
  '26000': ArtCategory.sea, // 부산 해안 — 해운대 랜드마크의 폴백
  '27000': ArtCategory.city, // 대구 도심 — 팔공산 랜드마크의 폴백
  '28000': ArtCategory.city, // 인천 도심 — 계양산 랜드마크의 폴백
  '28710': ArtCategory.island, // 강화도 — 완전 섬
  '28720': ArtCategory.island, // 옹진군 — 다도해
  '12210': ArtCategory.city, // 광주 도심
  '12240': ArtCategory.city, // 광주 도심
  '12270': ArtCategory.city, // 광주 도심
  '12300': ArtCategory.city, // 광주 도심
  '12330': ArtCategory.city, // 광주 도심
  '30000': ArtCategory.city, // 대전 도심 — 계룡산 랜드마크의 폴백
  '31000': ArtCategory.city, // 울산 도심 — 반구대 랜드마크의 폴백
  '36110': ArtCategory.city, // 행정중심복합도시
  '41111': ArtCategory.city, // 수도권 도심
  '41113': ArtCategory.city, // 수도권 도심
  '41115': ArtCategory.city, // 수도권 도심
  '41117': ArtCategory.city, // 수도권 도심
  '41131': ArtCategory.city, // 수도권 도심
  '41133': ArtCategory.city, // 수도권 도심
  '41135': ArtCategory.city, // 수도권 도심
  '41150': ArtCategory.city, // 수도권 도심
  '41171': ArtCategory.city, // 수도권 도심
  '41173': ArtCategory.city, // 수도권 도심
  '41210': ArtCategory.city, // 수도권 도심
  '41220': ArtCategory.field, // 평택 평야
  '41250': ArtCategory.city, // 수도권 도심
  '41271': ArtCategory.city, // 수도권 도심
  '41273': ArtCategory.island, // 대부도 — 흩어진 섬
  '41281': ArtCategory.city, // 수도권 도심
  '41285': ArtCategory.city, // 수도권 도심
  '41287': ArtCategory.city, // 수도권 도심
  '41290': ArtCategory.city, // 수도권 도심
  '41310': ArtCategory.city, // 수도권 도심
  '41360': ArtCategory.river, // 북한강·팔당 유원지가 대표 이미지
  '41370': ArtCategory.city, // 수도권 도심
  '41390': ArtCategory.sea, // 시흥갯골 갯벌
  '41410': ArtCategory.city, // 수도권 도심
  '41430': ArtCategory.city, // 수도권 도심
  '41450': ArtCategory.river, // 한강변 — 미사·팔당
  '41461': ArtCategory.field, // 용인 처인 농촌 — 기흥·수지와 성격이 다르다
  '41463': ArtCategory.city, // 수도권 도심
  '41465': ArtCategory.city, // 수도권 도심
  '41480': ArtCategory.river, // 임진강 — 해안이 아니라 강과 접경
  '41500': ArtCategory.field, // 이천 쌀과 도자기
  '41550': ArtCategory.field, // 안성 평야와 안성맞춤
  '41570': ArtCategory.field, // 김포평야
  '41593': ArtCategory.city, // 수도권 도심
  '41591': ArtCategory.sea, // 서해안 궁평항
  '41597': ArtCategory.city, // 수도권 도심
  '41595': ArtCategory.city, // 수도권 도심
  '41610': ArtCategory.mountain, // 남한산성 — 산성이 대표
  '41630': ArtCategory.field, // 양주 농촌
  '41650': ArtCategory.mountain, // 산정호수·백운계곡
  '41670': ArtCategory.river, // 남한강 — 세종대왕릉 랜드마크의 폴백
  '41800': ArtCategory.river, // 한탄강 — 해안이 아니라 강과 접경
  '41820': ArtCategory.river, // 북한강·자라섬
  '41830': ArtCategory.river, // 두물머리 — 남한강과 북한강이 만나는 곳
  '51110': ArtCategory.river, // 의암호·소양강이 도시의 얼굴
  '51130': ArtCategory.mountain, // 치악산과 구룡사
  '51150': ArtCategory.sea, // 경포해변과 정동진
  '51170': ArtCategory.sea, // 망상해변과 추암 촛대바위
  '51190': ArtCategory.mountain, // 태백산과 고원
  '51210': ArtCategory.sea, // 속초 해변과 항구 — 설악산 랜드마크의 폴백
  '51230': ArtCategory.sea, // 삼척 해안과 죽서루
  '51720': ArtCategory.mountain, // 홍천 산간 — 국내 최대 면적 시군구
  '51730': ArtCategory.mountain, // 횡성 산간과 한우
  '51750': ArtCategory.river, // 동강 래프팅과 어라연
  '51760': ArtCategory.mountain, // 대관령 고원 — 월정사 랜드마크의 폴백
  '51770': ArtCategory.mountain, // 정선 아우라지와 탄광 산간
  '51780': ArtCategory.river, // 한탄강 — 해안이 아니라 강과 접경
  '51790': ArtCategory.river, // 북한강 — 해안이 아니라 강과 접경
  '51800': ArtCategory.mountain, // 펀치볼과 두타연
  '51810': ArtCategory.mountain, // 내설악과 내린천
  '51820': ArtCategory.sea, // 화진포와 통일전망대
  '51830': ArtCategory.sea, // 낙산해변과 서핑
  '43130': ArtCategory.hotspring, // 수안보온천 — 국내 대표 온천지
  '43150': ArtCategory.river, // 청풍호와 남한강 수계
  '43111': ArtCategory.city, // 청주 도심
  '43112': ArtCategory.city, // 청주 도심
  '43113': ArtCategory.city, // 청주 도심
  '43114': ArtCategory.city, // 청주 도심
  '43720': ArtCategory.mountain, // 속리산 — 법주사 랜드마크의 폴백
  '43730': ArtCategory.river, // 금강·대청호
  '43740': ArtCategory.field, // 영동 포도와 과수
  '43750': ArtCategory.field, // 진천 농촌
  '43760': ArtCategory.mountain, // 괴산 산막이옛길과 산간
  '43770': ArtCategory.field, // 음성 농촌
  '43800': ArtCategory.river, // 남한강 — 도담삼봉 랜드마크의 폴백
  '43745': ArtCategory.field, // 증평 농촌
  '44131': ArtCategory.city, // 천안 도심
  '44133': ArtCategory.city, // 천안 도심
  '44150': ArtCategory.heritage, // 공산성·무령왕릉 — 백제 왕도
  '44180': ArtCategory.sea, // 대천해수욕장
  '44200': ArtCategory.hotspring, // 온양온천 — 국내 대표 온천지
  '44210': ArtCategory.sea, // 간월도와 서산 갯벌
  '44230': ArtCategory.field, // 논산평야와 딸기
  '44250': ArtCategory.mountain, // 계룡산 자락의 군사도시
  '44270': ArtCategory.sea, // 당진 서해안과 왜목마을
  '44710': ArtCategory.field, // 금산 인삼
  '44760': ArtCategory.heritage, // 정림사지·부소산성 — 백제 왕도
  '44770': ArtCategory.sea, // 춘장대해변과 장항
  '44790': ArtCategory.mountain, // 칠갑산과 장곡사
  '44800': ArtCategory.field, // 홍성 내포 들녘
  '44810': ArtCategory.field, // 예당평야
  '44825': ArtCategory.sea, // 안면도와 꽃지해변
  '12110': ArtCategory.sea, // 목포항과 유달산
  '12130': ArtCategory.island, // 여수 — 다도해
  '12150': ArtCategory.field, // 순천만 습지와 농촌 — 랜드마크의 폴백
  '12170': ArtCategory.field, // 나주평야
  '12190': ArtCategory.sea, // 광양만과 매화마을
  '12710': ArtCategory.field, // 죽녹원 대숲과 메타세쿼이아길
  '12720': ArtCategory.river, // 섬진강과 곡성 기차마을
  '12730': ArtCategory.mountain, // 지리산 노고단
  '12740': ArtCategory.sea, // 고흥 바다와 나로우주센터
  '12750': ArtCategory.field, // 보성 녹차밭
  '12760': ArtCategory.mountain, // 화순 운주사와 산간
  '12770': ArtCategory.field, // 장흥 농촌과 정남진
  '12780': ArtCategory.heritage, // 다산초당과 고려청자 도요지
  '12790': ArtCategory.sea, // 땅끝마을
  '12800': ArtCategory.mountain, // 월출산 기암괴석
  '12810': ArtCategory.sea, // 무안 갯벌
  '12820': ArtCategory.field, // 함평 나비축제와 들녘
  '12830': ArtCategory.sea, // 법성포와 굴비
  '12840': ArtCategory.mountain, // 백양사와 축령산
  '12850': ArtCategory.island, // 완도 — 다도해
  '12860': ArtCategory.island, // 진도 — 다도해
  '12870': ArtCategory.island, // 신안 — 다도해
  '47111': ArtCategory.sea, // 호미곶·영일만
  '47113': ArtCategory.city, // 포항 북부 도심과 영일대
  '47130': ArtCategory.heritage, // 신라 왕도 — 첨성대 랜드마크의 폴백
  '47150': ArtCategory.mountain, // 직지사와 황악산
  '47170': ArtCategory.heritage, // 하회마을 — 랜드마크의 폴백
  '47190': ArtCategory.city, // 구미 산업도시
  '47210': ArtCategory.heritage, // 부석사·소수서원
  '47230': ArtCategory.field, // 영천 과수 농촌
  '47250': ArtCategory.field, // 상주 곶감과 평야
  '47280': ArtCategory.mountain, // 문경새재
  '47290': ArtCategory.city, // 경산 대학도시
  '47730': ArtCategory.field, // 의성 마늘 농촌
  '47750': ArtCategory.mountain, // 주왕산과 주산지
  '47760': ArtCategory.mountain, // 일월산과 오지 산간
  '47770': ArtCategory.sea, // 영덕 대게와 강구항
  '47820': ArtCategory.field, // 청도 감과 소싸움
  '47830': ArtCategory.heritage, // 대가야 고분군
  '47840': ArtCategory.field, // 성주 참외
  '47850': ArtCategory.field, // 칠곡 낙동강변 농촌
  '47900': ArtCategory.field, // 예천 농촌
  '47920': ArtCategory.mountain, // 봉화 백두대간과 청량산
  '47930': ArtCategory.sea, // 울진 해안과 후포항
  '47940': ArtCategory.island, // 울릉도 — 완전 섬
  '48170': ArtCategory.heritage, // 진주성 촉석루 — 랜드마크의 폴백
  '48220': ArtCategory.island, // 통영 — 다도해. 한려수도 랜드마크의 폴백
  '48240': ArtCategory.sea, // 사천 삼천포 바다와 케이블카
  '48250': ArtCategory.city, // 창원·김해·양산 도심
  '48270': ArtCategory.heritage, // 영남루와 표충사
  '48310': ArtCategory.island, // 거제도 — 완전 섬
  '48330': ArtCategory.city, // 창원·김해·양산 도심
  '48121': ArtCategory.city, // 창원·김해·양산 도심
  '48123': ArtCategory.city, // 창원·김해·양산 도심
  '48125': ArtCategory.sea, // 마산만과 저도 연륙교
  '48127': ArtCategory.city, // 창원·김해·양산 도심
  '48129': ArtCategory.sea, // 진해 군항과 바다
  '48720': ArtCategory.field, // 의령 농촌
  '48730': ArtCategory.field, // 함안 농촌
  '48740': ArtCategory.river, // 우포늪 — 국내 최대 자연 늪
  '48820': ArtCategory.sea, // 고성 공룡발자국 해안
  '48840': ArtCategory.island, // 남해도 — 완전 섬
  '48850': ArtCategory.river, // 섬진강·화개장터
  '48860': ArtCategory.mountain, // 지리산 중산리
  '48870': ArtCategory.mountain, // 지리산 함양 자락과 상림
  '48880': ArtCategory.mountain, // 거창 덕유산 자락
  '48890': ArtCategory.mountain, // 가야산 — 해인사 랜드마크의 폴백
  '50000': ArtCategory.island, // 제주도 — 돌하르방 랜드마크의 폴백
  '41192': ArtCategory.city, // 수도권 도심
  '41194': ArtCategory.city, // 수도권 도심
  '41196': ArtCategory.city, // 수도권 도심
  '52111': ArtCategory.heritage, // 전주한옥마을과 경기전
  '52113': ArtCategory.city, // 전북대·덕진공원 일대 시가지
  '52130': ArtCategory.sea, // 근대 항구
  '52140': ArtCategory.heritage, // 미륵사지 — 백제 유적
  '52180': ArtCategory.mountain, // 내장산 단풍
  '52190': ArtCategory.heritage, // 광한루 — 랜드마크의 폴백
  '52210': ArtCategory.field, // 김제평야 지평선
  '52710': ArtCategory.mountain, // 대둔산과 모악산
  '52720': ArtCategory.mountain, // 마이산 탑사
  '52730': ArtCategory.mountain, // 덕유산과 무주구천동
  '52740': ArtCategory.mountain, // 장수 고랭지 산간
  '52750': ArtCategory.field, // 임실 치즈마을
  '52770': ArtCategory.field, // 순창 고추장마을
  '52790': ArtCategory.field, // 고창 청보리밭
  '52800': ArtCategory.sea, // 변산반도 — 채석강 랜드마크의 폴백
  'DK001': ArtCategory.island, // 독도 — 동도·서도 두 바위섬
};

/// 계획된 랜드마크 32개. 분포 검사에서 주 노출을 계산할 때 쓴다.
const Set<String> kPlannedLandmarks = {
  '11000',
  '28710',
  '28720',
  '41115',
  '41670',
  '51210',
  '51760',
  '43720',
  '43800',
  '44760',
  '44150',
  '36110',
  '52190',
  '52800',
  '12150',
  '12210',
  '47130',
  '47170',
  '48220',
  '48890',
  '50000',
  '41610',
  '41830',
  '41820',
  '48170',
  '47940',
  '26000',
  '27000',
  '28000',
  '30000',
  '31000',
  'DK001',
};
