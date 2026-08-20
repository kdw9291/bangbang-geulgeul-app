import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'hit_test.dart';
import 'map_data.dart';
import 'map_inset.dart';

/// 좌우 배치를 쓸 수 있는가. **부모가 이 함수로 한 번만 정한다.**
///
/// 판이 다시 계산하면 부모는 세로형인데 판만 좌우형이 되어 390px 판이 좁은
/// 화면 밖으로 나간다(Codex 28회차).
///
/// 좌우형을 고르는 구간은 지도 영역 기준 **높이 230~334, 폭 414 이상**이다.
///
/// - [wideEnough] — 판 [kInsetWidePanelWidth] + 좌우 여백 12씩
/// - [tallEnough] — 캔버스 190 + 판 상하 패딩 16 을 실제로 수용할 높이
/// - [shortEnoughToPreferWide] — 세로로 쌓기엔 답답해 좌우를 **선호**하는 구간
///
/// 마지막 것은 이름 그대로 **휴리스틱**이다. 세로형의 실제 가용 높이(검색·설정
/// 줄을 남긴 높이)가 아니라 좌우형 기준 높이로 재므로, 중간 높이 + 큰 글꼴에서
/// 세로형이 빠듯해도 좌우형을 안 고를 수 있다. 그 경우에도 판이 스크롤되고
/// 지역 목록이 있어 기능이 막히지는 않는다(Codex 28회차 Low, 알고 남긴다).
bool shouldUseWideInset(Size area) {
  final tallEnough = area.height - 24 >= kInsetCanvasSize.height + 16;
  final wideEnough = area.width >= kInsetWidePanelWidth + 24;
  final shortEnoughToPreferWide =
      area.height - 24 < kInsetCanvasSize.height + 120;
  return shortEnoughToPreferWide && tallEnough && wideEnough;
}

/// 좌우 배치일 때 판의 폭. 조작부 190 + 간격 8 + 캔버스 176 + 안팎 여백 16.
const double kInsetWidePanelWidth = 390;

/// 인셋 캔버스 크기. **여기 한 곳에서만 정한다.**
///
/// 테스트와 미리보기가 각자 다른 크기를 쓰면 "부산 중구가 6px 이상" 같은
/// 검증이 실제 화면과 무관해진다 — 실제로 테스트는 160×200, PNG 는 172×190,
/// UI 는 176×158 이라 **UI 에서만 5.39px 로 목표를 못 넘고 있었다**(Codex 28회차).
///
/// 높이가 배율을 제한한다. 이 값에서 부산 중구는 **6.48px**(본지도 1.8px),
/// 대구 중구 11.9px, 수도권 최소 14.5px 다. 판이 짧은 화면에서는 스크롤한다.
const Size kInsetCanvasSize = Size(176, 190);

/// M8 인셋 판. 지도 위 모서리에 겹쳐 놓는다.
///
/// ## 한 번에 하나만 그린다
///
/// 360px 화면에 160px 판 셋을 나란히 놓을 수 없고, 세로로 쌓으면 지도를 거의
/// 다 가린다. 셋을 한 번에 보이려고 판을 줄이면 확대율이 떨어져 **부산 중구가
/// 다시 3~4px** 이 된다 — 인셋의 존재 이유가 사라진다(Codex 27회차).
///
/// ## 아트를 그리지 않는다
///
/// 인셋의 목적은 아트 감상이 아니라 **수집 현황 판독**이다. 미수집 은박색,
/// 수집 시도색, 경계선, 선택 외곽선만 그린다. 더 선명하고 더 싸다.
///
/// ## 작은 도형만으로는 접근성을 만족할 수 없다
///
/// 인셋 지역은 확대해도 6~23px 이라 48×48 탭 영역이 안 된다. 허용 오차를
/// 늘리면 서로 겹쳐 어느 지역인지 모호해질 뿐이다. 그래서 시각 지도와 **별도로**
/// [_RegionListSheet] 를 둔다 — 48px 이상 행으로 같은 지역을 열 수 있다.
class MapInsetPanel extends StatefulWidget {
  const MapInsetPanel({
    super.key,
    required this.data,
    required this.scratched,
    required this.selected,
    required this.onOpenRegion,
    required this.maxHeight,
    required this.wide,
    this.onOpenChanged,
  });

  /// 좌우 배치인가. **부모가 정한다** — 판이 다시 계산하면 판단이 갈라진다.
  final bool wide;

  /// 펼침 상태가 바뀌면 알린다. 가로에서 검색줄이 판을 피하도록.
  final void Function(bool)? onOpenChanged;

  /// 판이 쓸 수 있는 세로 공간. **지도 영역 기준**이다.
  final double maxHeight;

  final MapData data;

  /// 카탈로그와 이미 교집합된 파생 집합.
  final Set<String> scratched;

  final Region? selected;

  /// **기존 `_openRegion` 을 그대로 탄다.** 비슷한 시트를 여기서 새로 만들면
  /// 저장 불가 상태에서도 긁기 화면으로 들어가게 된다.
  final Future<void> Function(Region) onOpenRegion;

  @override
  State<MapInsetPanel> createState() => _MapInsetPanelState();
}

class _MapInsetPanelState extends State<MapInsetPanel> {
  /// **기본은 접힘이다**(2026-08-18 사용자 결정). 탭을 오가도 유지되지만
  /// 앱을 다시 켜면 접힌 상태로 시작한다 — 따로 저장하지 않는다.
  bool _open = false;
  int _which = 0;

  void _setOpen(bool v) {
    setState(() => _open = v);
    // 부모가 알아야 가로에서 검색줄을 비켜 줄 수 있다.
    widget.onOpenChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    // **접혔을 때는 버튼만 트리에 남긴다.** 투명한 전체 화면 제스처를 깔면
    // 지도 탭이 통째로 막힌다(Codex 27회차).
    if (!_open) return _ToggleButton(onTap: () => _setOpen(true));

    final t = AppThemeScope.of(context);
    final inset = resolveInset(kInsetDefinitions[_which], widget.data);

    // **판은 `Container` 의 배경색만으로 탭을 먹는다.** 별도 제스처를 덧대지
    // 않는다 — 확인해 보니 색이 칠해진 상자는 그 자체로 히트 테스트를 막는다.
    // **세로 공간이 모자라면 판이 넘친다.** 가로 화면이나 큰 글꼴에서는
    // 머리글·칩 두 줄·캔버스 190·목록 버튼을 합치면 350px 가까이 필요한데,
    // 가로 360px 화면의 지도 영역은 250~280px 뿐이다(Codex 28회차).
    //
    // **화면 높이가 아니라 [maxHeight] 로 자른다.** 판은 아래에 고정돼 있어,
    // 지도 영역보다 커지면 위쪽이 화면 밖으로 밀려 머리글과 닫기 버튼을
    // 누를 수 없게 된다 — 실제로 그렇게 깨뜨려 봤다.
    // **세로가 모자라면 좌우로 배치한다.**
    //
    // 가로 화면(568×320)에서는 판 높이가 160 남짓이라 세로로 쌓으면 캔버스가
    // 거의 다 잘려 **시각 인셋을 쓸 수 없다.** 목록은 *접근* 경로일 뿐
    // "한눈에 본다" 는 *표시* 를 대신하지 못한다 — 그것이 인셋이 푸는 문제다
    // (Codex 28회차). 앱은 회전 제한이 없어 가로도 지원 범위다.
    //
    // 조작부를 왼쪽에, 캔버스를 오른쪽에 두면 캔버스가 온전히 보인다.
    // **판단은 부모가 한 번만 한다.** 판이 다시 계산하면 부모가 검색줄을
    // 남긴 채 판만 좌우형이 되어, 390px 판이 좁은 화면 밖으로 나간다
    // (Codex 28회차).
    final wide = widget.wide;

    final controls = <Widget>[
      _header(t),
      // **`지역 목록` 을 칩보다 앞에 둔다.** 조작부가 좁아 스크롤되면 뒤에 둔
      // 것이 가려지는데, 가려지면 안 되는 것은 접근성 진입점이다.
      _listButton(inset, t),
      const SizedBox(height: 4),
      // **`Row` 로 고정하지 않는다.** 큰 글꼴에서 세 이름이 한 줄에 안 들어간다.
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < kInsetDefinitions.length; i++)
            _Chip(
              key: Key('insetPick:${kInsetDefinitions[i].id}'),
              label: kInsetDefinitions[i].label,
              on: i == _which,
              onTap: () => setState(() => _which = i),
            ),
        ],
      ),
    ];

    final canvas = _InsetCanvas(
      inset: inset,
      sidoNames: widget.data.sidoNames,
      scratched: widget.scratched,
      selected: widget.selected,
      onOpenRegion: widget.onOpenRegion,
    );

    return Container(
      key: const Key('insetPanel'),
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.onSurfaceGhost),
      ),
      padding: const EdgeInsets.all(8),
      child: wide
          ? Row(
              key: const Key('insetWide'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  // **칩 세 개가 한 줄에 들어가야 한다.** 좁으면 두 줄이 되어
                  // 조작부가 판 높이를 넘고, 칩이 판 밖으로 밀려 눌리지 않는다.
                  width: 190,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controls,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                canvas,
              ],
            )
          : SizedBox(
              width: 192,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...controls,
                    const SizedBox(height: 8),
                    canvas,
                  ],
                ),
              ),
            ),
    );
  }

  Widget _header(AppTheme t) {
    return Row(
      children: [
        Expanded(
          child: Text('도심 확대',
              style: TextStyle(
                color: t.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              )),
        ),
        Semantics(
          button: true,
          label: '도심 확대 닫기',
          onTap: () => _setOpen(false),
          excludeSemantics: true,
          child: InkWell(
            key: const Key('insetClose'),
            onTap: () => _setOpen(false),
            // **최소 탭 영역 48×48.** 아이콘 크기로 두면 30px 밖에 안 된다.
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 18, color: t.onSurfaceMuted),
            ),
          ),
        ),
      ],
    );
  }

  void _openList(ResolvedInset inset) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppThemeScope.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _RegionListSheet(
        inset: inset,
        data: widget.data,
        scratched: widget.scratched,
        onOpenRegion: widget.onOpenRegion,
      ),
    );
  }

  Widget _listButton(ResolvedInset inset, AppTheme t) {
    return Semantics(
      button: true,
      label: '${inset.label} 지역 목록',
      onTap: () => _openList(inset),
      excludeSemantics: true,
      child: Material(
        color: t.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('insetList'),
          onTap: () => _openList(inset),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            // **테두리와 아이콘을 준다.** 가운데 정렬한 맨 글자로 두었더니
            // 실기기에서 **누를 수 있어 보이지 않았다** — 그냥 설명문 같았다.
            // 이 화면의 접근성 대안이라 발견되지 않으면 없는 것과 같다.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.list, size: 16, color: t.onSurfaceMuted),
                const SizedBox(width: 6),
                Text('지역 목록',
                    style: TextStyle(
                      color: t.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Semantics(
      button: true,
      label: '도심 확대 보기',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('insetToggle'),
          onTap: onTap,
          // 최소 탭 영역 48×48.
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.zoom_in_map, size: 18, color: t.onSurfaceMuted),
                const SizedBox(width: 6),
                Text('도심',
                    style: TextStyle(color: t.onSurfaceMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: '$label${on ? ', 선택됨' : ''}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          // 최소 탭 영역. 글자 크기로만 두면 26~30px 밖에 안 된다.
          //
          // **`alignment` 를 주지 않는다.** `Container` 에 정렬을 주면 가로를
          // 최대로 늘려, `Wrap` 안에서 칩 하나가 한 줄을 통째로 먹는다.
          // 세 칩이 3줄이 되어 판이 넘치고 캔버스가 잘렸다.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: on ? t.surfaceVariant : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? t.good : t.onSurfaceGhost),
          ),
          child: Text(label,
              style: TextStyle(
                color: on ? t.onSurface : t.onSurfaceMuted,
                fontSize: 12,
                fontWeight: on ? FontWeight.bold : FontWeight.normal,
              )),
        ),
      ),
    );
  }
}

/// 인셋 지도 자체. 탭을 자기가 받아 아래 지도로 흘리지 않는다.
class _InsetCanvas extends StatelessWidget {
  const _InsetCanvas({
    required this.inset,
    required this.sidoNames,
    required this.scratched,
    required this.selected,
    required this.onOpenRegion,
  });

  final ResolvedInset inset;
  final List<String> sidoNames;
  final Set<String> scratched;
  final Region? selected;
  final Future<void> Function(Region) onOpenRegion;


  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // **실제로 배치되는 크기로 변환을 만든다.**
        //
        // 고정 크기로 변환을 계산해 놓고 부모 제약에 눌려 줄어들면, 그리기와
        // 탭의 기준이 실제 위젯과 어긋난다 — 가로 화면에서 176×190 으로 계산해
        // 놓고 실제로는 176×146 으로 그려져 아래 42px 이 잘렸다(Codex 28회차).
        final h = c.maxHeight.isFinite && c.maxHeight < kInsetCanvasSize.height
            ? c.maxHeight
            : kInsetCanvasSize.height;
        final w = c.maxWidth.isFinite && c.maxWidth < kInsetCanvasSize.width
            ? c.maxWidth
            : kInsetCanvasSize.width;
        final size = Size(w, h);
        final transform = InsetTransform.fit(inset.window, size);
        return GestureDetector(
          // **불투명이다.** 지역이 없는 곳을 눌러도 아래 지도로 떨어지면
          // 인셋을 보다가 엉뚱한 지역이 열린다.
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) => _onTap(e.localPosition, transform),
          child: RepaintBoundary(
            // 테스트가 **실제 그려진 픽셀**을 떠서 비교한다.
            key: Key('insetCanvas:${inset.id}'),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: CustomPaint(
                painter: InsetPainter(
                  inset: inset,
                  sidoNames: sidoNames,
                  transform: transform,
                  scratched: scratched,
                  selected: selected,
                  foil: t.foilLight,
                  outline: t.onSurfaceGhost,
                  selectionOuter: t.selectionOuter,
                  selectionInner: t.selectionInner,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onTap(Offset local, InsetTransform transform) {
    // **레터박스는 변환이 `null` 로 알려준다.**
    final map = transform.toMap(local);
    if (map == null) return;
    // **기존 판정기를 그대로 쓴다.** 손수 순회하면 `RegionHitTester` 의
    // **작은 지역 우선** 정렬을 잃는다 — 경계가 맞닿은 지점은 두 지역 모두
    // `contains` 가 참이라, 정렬이 없으면 에셋 배열 순서가 승자를 정한다.
    // 도심의 작은 구가 손해 보지 않게 하는 것이 M8 의 존재 이유다
    // (Codex 28회차). 허용 오차는 **인셋 배율**로 환산한다.
    final hit = RegionHitTester(inset.regions).nearest(
      map,
      tolerance: transform.mapUnitsPerPx(kTapTolerancePx),
    );
    if (hit != null) onOpenRegion(hit);
  }
}

/// 인셋 지도 화가. **아트는 그리지 않는다** — 수집 현황만 읽으면 된다.
class InsetPainter extends CustomPainter {
  InsetPainter({
    required this.inset,
    required this.sidoNames,
    required this.transform,
    required this.scratched,
    required this.selected,
    required this.foil,
    required this.outline,
    required this.selectionOuter,
    required this.selectionInner,
  });

  final ResolvedInset inset;

  /// 시도 색을 이름으로 찾기 위해 받는다. **배열 인덱스로 찾지 않는다** —
  /// 에셋의 `sidos` 순서는 원본 데이터가 정하므로 재생성으로 바뀔 수 있다.
  final List<String> sidoNames;

  final InsetTransform transform;
  final Set<String> scratched;
  final Region? selected;
  final Color foil;
  final Color outline;
  final Color selectionOuter;
  final Color selectionInner;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(transform.dest.left, transform.dest.top);
    canvas.scale(transform.scale);
    canvas.translate(-transform.window.left, -transform.window.top);

    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 / transform.scale
      ..color = outline;

    for (final r in inset.regions) {
      final got = scratched.contains(r.scratchUnitId);
      fill.color = got ? sidoColorOf(sidoNames[r.sido]) : foil;
      canvas.drawPath(r.path, fill);
      canvas.drawPath(r.path, line);
    }

    final sel = selected;
    if (sel != null && inset.regions.any((r) => r.scratchUnitId == sel.scratchUnitId)) {
      // 지도와 같은 방식으로 두 겹이다 — 한 색으로는 시도 16색을 못 덮는다.
      canvas.drawPath(
        sel.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 / transform.scale
          ..color = selectionOuter,
      );
      canvas.drawPath(
        sel.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / transform.scale
          ..color = selectionInner,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InsetPainter old) =>
      old.inset.id != inset.id ||
      !setEquals(old.scratched, scratched) ||
      old.selected?.scratchUnitId != selected?.scratchUnitId ||
      old.foil != foil ||
      old.outline != outline ||
      old.selectionOuter != selectionOuter ||
      old.selectionInner != selectionInner;
}

bool setEquals(Set<String> a, Set<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}

/// 인셋 구역의 지역을 48px 이상 행으로 늘어놓는 시트.
///
/// **시각 도형만으로는 최소 탭 영역을 만족할 수 없다.** 확대해도 6~23px 이라
/// 손가락이 굵거나 스크린 리더를 쓰면 못 누른다. 검색(M3)은 이름을 아는 곳으로
/// 가는 도구라 "여기 어디 있더라" 를 대신하지 못한다(Codex 27회차).
class _RegionListSheet extends StatelessWidget {
  const _RegionListSheet({
    required this.inset,
    required this.data,
    required this.scratched,
    required this.onOpenRegion,
  });

  final ResolvedInset inset;
  final MapData data;
  final Set<String> scratched;
  final Future<void> Function(Region) onOpenRegion;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    final sorted = [...inset.regions]..sort((a, b) {
        final s = data.sidoNames[a.sido].compareTo(data.sidoNames[b.sido]);
        return s != 0 ? s : a.name.compareTo(b.name);
      });
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('${inset.label} ${sorted.length}곳',
                      style: TextStyle(
                        color: t.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      )),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              key: const Key('insetRegionList'),
              shrinkWrap: true,
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final r = sorted[i];
                final got = scratched.contains(r.scratchUnitId);
                final sido = data.sidoNames[r.sido];
                return ListTile(
                  key: Key('insetRow:${r.scratchUnitId}'),
                  // 48px 이상을 보장한다.
                  minVerticalPadding: 12,
                  title: Text(
                    // 통합 단위는 지역명이 시도명과 같다. 그대로 이으면
                    // "제주특별자치도 제주특별자치도" 가 된다.
                    sido == r.name ? r.name : '$sido ${r.name}',
                    style: TextStyle(color: t.onSurface, fontSize: 15),
                  ),
                  trailing: Text(got ? '수집' : '미수집',
                      style: TextStyle(
                        color: got ? t.good : t.onSurfaceFaint,
                        fontSize: 13,
                        fontWeight: got ? FontWeight.bold : FontWeight.normal,
                      )),
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenRegion(r);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
