import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'frame_stats.dart';
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
    // 다도해 지역은 bounds 가 넓어 표본이 성기지 않게 격자를 촘촘히 잡는다.
    const grid = 40;
    final samples = <Offset>[];
    for (var i = 0; i <= grid; i++) {
      for (var j = 0; j <= grid; j++) {
        final p = Offset(
          b.left + b.width * i / grid,
          b.top + b.height * j / grid,
        );
        if (widget.region.path.contains(p)) {
          samples.add(MatrixUtils.transformPoint(m, p));
        }
      }
    }
    _samples = samples;
    _covered = List.filled(samples.length, false);
    _stats.reset(); // 준비 단계 프레임은 측정에서 제외
  }

  void _addPoint(Offset p, {required bool newStroke}) {
    if (_done) return;
    final sw = Stopwatch()..start();
    if (newStroke || _strokes.isEmpty) {
      _strokes.add([p]);
    } else {
      _strokes.last.add(p);
    }
    for (var i = 0; i < _samples.length; i++) {
      if (_covered[i]) continue;
      if ((_samples[i] - p).distanceSquared <= brush * brush) {
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
        'fps=${_stats.estimatedFps.toStringAsFixed(1)} '
        'jank=${(_stats.jankRatio * 100).toStringAsFixed(0)}% '
        'worst=${_stats.worstTotalMs.toStringAsFixed(1)}ms');
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
