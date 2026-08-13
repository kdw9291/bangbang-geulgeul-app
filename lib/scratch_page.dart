import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
/// 긁기 완료 시 `Navigator.pop(true)` 로 닫힌다. 중간에 나가면 진행은 버려진다
/// (부분 진행 저장은 S2 MVP 본개발 범위).
class ScratchPage extends StatefulWidget {
  const ScratchPage({
    super.key,
    required this.region,
    required this.sidoName,
  });

  final Region region;
  final String sidoName;

  @override
  State<ScratchPage> createState() => _ScratchPageState();
}

class _ScratchPageState extends State<ScratchPage>
    with SingleTickerProviderStateMixin {
  /// 이 비율 이상 긁으면 나머지를 자동 완성한다.
  /// 실물 복권도 구석까지 긁는 사람은 없다 — 끝까지 강요하면 답답해진다.
  static const threshold = 0.65;

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

  double get _ratio => _progress?.ratio ?? 0;

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
    if (artForRegion(region.code) != null) {
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
    final avg = _panEvents == 0 ? 0 : _panMicros ~/ _panEvents;
    debugPrint('[SCRATCH] 완료 ${widget.region.code} ${widget.region.name} '
        'ratio=${(_ratio * 100).toStringAsFixed(0)}% '
        'pan=$_panEvents회 handler=${avg}us '
        'fps=${_stats.measuredFps.toStringAsFixed(1)} '
        '(여유 ${_stats.headroomFps.toStringAsFixed(0)}) '
        'jank=${(_stats.jankRatio * 100).toStringAsFixed(0)}% '
        'worst=${_stats.worstTotalMs.toStringAsFixed(1)}ms '
        '구간=${_stats.elapsedSeconds.toStringAsFixed(1)}s');
  }

  @override
  Widget build(BuildContext context) {
    final color = kSidoColors[widget.region.sido];
    return Scaffold(
      backgroundColor: const Color(0xFF141319),
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
                    '${widget.sidoName} ${widget.region.name}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(_done),
                    icon: const Icon(Icons.close, color: Colors.white54),
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
                          art: artForRegion(widget.region.code),
                          artTarget: _artTarget,
                          artClip: _artClip,
                          artCache: _artCache,
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
                            backgroundColor: const Color(0xFF2A2833),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _done ? '완료!' : '${(_ratio * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _done
                        ? FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('지도로 돌아가기'),
                          )
                        : const Text(
                            '손가락으로 문질러 긁어보세요',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white38, fontSize: 13),
                          ),
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
    required this.artCache,
  });

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
      canvas.drawPicture(artCache.obtain(a, artTarget!));
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
            const [Color(0xFF5A5766), Color(0xFF3B3944), Color(0xFF5A5766)],
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
        ..color = Colors.white.withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(_ScratchPainter old) => true;
  // strokes 는 같은 리스트를 제자리에서 수정하므로 참조 비교가 무의미하다.
  // 리페인트는 어차피 setState 로만 유발되니 항상 true 로 둔다.
}
