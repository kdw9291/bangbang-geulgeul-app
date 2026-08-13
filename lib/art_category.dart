/// 카테고리 아이콘 8종.
///
/// `region_art.dart` 와 생성 파일 `region_category.g.dart` 가 함께 쓴다.
/// 두 파일이 서로를 import 하지 않도록 열거형만 따로 둔다.
///
/// 랜드마크가 없는 지역이 이 8종을 재사용한다. 개당 노출이 랜드마크보다 훨씬 많다.
enum ArtCategory { mountain, sea, island, city, heritage, hotspring, river, field }
