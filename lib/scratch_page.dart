import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'frame_stats.dart';
import 'geometry.dart';
import 'map_data.dart';

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
  List<Offset> _samples = const []; // 면적 비율 계산용 내부 표본점
  List<bool> _covered = const [];
  int _coveredCount = 0;
  bool _done = false;

  final _stats = FrameStats();
  int _panEvents = 0;
  int _panMicros = 0;

  double get _ratio =>
      _samples.isEmpty ? 0 : _coveredCount / _samples.length;

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
    super.dispose();
  }

  /// 면적 비율 계산에 쓸 최소 표본 수.
  ///
  /// 고정 격자만 쓰면 bounds 대비 실제 육지가 작은 다도해에서 표본이 극히 적어진다.
  /// 옹진군은 41x41 격자에서 15개뿐이라 한 점이 6.7% 를 좌우했다.
  static const minSamples = 300;

  /// 표본 격자 상한. 이 이상은 `Path.contains` 호출 비용이 화면 진입을 늦춘다.
  static const maxGrid = 220;

  /// 지역 Path 를 화면 크기에 맞춰 변환하고, 면적 계산용 표본점을 깐다.
  /// 레이아웃 크기가 정해진 뒤 한 번만 실행된다.
  void _prepare(Size size) {
    if (_path != null) return;
    final b = widget.region.bounds;
    const pad = 36.0;
    final k = math.min(
      (size.width - pad * 2) / b.width,
      (size.height - pad * 2) / b.height,
    );
    final m = Matrix4.identity()
      ..translateByDouble(
        size.width / 2 - b.center.dx * k,
        size.height / 2 - b.center.dy * k,
        0,
        1,
      )
      ..scaleByDouble(k, k, 1, 1);
    _path = widget.region.path.transform(m.storage);

    // 원본(지도) 좌표에서 내부 판정 후 화면 좌표로 옮긴다.
    //
    // 격자를 고정하면 다도해에서 표본이 말라붙는다. 1차로 성기게 훑어 육지 비율을
    // 구한 뒤, 필요한 격자 크기를 역산해 한 번만 더 훑는다. 전수 확대가 아니라
    // 2회 통과라 비용이 예측 가능하다.
    var samples = _collectSamples(b, m, 40);
    if (samples.length < minSamples) {
      const first = 41 * 41;
      final landRatio = samples.length / first;
      final needed = landRatio <= 0
          ? maxGrid
          : math.sqrt(minSamples / landRatio).ceil();
      final grid = needed.clamp(41, maxGrid);
      samples = _collectSamples(b, m, grid);
    }
    _samples = samples;
    _covered = List.filled(_samples.length, false);
    _stats.reset(); // 준비 단계 프레임은 측정에서 제외
    debugPrint('[SCRATCH] 준비 ${widget.region.name} '
        '표본 ${_samples.length}개 (1점당 '
        '${_samples.isEmpty ? 0 : (100 / _samples.length).toStringAsFixed(2)}%)');
  }

  /// [grid] x [grid] 로 bounds 를 훑어 폴리곤 내부 점만 화면 좌표로 모은다.
  List<Offset> _collectSamples(Rect b, Matrix4 m, int grid) {
    final out = <Offset>[];
    for (var i = 0; i <= grid; i++) {
      final x = b.left + b.width * i / grid;
      for (var j = 0; j <= grid; j++) {
        final p = Offset(x, b.top + b.height * j / grid);
        if (widget.region.path.contains(p)) {
          out.add(MatrixUtils.transformPoint(m, p));
        }
      }
    }
    return out;
  }

  void _addPoint(Offset p, {required bool newStroke}) {
    if (_done) return;
    final sw = Stopwatch()..start();

    // 이전 점을 기억해 두고 **선분** 기준으로 덮인 표본을 센다.
    // 화면에는 두 점 사이를 선으로 이어 지우는데 진행률만 점 기준으로 세면,
    // 손가락을 빠르게 움직여 이벤트 간격이 벌어질수록 같은 자취인데도
    // 진행률이 낮게 나온다. 즉 기기와 입력 속도에 따라 값이 달라진다.
    Offset? prev;
    if (newStroke || _strokes.isEmpty) {
      _strokes.add([p]);
    } else {
      prev = _strokes.last.last;
      _strokes.last.add(p);
    }

    for (var i = 0; i < _samples.length; i++) {
      if (_covered[i]) continue;
      final s = _samples[i];
      final d = prev == null
          ? (s - p).distance
          : distancePointToSegment(s, prev, p);
      if (d <= brush) {
        _covered[i] = true;
        _coveredCount++;
      }
    }
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
                  _prepare(size);
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
  });

  final Path path;
  final Color baseColor;
  final List<List<Offset>> strokes;
  final double foilOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    // 긁으면 드러나는 밑색 (나중에 랜드마크 일러스트가 들어갈 자리)
    canvas.drawPath(path, Paint()..color = baseColor);

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
