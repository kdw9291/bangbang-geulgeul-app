import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'frame_stats.dart';
import 'hit_test.dart';
import 'map_data.dart';
import 'map_painter.dart';
import 'region_art.dart';
import 'scratch_page.dart';
import 'sea_background.dart';

void main() => runApp(const MapScratchApp());

class MapScratchApp extends StatefulWidget {
  const MapScratchApp({super.key});

  @override
  State<MapScratchApp> createState() => _MapScratchAppState();
}

class _MapScratchAppState extends State<MapScratchApp> {
  /// 바다 팔레트를 앱 최상위에 둔다. 여기서 UI 테마가 함께 결정된다.
  ///
  /// `--dart-define=SEA=flat` 으로 단색과 교대 측정할 수 있다.
  /// M12 설정 화면이 생기면 이 값을 사용자가 바꾼다.
  final SeaPalette _sea = seaPaletteByName(
      const String.fromEnvironment('SEA', defaultValue: 'cerulean'));

  AppTheme get _theme => themeForSea(_sea.brightness);

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    return MaterialApp(
      title: '방방긁긁',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA8752A),
          brightness: t.brightness,
        ),
        useMaterial3: true,
      ),
      // **`home` 이 아니라 `builder` 에서 감싼다.** 팝업은 `showModalBottomSheet`
      // 로 Navigator 위에 뜨므로 페이지 아래에 둔 Scope 를 보지 못한다.
      builder: (context, child) => AppThemeScope(theme: t, child: child!),
      home: MapSpikePage(sea: _sea),
    );
  }
}

/// T2 지도 렌더 스파이크.
/// 목적은 두 가지다 — 231개 폴리곤이 렌더되는가, 확대·이동 중 60fps 가 유지되는가.
class MapSpikePage extends StatefulWidget {
  const MapSpikePage({super.key, required this.sea});

  final SeaPalette sea;

  @override
  State<MapSpikePage> createState() => _MapSpikePageState();
}

class _MapSpikePageState extends State<MapSpikePage>
    with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  final _stats = FrameStats();
  late final AnimationController _bench;

  MapData? _data;
  Object? _error;
  bool _sidoLines = true;
  bool _benchmarking = false;
  /// 일반 실행은 **문서상 채택안과 같은 설정**으로 시작한다.
  /// 초기 구현은 `direct` 로 시작해, 채택했다고 적어둔 경로가 실제로는
  /// 한 번도 실행되지 않는 상태였다.
  RenderConfig _config = RenderConfig.adopted;

  /// 긁기를 완료한 지역의 `Region.scratchUnitId` 집합.
  ///
  /// **제자리에서 수정하지 않는다.** painter 가 이 Set 을 그대로 들고 있어서,
  /// `add`/`clear` 로 고치면 이전 painter 와 새 painter 가 같은 객체를 보게 되고
  /// `shouldRepaint` 가 변경을 감지하지 못한다. 항상 새 스냅샷으로 교체한다.
  Set<String> _scratched = const <String>{};
  final _cache = MapPictureCache();

  /// 바다 배경. 은박 색도 여기서 따라온다 — 배경이 밝아지면 은박이 함께
  /// 조정되지 않으면 미수집 지역이 배경에 묻힌다.
  SeaPalette get _sea => widget.sea;
  final _seaCache = SeaBackgroundCache();

  /// 애니메이션 틱 수. 프레임이 안 나올 때 "애니메이션이 멈춘 것"인지
  /// "그리다가 못 따라가는 것"인지 구분하려면 이 값이 필요하다.
  int _ticks = 0;

  RegionHitTester? _hitTester;
  Region? _selected;

  @override
  void initState() {
    super.initState();
    _stats.start();
    _bench = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addListener(_driveBenchmark);
    _load();
  }

  /// `--dart-define=AUTOBENCH=true` 로 실행하면 화면을 보지 않고
  /// 로그만으로 프레임 성능을 측정할 수 있다.
  static const bool _autoBench = bool.fromEnvironment('AUTOBENCH');

  Future<void> _load() async {
    try {
      final d = await MapData.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _hitTester = RegionHitTester(d.regions);
      });
      debugPrint('[BENCH] 로딩 ${d.loadMs}ms '
          '(읽기 ${d.readMs}ms · JSON ${d.decodeMs}ms · Path ${d.pathMs}ms) · '
          '지역 ${d.regions.length}개 · 정점 ${d.vertexCount}개');
      if (_autoBench) _runAutoBench();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// 네 가지 렌더 방식을 순서대로 돌려 각각의 프레임 성능을 로그로 남긴다.
  /// 한 번의 실행으로 비교표가 나오도록 한 것.
  /// 비교할 설정. **채택안(Picture+획)이 반드시 포함돼야 한다** — 실제로 쓰는
  /// 조합을 측정하지 않으면 성능 근거가 되지 않는다.
  static const _benchConfigs = <RenderConfig>[
    RenderConfig(RenderMode.direct), // 직접+획 (기준선)
    RenderConfig.adopted, // Picture+획 ← 채택안
    RenderConfig(RenderMode.picture, strokes: false), // 획 비용 분리
    RenderConfig(RenderMode.pictureBoundary), // Picture+경계+획
  ];

  void _runAutoBench() {
    _toggleBenchmark();
    final modes = _benchConfigs;
    var i = 0;

    void runMode() {
      if (!mounted || i >= modes.length) {
        if (mounted) debugPrint('[BENCH] 측정 종료');
        return;
      }
      setState(() => _config = modes[i]);
      // 워밍업 2.5초는 버린다 — 셰이더 컴파일과 첫 래스터가 섞이면 정상 상태가 아니다.
      Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        _stats.reset();
        _ticks = 0;
        Timer(const Duration(seconds: 4), () {
          if (!mounted) return;
          debugPrint('[BENCH] ${modes[i].label.padRight(16)} '
              'fps=${_stats.measuredFps.toStringAsFixed(1).padLeft(5)} '
              '(여유 ${_stats.headroomFps.toStringAsFixed(0).padLeft(3)}) '
              'build=${_stats.avgBuildMs.toStringAsFixed(2).padLeft(6)}ms '
              'raster=${_stats.avgRasterMs.toStringAsFixed(2).padLeft(7)}ms '
              'worst=${_stats.worstTotalMs.toStringAsFixed(1).padLeft(6)}ms '
              'jank=${(_stats.jankRatio * 100).toStringAsFixed(0).padLeft(3)}% '
              'n=${_stats.frames} '
              '구간=${_stats.elapsedSeconds.toStringAsFixed(1)}s '
              'ticks=$_ticks anim=${_bench.isAnimating}');
          i++;
          runMode();
        });
      });
    }

    runMode();
  }

  /// 손으로 드래그하면 측정이 들쭉날쭉하다. 일정한 확대·이동을 반복시켜
  /// 지속 부하 상태의 프레임을 모은다.
  void _driveBenchmark() {
    _ticks++;
    final t = _bench.value * 2 * math.pi;
    final scale = 2.6 + 1.8 * math.sin(t);
    final dx = 120 * math.cos(t);
    final dy = 160 * math.sin(t * 0.7);
    _tc.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// [local] 은 지도 위젯 기준 좌표, [renderWidth] 는 그 위젯의 실제 폭.
  /// 페인터가 `size.width / data.size.width` 로 축소해 그리므로 그 역수를 곱한다.
  void _onTapMap(Offset local, MapData d, double renderWidth) {
    final tester = _hitTester;
    if (tester == null) return;
    final k = d.size.width / renderWidth;
    final mapPoint = Offset(local.dx * k, local.dy * k);

    // 허용 오차는 화면 픽셀 기준이다. 손가락 굵기는 배율과 무관하므로
    // 확대할수록 지도 좌표계에서의 허용 거리는 줄어들어야 한다.
    final tol = tapToleranceInMapUnits(
      mapUnitsPerWidgetPx: k,
      viewerScale: _tc.value.getMaxScaleOnAxis(),
    );

    final sw = Stopwatch()..start();
    final hit = tester.nearest(mapPoint, tolerance: tol);
    sw.stop();

    debugPrint('[HIT] 화면(${local.dx.toStringAsFixed(0)},'
        '${local.dy.toStringAsFixed(0)}) → '
        '지도(${mapPoint.dx.toStringAsFixed(1)},${mapPoint.dy.toStringAsFixed(1)}) '
        '= ${hit == null ? "바다" : "${d.sidoNames[hit.sido]} ${hit.name}(${hit.scratchUnitId})"} '
        '· 허용 ${tol.toStringAsFixed(1)}km · ${sw.elapsedMicroseconds}us');

    setState(() => _selected = hit);
    if (hit != null && !_benchmarking) _openRegion(hit, d);
  }

  /// 지역 탭 → 소개 팝업 → "지역 긁기" → 전용 긁기 화면 → 완료 시 컬러 채움.
  Future<void> _openRegion(Region r, MapData d) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppThemeScope.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _RegionSheet(
        region: r,
        sidoName: d.sidoNames[r.sido],
        scratched: _scratched.contains(r.scratchUnitId),
      ),
    );
    if (go != true || !mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScratchPage(region: r, sidoName: d.sidoNames[r.sido]),
      ),
    );
    if (done == true && mounted) {
      setState(() => _scratched = {..._scratched, r.scratchUnitId});
      debugPrint('[SCRATCH] 지도 반영 ${r.scratchUnitId} · '
          '수집 ${_scratched.length}/${_data!.regions.length}');
    }
  }

  void _toggleBenchmark() {
    setState(() {
      _benchmarking = !_benchmarking;
      if (_benchmarking) {
        _stats.reset();
        _bench.repeat();
      } else {
        _bench.stop();
        _tc.value = Matrix4.identity();
      }
    });
  }

  @override
  void dispose() {
    _bench.dispose();
    _tc.dispose();
    _stats.dispose();
    _cache.dispose();
    _seaCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final t = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('지도 데이터를 불러오지 못했습니다.\n$_error',
                      style: TextStyle(color: t.onSurfaceMuted)),
                ),
              )
            : d == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(child: _buildMap(d)),
                      _StatsBar(
                        stats: _stats,
                        data: d,
                        selected: _selected == null
                            ? null
                            : '${d.sidoNames[_selected!.sido]} '
                                '${_selected!.name}',
                      ),
                      _Controls(
                        benchmarking: _benchmarking,
                        sidoLines: _sidoLines,
                        onBenchmark: _toggleBenchmark,
                        onSidoLines: () =>
                            setState(() => _sidoLines = !_sidoLines),
                        onReset: () {
                          _tc.value = Matrix4.identity();
                          _stats.reset();
                        },
                        onZoom3x: () {
                          _tc.value = Matrix4.identity()
                            ..scaleByDouble(3, 3, 1, 1);
                          debugPrint('[HIT] 배율 3배 고정');
                        },
                        onFillDemo: () => setState(() {
                          _scratched = _scratched.isEmpty
                              ? d.regions.take(60).map((r) => r.scratchUnitId).toSet()
                              : const <String>{};
                        }),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildMap(MapData d) {
    return LayoutBuilder(
      builder: (context, c) {
        final aspect = d.size.height / d.size.width;
        var w = c.maxWidth;
        if (w * aspect > c.maxHeight) w = c.maxHeight / aspect;
        Widget map = CustomPaint(
          painter: KoreaMapPainter(
            data: d,
            scratched: _scratched,
            showSidoLines: _sidoLines,
            sea: _sea,
            seaCache: _seaCache,
            theme: AppThemeScope.of(context),
            foilColor: _sea.foil,
            config: _config,
            cache: _cache,
            selected: _selected,
          ),
          isComplex: true,
        );
        if (_config.mode == RenderMode.pictureBoundary) {
          map = RepaintBoundary(child: map);
        }
        // GestureDetector 를 InteractiveViewer 안쪽에 두면 확대·이동 변환의
        // 역변환을 Flutter 가 알아서 해준다. localPosition 은 항상 지도
        // 위젯 기준 좌표로 들어온다.
        map = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => _onTapMap(e.localPosition, d, w),
          child: map,
        );
        return Center(
          // **지도 밖 빈 공간이 보이지 않게 이동·축소를 제한한다.**
          //
          // `boundaryMargin` 이 400 이면 사방 400px 까지 끌어낼 수 있어 지도가
          // 화면 밖으로 밀려나고 배경만 남는다. `minScale` 이 1 미만이면 축소
          // 했을 때 지도가 화면보다 작아져 같은 문제가 생긴다.
          //
          // `w` 는 화면에 맞춰 계산한 폭이므로 배율 1이 "꽉 찬 상태"다.
          // 여기서 더 줄일 이유가 없다.
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1.0,
            maxScale: 16,
            boundaryMargin: EdgeInsets.zero,
            child: SizedBox(width: w, height: w * aspect, child: map),
          ),
        );
      },
    );
  }
}

/// 지역 소개 팝업. 소개 글은 아직 준비 전이라 자리만 잡아둔다 —
/// 실제 문구와 랜드마크는 T6 아트 전략에서 채운다.
class _RegionSheet extends StatelessWidget {
  const _RegionSheet({
    required this.region,
    required this.sidoName,
    required this.scratched,
  });

  final Region region;
  final String sidoName;
  final bool scratched;

  @override
  Widget build(BuildContext context) {
    final color = kSidoColors[region.sido];
    final t = AppThemeScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.onSurfaceGhost,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    region.name,
                    style: TextStyle(
                      color: t.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // 통합 긁기 단위는 지역명이 시도명과 같다. 둘 다 쓰면
                // "서울특별시  서울특별시" 가 된다.
                if (sidoName != region.name)
                  Text(sidoName,
                      style:
                          TextStyle(color: t.onSurfaceFaint, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 14),
            _RegionArtCard(region: region, color: color, revealed: scratched),
            const SizedBox(height: 14),
            Text(
              scratched
                  ? _artName(region) == null
                      ? '이미 수집한 지역이에요.'
                      : '이미 수집한 지역이에요. ${_artName(region)}.'
                  : '복권처럼 긁어서 이 지역을 수집해 보세요. '
                      '무엇이 나올지는 긁어야 알 수 있어요.',
              style: TextStyle(
                  color: t.onSurfaceMuted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: scratched
                  ? OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('닫기'),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: color),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('지역 긁기'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 팝업의 아트 자리. 소개 글이 비어 있던 곳이다.
///
/// **아직 안 긁은 지역은 아트를 가린다.** "가리고 긁을 때 공개" 결정(2026-08-13)이
/// 팝업에도 적용된다 — 여기서 미리 보여주면 긁을 이유가 없어진다.
class _RegionArtCard extends StatelessWidget {
  const _RegionArtCard({
    required this.region,
    required this.color,
    required this.revealed,
  });

  final Region region;
  final Color color;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final art = artForRegion(region.scratchUnitId);
    final t = AppThemeScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: CustomPaint(
          painter: _ArtCardPainter(
            art: art,
            color: color,
            revealed: revealed,
            variant: artVariantFor(region.scratchUnitId),
            foilLight: t.foilLight,
            foilDark: t.foilDark,
          ),
          child: revealed || art == null
              ? null
              : Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      color: t.onSurfaceFaint,
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ArtCardPainter extends CustomPainter {
  _ArtCardPainter({
    required this.art,
    required this.color,
    required this.revealed,
    required this.variant,
    required this.foilLight,
    required this.foilDark,
  });

  final RegionArt? art;
  final Color color;
  final bool revealed;
  final ArtVariant variant;

  /// 은박 결. `CustomPainter` 는 context 가 없어 색을 받아 온다.
  final Color foilLight;
  final Color foilDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (!revealed) {
      // 긁기 화면의 은박과 같은 결. 무엇이 있는지 알 수 없게 둔다.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.bottomRight,
            [foilLight, foilDark, foilLight],
            const [0, .5, 1],
          ),
      );
      return;
    }
    canvas.drawRect(rect, Paint()..color = color);
    if (art case final a?) {
      // 카드는 가로로 길다. 정사각형 아트를 세로에 맞춰 넣으면 좌우가 남으므로
      // 긴 변에 맞춰 채우고 넘치는 부분을 잘라낸다 — 긁기 화면의 B 배치와 같다.
      final side = math.max(size.width, size.height);
      final target = Rect.fromCenter(
          center: rect.center, width: side, height: side);
      canvas.save();
      canvas.clipRect(rect);
      paintRegionArt(canvas, a, target, variant: variant);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ArtCardPainter old) =>
      old.revealed != revealed ||
      old.color != color ||
      !identical(old.art, art) ||
      old.variant != variant ||
      old.foilLight != foilLight ||
      old.foilDark != foilDark;
}

/// 팝업 문구에 쓸 아트 이름. 랜드마크면 소재 이름, 카테고리면 `null`.
String? _artName(Region region) => kLandmarkArt[region.scratchUnitId]?.name;

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats, required this.data, this.selected});

  final FrameStats stats;
  final MapData data;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: stats,
      builder: (context, _) {
        final ok = stats.jankRatio < 0.05;
        final t = AppThemeScope.of(context);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: t.surface,
          child: DefaultTextStyle(
            style: TextStyle(
                fontSize: 12,
                color: t.onSurfaceMuted,
                fontFamily: 'monospace'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${stats.measuredFps.toStringAsFixed(0)} fps',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: ok ? t.good : t.bad)),
                    const SizedBox(width: 8),
                    Text('여유 ${stats.headroomFps.toStringAsFixed(0)}'),
                    const SizedBox(width: 10),
                    Text('예산 초과 ${(stats.jankRatio * 100).toStringAsFixed(0)}%'
                        ' · ${stats.frames}프레임'),
                  ],
                ),
                const SizedBox(height: 4),
                Text('빌드 ${stats.avgBuildMs.toStringAsFixed(1)}ms  '
                    '래스터 ${stats.avgRasterMs.toStringAsFixed(1)}ms  '
                    '최악 ${stats.worstTotalMs.toStringAsFixed(1)}ms  '
                    '구간 ${stats.elapsedSeconds.toStringAsFixed(1)}s'),
                Text('지역 ${data.regions.length}개 · 정점 ${data.vertexCount}개 · '
                    '로딩 ${data.loadMs}ms'),
                Text(selected == null
                    ? '지도를 탭하면 지역이 판정됩니다'
                    : '선택: $selected'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.benchmarking,
    required this.sidoLines,
    required this.onBenchmark,
    required this.onSidoLines,
    required this.onReset,
    required this.onFillDemo,
    required this.onZoom3x,
  });

  final bool benchmarking;
  final bool sidoLines;
  final VoidCallback onBenchmark, onSidoLines, onReset, onFillDemo, onZoom3x;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeScope.of(context).surface,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: onBenchmark,
            child: Text(benchmarking ? '벤치마크 중지' : '벤치마크 시작'),
          ),
          OutlinedButton(
            onPressed: onSidoLines,
            child: Text(sidoLines ? '시도선 끄기' : '시도선 켜기'),
          ),
          OutlinedButton(onPressed: onFillDemo, child: const Text('60칸 채우기')),
          // adb 로는 핀치 줌을 넣을 수 없어, 확대 상태의 좌표 변환을 검증하려면
          // 배율을 코드로 고정하는 수단이 필요하다.
          OutlinedButton(onPressed: onZoom3x, child: const Text('3배 확대')),
          OutlinedButton(onPressed: onReset, child: const Text('초기화')),
        ],
      ),
    );
  }
}
