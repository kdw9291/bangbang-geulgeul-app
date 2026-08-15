import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'collection.dart';
import 'frame_stats.dart';
import 'island_layout.dart';
import 'map_data.dart';
import 'region_art.dart';
import 'scratch_progress.dart';

/// 지역 하나를 복권처럼 긁는 전용 화면.
///
/// 지도 위에서 직접 긁지 않는 이유:
/// - InteractiveViewer 의 한 손가락 드래그(이동)와 긁기 제스처가 충돌한다.
/// - 작은 도심 구도 화면 가득 확대되므로 셀 크기 문제가 이 화면에서는 사라진다.
///
/// **완료는 화면을 닫을 때가 아니라 임계치에 도달한 순간 확정된다.**
///
/// 예전에는 `Navigator.pop(true)` 가 커밋 신호였다. 그러면 완료 연출을 보고
/// 버튼을 누르기 전까지가 통째로 손실 창이 되어, 그 사이 앱이 죽으면
/// "긁었는데 기록이 안 남는다" 가 된다(Codex 15회차). 지금은 도달 즉시
/// [onCollected] 로 저장을 요청하고, **성공해야** 완료로 확정한다.
///
/// 중간에 나가면 진행은 버려진다 (부분 진행 저장은 M1 범위 밖).
class ScratchPage extends StatefulWidget {
  const ScratchPage({
    super.key,
    required this.region,
    required this.sidoName,
    required this.onCollected,
  });

  final Region region;
  final String sidoName;

  /// 임계치 도달 즉시 호출된다. **실패하면 예외를 던져야 한다** —
  /// 이 화면이 재시도 UI 를 띄운다.
  final Future<void> Function(CollectedUnit unit) onCollected;

  @override
  State<ScratchPage> createState() => _ScratchPageState();
}

/// 저장 진행 상태. `_done`(다 긁었다)과 구분한다.
enum _SaveState { idle, saving, saved, failed }

class _ScratchPageState extends State<ScratchPage>
    with SingleTickerProviderStateMixin {
  /// 이 비율 이상 긁으면 나머지를 자동 완성한다.
  /// 실물 복권도 구석까지 긁는 사람은 없다 — 끝까지 강요하면 답답해진다.
  ///
  /// **2026-08-14 사용자 결정으로 0.65 → 0.80 으로 올렸다.** 촉감 확인("좋다")은
  /// 0.65 기준이었으므로 실기기에서 다시 판단해야 한다.
  static const threshold = 0.80;

  /// 손가락 지우개 반지름 (논리 px)
  static const brush = 26.0;

  final _strokes = <List<Offset>>[];
  late final AnimationController _fade;

  Path? _path; // 화면 좌표로 변환된 지역 Path
  Rect? _artTarget; // 아트를 놓을 자리 (준비 단계에서 한 번 계산)
  Path? _artClip; // 다도해에서 아트를 가둘 섬. null 이면 지역 전체
  ScratchProgress? _progress;
  Size? _preparedFor; // 어떤 화면 크기로 준비했는지
  bool _preparing = false;
  bool _done = false;

  final _stats = FrameStats();
  final _artCache = RegionArtCache();
  int _panEvents = 0;
  int _panMicros = 0;

  /// 저장 상태. `_done` 은 "다 긁었다", 이건 "기록됐다" 로 서로 다르다.
  _SaveState _save = _SaveState.idle;
  Object? _saveError;

  /// **임계치에 도달한 순간 한 번만** 잡는다. 재시도해도 갱신하지 않는다 —
  /// 그러면 수집 시각이 "실제로 긁은 때" 가 아니라 "저장에 성공한 때" 가 된다.
  CollectedUnit? _pending;

  double get _ratio => _progress?.ratio ?? 0;

  /// 화면을 떠나도 되는가.
  ///
  /// 아직 다 긁지 않았으면 언제든 나갈 수 있다(진행은 원래 버려진다).
  /// **다 긁었으면 기록된 뒤에만** 나갈 수 있다.
  bool get _canLeave => !_done || _save == _SaveState.saved;

  @override
  void initState() {
    super.initState();
    _stats.start();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _fade.dispose();
    _stats.dispose();
    _artCache.dispose();
    super.dispose();
  }

  /// 형상 [b] 를 [size] 화면에 맞추는 변환.
  ///
  /// 대부분은 지역 `bounds` 지만, 다도해는 재배치된 형상의 bounds 를 쓴다.
  Matrix4 _transformFor(Size size, Rect b) {
    const pad = 36.0;
    final k = math.min(
      (size.width - pad * 2) / b.width,
      (size.height - pad * 2) / b.height,
    );
    return Matrix4.identity()
      ..translateByDouble(
        size.width / 2 - b.center.dx * k,
        size.height / 2 - b.center.dy * k,
        0,
        1,
      )
      ..scaleByDouble(k, k, 1, 1);
  }

  /// 지역 Path 변환과 표본 수집.
  ///
  /// **빌드 중에 호출하지 않는다.** 다도해 지역은 `Path.contains` 를 3만 회 넘게
  /// 부르므로 프레임 예산을 훌쩍 넘긴다. 빌드에서는 로딩 상태를 한 프레임 보여주고
  /// 다음 프레임에서 준비한다.
  ///
  /// 화면 크기가 바뀌면 다시 준비한다 — 회전이나 분할 화면에서 좌표계가 어긋나던
  /// 문제도 여기서 함께 해소된다.
  void _prepare(Size size) {
    if (!mounted || _preparedFor == size) return;
    final sw = Stopwatch()..start();
    final region = widget.region;

    // 다도해는 섬을 모아 재배치한다. 옹진군은 육지가 bounds 의 0.93% 뿐이라
    // 그대로 화면에 맞추면 사용자가 빈 바다를 긁게 된다. 상세는 `island_layout.dart`.
    final layout =
        needsPacking(region.rings, region.bounds) ? packIslands(region.rings) : null;
    final shape = layout == null ? region.path : buildPackedPath(layout);
    final shapeBounds = layout == null ? region.bounds : layout.bounds;

    final m = _transformFor(size, shapeBounds);
    final path = shape.transform(m.storage);
    // 표본도 **재배치된 형상 위에서** 모아야 화면에 그려지는 것과 일치한다.
    final progress =
        ScratchProgress.forShape(shape, shapeBounds, m, brush: brush);

    // 아트 배치도 여기서 정한다. Path.contains 를 여러 번 부르므로
    // 렌더 중에 하면 매 입력 프레임에 얹힌다.
    // 배치는 B(`artTargetFill`) 를 쓴다 — 아트를 지역보다 크게 놓고 지역 모양을
    // 창처럼 써서 비춘다. A(`artTargetRectIn`) 는 지역 안에 맞추려고 줄이는데,
    // 육지가 가늘거나 흩어진 지역(종로구·옹진군·부산 서구)에서 안 보일 만큼
    // 작아졌다. 비교 렌더는 `design/art-pilot-placement.png` 참고.
    //
    // 다도해는 아트를 지역 전체에 걸치면 섬마다 파편으로 잘려 알아볼 수 없다.
    // **가장 큰 섬 하나에만** 놓는다 (`design/art-island-repack.png`).
    Rect? artTarget;
    Path? artClip;
    if (artForRegion(region.scratchUnitId) != null) {
      if (layout != null) {
        artClip = buildLargestIslandPath(layout).transform(m.storage);
        artTarget = artTargetFill(artClip, artClip.getBounds());
      } else {
        artTarget = artTargetFill(
          path,
          largestRingBounds(
            region.rings,
            scale: m.storage[0],
            offset: Offset(m.storage[12], m.storage[13]),
          ),
        );
      }
    }
    sw.stop();

    debugPrint('[SCRATCH] 준비 ${widget.region.name} '
        '표본 ${progress.sampleCount}개 · 격자 ${progress.gridUsed} · '
        '목표달성 ${progress.reachedTarget} · ${sw.elapsedMilliseconds}ms');

    setState(() {
      _path = path;
      _artTarget = artTarget;
      _artClip = artClip;
      _progress = progress;
      _preparedFor = size;
      _preparing = false;
      _strokes.clear(); // 좌표계가 바뀌었으므로 이전 자취는 버린다
    });
    _stats.reset(); // 준비 단계 프레임은 측정에서 제외
  }

  void _addPoint(Offset p, {required bool newStroke}) {
    final progress = _progress;
    if (_done || progress == null) return;
    final sw = Stopwatch()..start();

    if (newStroke || _strokes.isEmpty) {
      _strokes.add([p]);
      progress.startStroke();
    } else {
      _strokes.last.add(p);
    }
    progress.addPoint(p);
    sw.stop();
    _panEvents++;
    _panMicros += sw.elapsedMicroseconds;
    setState(() {});
    if (_ratio >= threshold) _finish();
  }

  void _finish() {
    _done = true;
    _fade.forward();

    // 수집 시각은 여기서 한 번만 잡는다.
    final now = DateTime.now();
    _pending = CollectedUnit(
      scratchUnitId: widget.region.scratchUnitId,
      collectedAtUtc: now.toUtc(),
      utcOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
    unawaited(_saveNow());

    final avg = _panEvents == 0 ? 0 : _panMicros ~/ _panEvents;
    debugPrint('[SCRATCH] 완료 ${widget.region.scratchUnitId} ${widget.region.name} '
        'ratio=${(_ratio * 100).toStringAsFixed(0)}% '
        'pan=$_panEvents회 handler=${avg}us '
        'fps=${_stats.measuredFps.toStringAsFixed(1)} '
        '(여유 ${_stats.headroomFps.toStringAsFixed(0)}) '
        'jank=${(_stats.jankRatio * 100).toStringAsFixed(0)}% '
        'worst=${_stats.worstTotalMs.toStringAsFixed(1)}ms '
        '구간=${_stats.elapsedSeconds.toStringAsFixed(1)}s');
  }

  /// 하단은 **저장 상태**를 보여준다. 다 긁었다는 것과 기록됐다는 것은 다르다.
  Widget _buildFooter(AppTheme t) {
    if (!_done) {
      return Text(
        '손가락으로 문질러 긁어보세요',
        textAlign: TextAlign.center,
        style: TextStyle(color: t.onSurfaceFaint, fontSize: 13),
      );
    }
    switch (_save) {
      case _SaveState.saving:
      case _SaveState.idle:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: t.onSurfaceFaint),
            ),
            const SizedBox(width: 10),
            Text('기록하는 중…',
                style: TextStyle(color: t.onSurfaceMuted, fontSize: 13)),
          ],
        );
      case _SaveState.failed:
        return Column(
          children: [
            Text(
              '기록하지 못했습니다. 다시 시도해 주세요.'
              '${_saveError == null ? '' : '\n($_saveError)'}',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.onSurface, fontSize: 13),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saveNow,
              child: const Text('다시 시도'),
            ),
          ],
        );
      case _SaveState.saved:
        return FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('지도로 돌아가기'),
        );
    }
  }

  Future<void> _saveNow() async {
    final unit = _pending;
    if (unit == null || _save == _SaveState.saving) return;
    setState(() {
      _save = _SaveState.saving;
      _saveError = null;
    });
    try {
      await widget.onCollected(unit);
      if (!mounted) return;
      setState(() => _save = _SaveState.saved);
      debugPrint('[SCRATCH] 저장 완료 ${unit.scratchUnitId}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _save = _SaveState.failed;
        _saveError = e;
      });
      debugPrint('[SCRATCH] 저장 실패 ${unit.scratchUnitId}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = kSidoColors[widget.region.sido];
    final t = AppThemeScope.of(context);
    // **다 긁었으면 기록되기 전에는 나가지 못하게 한다.**
    //
    // 저장 중만 막았더니 **실패 상태에서 뒤로가기와 X 로 빠져나갈 수 있었다**
    // — 긁은 것이 그대로 버려진다(Codex 16회차). 완료 이후의 이탈은
    // `saved` 일 때만 허용한다.
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(_save == _SaveState.saving
                    ? '기록하는 중입니다. 잠시만요.'
                    : '아직 기록되지 않았습니다. 다시 시도해 주세요.'),
                duration: const Duration(seconds: 3)),
          );
        }
      },
      child: _buildBody(context, color, t),
    );
  }

  Widget _buildBody(BuildContext context, Color color, AppTheme t) {
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    // 통합 긁기 단위는 지역명이 시도명과 같다.
                    // 그대로 이으면 "서울특별시 서울특별시" 가 된다.
                    widget.sidoName == widget.region.name
                        ? widget.region.name
                        : '${widget.sidoName} ${widget.region.name}',
                    style: TextStyle(
                      color: t.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    // 기록되기 전에는 닫기도 막는다. `PopScope` 와 같은 이유다.
                    onPressed:
                        _canLeave ? () => Navigator.of(context).pop() : null,
                    icon: Icon(Icons.close, color: t.onSurfaceFaint),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  // 준비는 빌드 밖에서 한다. 다도해는 Path.contains 를 3만 회 넘게
                  // 부르므로 빌드 중에 하면 화면 전환이 눈에 띄게 멈춘다.
                  if (_preparedFor != size) {
                    if (!_preparing) {
                      _preparing = true;
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _prepare(size));
                    }
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  return GestureDetector(
                    onPanStart: (e) =>
                        _addPoint(e.localPosition, newStroke: true),
                    onPanUpdate: (e) =>
                        _addPoint(e.localPosition, newStroke: false),
                    child: AnimatedBuilder(
                      animation: _fade,
                      builder: (context, _) => CustomPaint(
                        size: size,
                        painter: _ScratchPainter(
                          path: _path!,
                          baseColor: color,
                          strokes: _strokes,
                          foilOpacity: 1 - _fade.value,
                          art: artForRegion(widget.region.scratchUnitId),
                          artTarget: _artTarget,
                          artClip: _artClip,
                          artVariant: artVariantFor(widget.region.scratchUnitId),
                          artCache: _artCache,
                          foilLight: t.foilLight,
                          foilDark: t.foilDark,
                          outline: t.onSurface,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: _done ? 1 : _ratio,
                            minHeight: 8,
                            backgroundColor: t.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _done ? '완료!' : '${(_ratio * 100).round()}%',
                        style: TextStyle(
                          color: t.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _buildFooter(t),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  _ScratchPainter({
    required this.path,
    required this.baseColor,
    required this.strokes,
    required this.foilOpacity,
    required this.art,
    required this.artTarget,
    required this.artClip,
    required this.artVariant,
    required this.artCache,
    required this.foilLight,
    required this.foilDark,
    required this.outline,
  });

  /// 은박 결과 지역 외곽선. `CustomPainter` 는 context 가 없어 받아 온다.
  final Color foilLight;
  final Color foilDark;
  final Color outline;

  final Path path;
  final Color baseColor;
  final List<List<Offset>> strokes;
  final double foilOpacity;

  /// 긁으면 드러나는 아트. 없으면(1층 폴백) 단색만 보인다.
  final RegionArt? art;

  /// 아트를 놓을 자리. 준비 단계에서 한 번 계산한다 — `Path.contains` 를
  /// 여러 번 부르므로 매 입력 프레임에 다시 구하면 안 된다.
  final Rect? artTarget;

  /// 다도해에서 아트를 가둘 섬 하나. `null` 이면 지역 전체로 가둔다.
  final Path? artClip;

  /// 같은 카테고리가 반복될 때 그림을 흩뜨리는 변형.
  final ArtVariant artVariant;
  final RegionArtCache artCache;

  @override
  void paint(Canvas canvas, Size size) {
    // 긁으면 드러나는 밑색
    canvas.drawPath(path, Paint()..color = baseColor);

    // 그 위에 랜드마크 또는 카테고리 아트. 지역 모양으로 잘라내지 않으면
    // bounds 중앙에 놓인 아트가 경계 밖으로 삐져나온다 — 특히 다도해와
    // 세로로 긴 지역에서 두드러진다.
    //
    // 매 입력 프레임마다 이 painter 가 다시 도는데, 아트를 그때마다 파싱하고
    // 그리면 그 비용이 전부 얹힌다. Picture 로 기록해두고 재생만 한다.
    if (art case final a? when artTarget != null) {
      canvas.save();
      canvas.clipPath(artClip ?? path);
      canvas.drawPicture(artCache.obtain(a, artTarget!, variant: artVariant));
      canvas.restore();
    }

    if (foilOpacity > 0) {
      // BlendMode.clear 는 레이어 안에서 써야 은박만 뚫린다.
      // saveLayer 의 paint 알파가 자동 완성 페이드아웃을 겸한다.
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, foilOpacity),
      );
      final b = path.getBounds();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            b.topLeft,
            b.bottomRight,
            [foilLight, foilDark, foilLight],
            const [0, .5, 1],
          ),
      );
      final erase = Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ScratchPageState.brush * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final s in strokes) {
        if (s.length == 1) {
          canvas.drawCircle(
            s.first,
            _ScratchPageState.brush,
            Paint()..blendMode = BlendMode.clear,
          );
        } else {
          final line = Path()..moveTo(s.first.dx, s.first.dy);
          for (final o in s.skip(1)) {
            line.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(line, erase);
        }
      }
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = outline.withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(_ScratchPainter old) => true;
  // strokes 는 같은 리스트를 제자리에서 수정하므로 참조 비교가 무의미하다.
  // 리페인트는 어차피 setState 로만 유발되니 항상 true 로 둔다.
}
