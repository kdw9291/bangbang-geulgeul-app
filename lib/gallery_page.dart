import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'collection.dart';
import 'map_data.dart';
import 'region_art.dart';
import 'region_category.g.dart';
import 'region_description.dart';

/// M6 랜드마크 갤러리. **수집한 랜드마크를 모아 보는 보상 화면**이다.
///
/// ## 미수집 유출 금지 — 이 화면의 가장 중요한 계약
///
/// M4 에서 정한 "가리고, 긁을 때 공개" 결정이 여기에도 그대로 적용된다.
/// **랜드마크 이름 한 단어도 힌트가 된다.** 그래서 잠금 카드와 공개 카드를
/// 아예 다른 위젯으로 나눴다 — [_LockedCard] 는 생성자로 [RegionArt] 도,
/// 랜드마크 이름도, 설명도 **받지 않는다.** 실수로 넘길 수 있는 통로 자체가 없다.
///
/// 가리는 대상은 **랜드마크 이름과 설명뿐**이다. 지역명·시도명은 지도와 검색에
/// 이미 공개돼 있어 힌트가 되지 않는다(Codex 23회차 확인).
///
/// ## 대상은 랜드마크 32개다
///
/// 193개 전부가 아니다(2026-08-18 사용자 결정). 단일 원본은
/// [kPlannedLandmarks] 이며 [kLandmarkArt]·[kLandmarkDescription] 과
/// 세 집합이 정확히 일치한다 — 테스트가 이를 강제한다.
class GalleryPage extends StatelessWidget {
  const GalleryPage({
    super.key,
    required this.data,
    required this.snapshot,
    required this.onOpenRegion,
  });

  final MapData data;

  /// **수집 기록의 원본을 그대로 받는다.** 자체 State 에 복사하지 않는다 —
  /// 복사하면 지도 탭에서 긁고 돌아왔을 때 stale 이 된다(Codex 23회차).
  final CollectionSnapshot snapshot;

  /// 지역 팝업 열기. **부모의 `_openRegion` 을 그대로 탄다.**
  ///
  /// 비슷한 시트를 여기서 새로 만들면 저장 불가 상태(손상 격리·미래 버전)에서도
  /// 긁기 화면으로 들어가게 된다 — 그 게이트가 `_openRegion` 안에 있다.
  final Future<void> Function(Region) onOpenRegion;

  /// 갤러리에 늘어놓을 지역. **시도·지역 고정 순서다.**
  ///
  /// 수집 여부로 재정렬하지 않는다 — 긁고 돌아올 때마다 카드가 위로 튀면
  /// 스크롤 위치와 "그 칸이 거기 있었다" 는 기억이 깨진다.
  List<Region> get _entries {
    final list = data.regions
        .where((r) => kPlannedLandmarks.contains(r.scratchUnitId))
        .toList()
      ..sort((a, b) {
        final s = data.sidoNames[a.sido].compareTo(data.sidoNames[b.sido]);
        return s != 0 ? s : a.name.compareTo(b.name);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    final entries = _entries;
    // **모집단은 랜드마크 32개다.** `snapshot.length` 를 쓰면 랜드마크가 없는
    // 지역과 현재 카탈로그에 없는 ID 까지 세어 33/32 같은 값이 나온다.
    final collected =
        entries.where((r) => snapshot.contains(r.scratchUnitId)).length;

    // 큰 글꼴에서는 칸을 나누지 않는다. 320px 2열에 이름·설명·날짜를 넣으면
    // 어떤 비율을 골라도 글자가 잘린다 — 이 프로젝트에서 이미 겪은 실패다.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return LayoutBuilder(
      builder: (context, c) {
        final columns = (scale > 1.3 || c.maxWidth < 340)
            ? 1
            : (c.maxWidth >= 620 ? 3 : 2);
        return CustomScrollView(
          key: const Key('galleryScroll'),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(collected: collected, total: entries.length),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
              sliver: SliverList.separated(
                itemCount: (entries.length + columns - 1) ~/ columns,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, row) {
                  // **고정 높이나 고정 비율을 쓰지 않는다.** `IntrinsicHeight`
                  // 로 한 줄의 카드 높이를 맞추면 글꼴이 커져도 잘리지 않는다.
                  final children = <Widget>[];
                  for (var i = 0; i < columns; i++) {
                    final index = row * columns + i;
                    if (i > 0) children.add(const SizedBox(width: 12));
                    children.add(Expanded(
                      child: index < entries.length
                          ? _cardFor(entries[index], t)
                          : const SizedBox.shrink(),
                    ));
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// **수집 여부를 먼저 확인하고, 확인한 뒤에야 민감한 값에 손을 댄다.**
  ///
  /// 이 순서가 이 화면의 유출 게이트 전부다. 잠금 가지에서는 [kLandmarkArt] 도
  /// [descriptionFor] 도 부르지 않는다.
  Widget _cardFor(Region r, AppTheme t) {
    final sidoName = data.sidoNames[r.sido];
    final unit = snapshot[r.scratchUnitId];
    if (unit == null) {
      return _LockedCard(
        // 테스트가 특정 칸을 집고, 훑으면서 몇 칸을 봤는지 셀 수 있게 한다.
        key: Key('galleryCard:${r.scratchUnitId}'),
        regionName: r.name,
        sidoName: sidoName,
        foilLight: t.foilLight,
        foilDark: t.foilDark,
        onTap: () => onOpenRegion(r),
      );
    }
    return _RevealedCard(
      key: Key('galleryCard:${r.scratchUnitId}'),
      art: kLandmarkArt[r.scratchUnitId]!,
      landmarkName: kLandmarkArt[r.scratchUnitId]!.name,
      regionName: r.name,
      sidoName: sidoName,
      description: descriptionFor(r.scratchUnitId),
      // **수집 당시 오프셋으로 푼 날짜다.** UTC 로 표시하면 여행 중 시간대를
      // 넘나든 사용자에게 하루 어긋난 날짜가 보인다.
      localDate: unit.localDate,
      onTap: () => onOpenRegion(r),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.collected, required this.total});

  final int collected;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **`Row` 를 쓰지 않는다.** 글꼴이 2.5배가 되면 제목과 숫자가 한 줄에
          // 안 들어가 오른쪽으로 넘친다 — 테스트가 64px 오버플로로 잡았다.
          // `Wrap` 은 자리가 모자라면 스스로 줄을 바꾼다.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(
                '랜드마크',
                style: TextStyle(
                  color: t.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$collected/$total',
                key: const Key('galleryProgress'),
                style: TextStyle(
                  color: t.onSurfaceMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // **"지역을 긁으면" 이라고 쓰지 않는다.** 193곳 중 161곳은 긁어도
            // 이 화면이 변하지 않아, 저장이 안 된 것으로 오해하게 된다.
            collected == 0
                ? '랜드마크가 있는 $total곳을 긁으면 이곳에 공개됩니다.'
                : collected == total
                    ? '랜드마크를 전부 모았어요!'
                    : '아직 열리지 않은 곳이 ${total - collected}곳 있어요.',
            style: TextStyle(color: t.onSurfaceMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 미수집 카드. **랜드마크에 대한 것은 아무것도 받지 않는다.**
///
/// 아트·이름·설명이 생성자에 없으므로 실수로 그릴 수 없다. 은박도
/// 랜드마크와 무관한 **공통 결**이라 어느 칸이든 똑같이 보인다 —
/// 실제 아트 위에 반투명을 덮으면 실루엣이 남아 계약이 깨진다.
class _LockedCard extends StatelessWidget {
  const _LockedCard({
    super.key,
    required this.regionName,
    required this.sidoName,
    required this.foilLight,
    required this.foilDark,
    required this.onTap,
  });

  final String regionName;
  final String sidoName;
  final Color foilLight;
  final Color foilDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Semantics(
      button: true,
      label: sidoName == regionName
          ? '$regionName · 아직 열리지 않았습니다'
          : '$sidoName $regionName · 아직 열리지 않았습니다',
      // **`onTap` 을 반드시 함께 준다.** `excludeSemantics` 가 자식 `InkWell`
      // 의 탭 액션까지 지워서, 이것이 없으면 TalkBack 이 읽어 주고도
      // 더블 탭으로 실행할 수 없다 — 손가락 탭만 되고 스크린 리더는 막힌다.
      onTap: onTap,
      excludeSemantics: true,
      child: _CardShell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _FoilPainter(light: foilLight, dark: foilDark),
                child: Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      color: t.onSurfaceFaint,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(regionName,
                      style: TextStyle(
                        color: t.onSurfaceMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      )),
                  // 통합 단위는 두 이름이 같다. 그대로 두면 같은 말이 두 줄이다.
                  if (sidoName != regionName) ...[
                    const SizedBox(height: 2),
                    Text(sidoName,
                        style:
                            TextStyle(color: t.onSurfaceFaint, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 수집한 카드. 아트를 공개하고 랜드마크 이름·설명·수집일을 붙인다.
class _RevealedCard extends StatelessWidget {
  const _RevealedCard({
    super.key,
    required this.art,
    required this.landmarkName,
    required this.regionName,
    required this.sidoName,
    required this.description,
    required this.localDate,
    required this.onTap,
  });

  final RegionArt art;
  final String landmarkName;
  final String regionName;
  final String sidoName;
  final String description;
  final DateTime localDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return _CardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              // **카드마다 직접 그린다.** `RegionArtCache` 는 한 벌만 기억해서
              // 여러 칸이 공유하면 스크롤 중에 서로의 Picture 를 버린다.
              painter: _ArtPainter(art: art, color: sidoColorOf(sidoName)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(landmarkName,
                    key: const Key('galleryLandmarkName'),
                    style: TextStyle(
                      color: t.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 2),
                Text(
                    // **통합 긁기 단위는 지역명이 시도명과 같다.** 그대로 이으면
                    // "제주특별자치도 제주특별자치도" 가 된다 — 실기기에서 눈으로
                    // 보고 찾았다. `main.dart` 팝업과 `scratch_page.dart` 가
                    // 이미 같은 규칙을 쓰고 있는데 갤러리만 빠뜨렸다.
                    sidoName == regionName
                        ? regionName
                        : '$sidoName $regionName',
                    style: TextStyle(color: t.onSurfaceFaint, fontSize: 12)),
                const SizedBox(height: 6),
                Text(description,
                    key: const Key('galleryDescription'),
                    style: TextStyle(
                        color: t.onSurfaceMuted, fontSize: 13, height: 1.35)),
                const SizedBox(height: 6),
                Text(
                  '${localDate.year}년 ${localDate.month}월 ${localDate.day}일',
                  style: TextStyle(color: t.onSurfaceFaint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드 겉모양. 잠금·공개가 같은 테두리와 탭 영역을 쓴다.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// 공통 은박. **랜드마크가 무엇이든 똑같이 그린다.**
class _FoilPainter extends CustomPainter {
  _FoilPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [light, dark, light],
          const [0, .5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_FoilPainter old) =>
      old.light != light || old.dark != dark;
}

class _ArtPainter extends CustomPainter {
  _ArtPainter({required this.art, required this.color});

  final RegionArt art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color);
    canvas.save();
    canvas.clipRect(rect);
    paintRegionArt(canvas, art, rect);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      !identical(old.art, art) || old.color != color;
}
