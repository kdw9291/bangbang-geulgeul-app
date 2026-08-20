import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'achievement.dart';
import 'app_flags.dart';
import 'app_theme.dart';
import 'collection.dart';
import 'collection_store.dart';
import 'frame_stats.dart';
import 'gallery_page.dart';
import 'hit_test.dart';
import 'map_data.dart';
import 'map_inset_panel.dart';
import 'map_painter.dart';
import 'medal_celebration.dart';
import 'records_page.dart';
import 'region_art.dart';
import 'region_description.dart';
import 'region_search.dart';
import 'scratch_page.dart';
import 'search_sheet.dart';
import 'sea_background.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'settings_store.dart';
import 'sido_progress.dart';

/// **설정을 읽은 뒤에 첫 프레임을 낸다.**
///
/// 화면을 먼저 띄우고 나중에 테마를 바꾸면, 어두운 바다를 고른 사용자가
/// **흰 화면이 한 프레임 번쩍이는 것**을 본다(Codex 22회차). 그 사이에는
/// Android 런치 화면이 그대로 보인다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SettingsStore? settings;
  try {
    settings = SettingsStore(await FileSettingsStorage.open());
    await settings.load();
  } catch (e) {
    // 설정을 못 읽어도 앱은 떠야 한다. 잃는 것은 취향 하나다.
    debugPrint('[SETTINGS] 열지 못했다 — 기본값으로 시작한다: $e');
    settings = null;
  }
  runApp(MapScratchApp(settings: settings));
}

/// 저장소를 아예 열지 못했을 때 쓰는 자리 채움.
/// 읽기·쓰기 모두 실패시켜 **조용히 빈 상태로 덮어쓰는 일을 막는다.**
class _UnavailableStorage implements CollectionStorage {
  @override
  Future<String?> read() => Future.error(StateError('저장소를 열지 못했다'));
  @override
  Future<void> writeAtomically(String contents) =>
      Future.error(StateError('저장소를 열지 못했다'));
  @override
  Future<String> quarantine() => Future.error(StateError('저장소를 열지 못했다'));
}

/// 지도 에셋을 읽는다. 테스트가 **타이밍을 제어**하려고 갈아 끼운다.
typedef MapLoader = Future<MapData> Function();

/// 수집 기록 저장소를 열고 로드한다. 테스트가 정상·손상·실패 상태를 만든다.
typedef StoreOpener = Future<(CollectionStore, CollectionLoadResult)> Function();

/// 설정 저장소를 열고 로드한다.
typedef SettingsOpener = Future<SettingsStore> Function();

class MapScratchApp extends StatefulWidget {
  const MapScratchApp({
    super.key,
    this.mapLoader,
    this.storeOpener,
    this.settingsOpener,
    this.settings,
    this.showDiagnostics,
    this.showInset,
  })  : assert(settings == null || settingsOpener == null,
            '설정 입구는 하나만 쓴다 — 둘 다 주면 settings 가 조용히 이긴다');

  /// **이미 읽어 둔 설정.** 주면 첫 프레임부터 올바른 테마로 그린다.
  /// `settingsOpener` 는 테스트가 로딩 순서를 제어할 때 쓴다.
  final SettingsStore? settings;

  /// 둘 다 `null` 이면 실제 에셋과 실제 파일 저장소를 쓴다.
  ///
  /// **주입 지점을 만든 이유**: `path_provider` 는 `flutter test` 에서
  /// `MissingPluginException` 이라 저장소가 늘 `readFailed` 로 떨어졌다.
  /// 그러면 **정상 배선을 테스트가 한 번도 지나가지 않는다**(Codex 16회차).
  final MapLoader? mapLoader;
  final StoreOpener? storeOpener;
  final SettingsOpener? settingsOpener;

  /// S1 진단 UI 노출 여부. `null` 이면 `!kReleaseMode` 다.
  /// 테스트가 **릴리스 구성**을 재현하려고 `false` 를 준다.
  final bool? showDiagnostics;

  /// 도심 확대 인셋 노출 여부. `null` 이면 [kShowMapInset] 다.
  /// 인셋 테스트가 `true` 를 줘서 기능 자체는 계속 검증한다.
  final bool? showInset;

  @override
  State<MapScratchApp> createState() => _MapScratchAppState();
}

/// `--dart-define=SEA=...` 로 고정한 팔레트. 비어 있으면 사용자 설정을 쓴다.
const String _seaFromEnv = String.fromEnvironment('SEA');

class _MapScratchAppState extends State<MapScratchApp> {
  /// 바다 팔레트를 앱 최상위에 둔다. 여기서 UI 테마가 함께 결정된다.
  ///
  /// **환경값이 사용자 설정보다 우선한다.** `--dart-define=SEA=flat` 은 성능
  /// 측정용이라, 저장된 설정이 이를 덮으면 무엇을 쟀는지 알 수 없게 된다
  /// (Codex 22회차).
  SeaPalette _sea = seaPaletteByName(
      _seaFromEnv.isEmpty ? kDefaultSeaName : _seaFromEnv);

  bool get _seaLocked => _seaFromEnv.isNotEmpty;

  SettingsStore? _settings;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// 설정을 읽기 전에는 화면을 내보내지 않는다. 기본 테마로 먼저 그리면
  /// 어두운 바다를 고른 사용자가 **밝은 화면이 번쩍이는 것**을 본다.
  bool _ready = false;

  AppTheme get _theme => themeForSea(_sea.brightness);

  @override
  void initState() {
    super.initState();
    final given = widget.settings;
    if (given != null || widget.settingsOpener == null) {
      // `main()` 이 이미 읽어 왔다. 첫 프레임부터 올바른 테마로 그린다.
      _adopt(given ?? SettingsStore(_NullSettingsStorage()));
    } else {
      _loadSettings();
    }
  }

  void _adopt(SettingsStore store) {
    _settings = store;
    if (!_seaLocked) _sea = seaPaletteByName(store.current.seaName);
    _ready = true;
  }

  Future<void> _loadSettings() async {
    SettingsStore store;
    try {
      store = await widget.settingsOpener!();
    } catch (e) {
      // 설정을 못 읽어도 앱은 떠야 한다. 잃는 것은 취향 하나다.
      debugPrint('[SETTINGS] 열지 못했다 — 기본값으로 시작한다: $e');
      store = SettingsStore(_NullSettingsStorage());
    }
    if (!mounted) return;
    setState(() => _adopt(store));
  }

  /// 설정 화면이 부른다. 화면은 곧바로 바뀌고 저장이 뒤따른다.
  Future<void> _changeSea(String name) async {
    final store = _settings;
    if (store == null || _seaLocked) return;
    setState(() => _sea = seaPaletteByName(name));
    try {
      await store.setSea(name);
    } catch (_) {
      if (!mounted) return;
      // 앱 최상위 context 는 `MaterialApp` 밖이라 `ScaffoldMessenger.of` 가
      // 닿지 않는다. key 로 직접 잡는다.
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('바다 색을 저장하지 못했습니다. 앱을 다시 켜면 되돌아갑니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    if (!_ready) {
      // 테마가 아직 안 정해졌으므로 색을 쓰지 않고 로딩만 보여 준다.
      // 지도도 어차피 같은 시점에 로딩 중이라 화면이 하나 더 늘지 않는다.
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: '방방긁긁',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
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
      // **`key` 를 팔레트에 묶지 않는다.** 그러면 바다를 바꿀 때마다 State 가
      // 새로 생겨 지도와 저장소를 다시 읽고 확대 위치·선택이 초기화된다
      // (Codex 22회차).
      home: MapSpikePage(
        sea: _sea,
        mapLoader: widget.mapLoader,
        storeOpener: widget.storeOpener,
        showDiagnostics: widget.showDiagnostics,
        showInset: widget.showInset,
        // **지도 화면의 context 를 받아서 push 한다.** 여기(앱 최상위)의 context
        // 는 `MaterialApp` 보다 위라 Navigator 를 찾지 못한다.
        onOpenSettings: (ctx) => Navigator.of(ctx).push<void>(
          MaterialPageRoute(
            builder: (_) => SettingsPage(
              seaName: _sea.name,
              seaLocked: _seaLocked,
              onSeaChanged: _changeSea,
            ),
          ),
        ),
      ),
    );
  }
}

/// 설정 파일을 아예 열지 못했을 때.
///
/// 읽기는 비어 있다 — 설정이 없어도 앱은 돈다. **쓰기는 실패시킨다.**
/// 조용히 버리면 사용자가 저장된 줄 알고 앱을 껐다 켰을 때 되돌아간다
/// (Codex 22회차). 실패로 올려야 `_changeSea` 가 안내를 띄운다.
class _NullSettingsStorage implements SettingsStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> writeAtomically(String contents) =>
      Future.error(StateError('설정 저장소를 열지 못했다'));
}

/// T2 지도 렌더 스파이크.
/// 목적은 두 가지다 — 232개 폴리곤이 렌더되는가, 확대·이동 중 60fps 가 유지되는가.
class MapSpikePage extends StatefulWidget {
  const MapSpikePage({
    super.key,
    required this.sea,
    this.mapLoader,
    this.storeOpener,
    this.onOpenSettings,
    this.showDiagnostics,
    this.showInset,
  });

  /// 도심 확대 인셋 노출 여부. `null` 이면 [kShowMapInset] 다.
  final bool? showInset;

  /// S1 진단 UI(프레임 통계·벤치마크·시도선·3배 확대·데모 채움)를 보일지.
  ///
  /// 기본값은 **`!kReleaseMode`** 다 — 성능 측정은 profile 에서 하므로
  /// `kDebugMode` 로 막으면 정작 필요한 곳에서 사라진다(2026-08-15 실기기).
  ///
  /// **테스트가 갈아 끼울 수 있게 열어 뒀다.** `kReleaseMode` 는 컴파일 타임
  /// 상수라 위젯 테스트에서 뒤집을 수 없어, 이 seam 이 없으면 "릴리스에서는
  /// 사라진다" 를 아무 테스트도 지나가지 않는다(Codex 25회차).
  final bool? showDiagnostics;

  final SeaPalette sea;
  final MapLoader? mapLoader;
  final StoreOpener? storeOpener;

  /// 설정 화면 열기. 지도 화면의 `BuildContext` 를 넘겨 준다 —
  /// 앱 최상위 context 로는 Navigator 를 찾지 못한다.
  final void Function(BuildContext)? onOpenSettings;

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
  ///
  /// **원본이 아니라 파생 상태다.** 원본은 [_store] 의 `CollectionSnapshot` 이며
  /// 수집일시·메모·현재 카탈로그에 없는 ID 까지 들고 있다. 여기에는 지금 지도에
  /// 그릴 수 있는 것만 내려온다.
  Set<String> _scratched = const <String>{};
  final _cache = MapPictureCache();

  /// 수집 기록의 원본. 저장에 성공해야 스냅샷이 바뀐다.
  CollectionStore? _store;

  /// 이름·초성 검색. 에셋을 읽은 뒤에 만든다.
  RegionSearcher? _searcher;

  /// 저장 로드 결과. 쓸 수 없는 상태면 긁기 화면 진입을 막는다.
  CollectionLoadResult? _loadResult;

  /// **데모용 임시 채움.** 실제 기록과 분리한다.
  ///
  /// 예전에는 `_scratched` 를 직접 60개로 바꿨는데, 영구 저장이 붙으면
  /// 가짜 기록이 그대로 남는다(Codex 15회차). 이제 화면에만 얹고
  /// 저장은 건드리지 않으며, 릴리스 빌드에는 버튼 자체가 없다.
  bool _demoFill = false;

  /// 바다 배경. 은박 색도 여기서 따라온다 — 배경이 밝아지면 은박이 함께
  /// 조정되지 않으면 미수집 지역이 배경에 묻힌다.
  SeaPalette get _sea => widget.sea;
  final _seaCache = SeaBackgroundCache();

  /// 애니메이션 틱 수. 프레임이 안 나올 때 "애니메이션이 멈춘 것"인지
  /// "그리다가 못 따라가는 것"인지 구분하려면 이 값이 필요하다.
  int _ticks = 0;

  RegionHitTester? _hitTester;
  Region? _selected;

  bool get _diagnostics => widget.showDiagnostics ?? !kReleaseMode;

  bool get _inset => widget.showInset ?? kShowMapInset;

  /// 진단이 켜져 있을 때만 프레임을 잰다.
  ///
  /// **`initState` 한 번으로 끝내지 않는다.** `showDiagnostics` 가 바뀌면 UI 는
  /// getter 라 따라오는데 수집은 안 따라와, 바가 나타났는데 계속 0 이거나
  /// 바가 사라졌는데 콜백이 남는다(Codex 25회차). 제품에는 바꾸는 경로가
  /// 없지만 테스트가 이미 그렇게 쓰고 있다.
  void _syncStats() {
    if (_diagnostics || _autoBench) {
      _stats.start();
    } else {
      _stats.stop();
    }
  }

  @override
  void didUpdateWidget(MapSpikePage old) {
    super.didUpdateWidget(old);
    if (old.showDiagnostics == widget.showDiagnostics) return;
    _syncStats();
    // **진단을 끄면 진단으로 만든 상태도 되돌린다.** 수집만 멈추면 수동
    // 벤치마크가 계속 돌고 데모 채움이 지도에 남아, seam 이 "릴리스 구성" 을
    // 온전히 재현하지 못한다(Codex 26회차).
    //
    // `_autoBench` 중에는 멈추지 않는다 — 성능 측정 하네스가 끊긴다.
    if (!_diagnostics && !_autoBench) {
      if (_benchmarking) _toggleBenchmark();
      _demoFill = false;
      _sidoLines = true;
    }
  }

  /// 인셋 판이 펼쳐져 있는가. **판이 스스로 알려 준다.**
  ///
  /// 가로 화면에서는 판이 좌우 배치라 폭이 약 390 이다. 검색줄이 화면 전체를
  /// 가로지르면 판이 그 아래로 밀려 세로 공간을 잃고 캔버스가 눌린다.
  /// 펼쳐져 있을 때만 검색줄을 왼쪽으로 물린다(Codex 28회차).
  bool _insetOpen = false;

  /// 하단 탭. 0 = 지도, 1 = 갤러리, 2 = 기록.
  ///
  /// **이 State 가 탭까지 소유한다.** 지도의 확대·이동(`_tc`)과 Picture 캐시
  /// (`_cache`·`_seaCache`), 저장소(`_store`)가 전부 여기 있어서, 탭을 앱
  /// 최상위로 올리고 지도를 조건부로 만들면 전환할 때마다 State 가 폐기돼
  /// **지도와 저장소를 다시 읽고 확대 위치가 초기화된다**(Codex 23회차).
  /// `IndexedStack` 으로 셋을 함께 살려 둔다.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // **화면에 안 보이면 재지도 않는다.** `_StatsBar` 만 감추면 타이밍 콜백은
    // 매 프레임 계속 돌아 릴리스에 쓰지 않는 일이 남는다(Codex 25회차).
    _syncStats();
    _bench = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addListener(_driveBenchmark);
    _load();
  }

  /// `--dart-define=AUTOBENCH=true` 로 실행하면 화면을 보지 않고
  /// 로그만으로 프레임 성능을 측정할 수 있다.
  static const bool _autoBench = bool.fromEnvironment('AUTOBENCH');

  /// 지도와 수집 기록을 **둘 다 읽은 뒤에야** 지도를 보여준다.
  ///
  /// 지도만 먼저 띄우면 ① 잠깐 전부 미수집으로 보이고 ② 그 사이 사용자가 새
  /// 지역을 완료할 수 있으며 ③ 늦게 도착한 로드가 그 결과를 덮어쓴다
  /// (Codex 15회차). 두 로드는 병렬로 돌리되 표시는 함께 연다.
  Future<void> _load() async {
    try {
      // **둘을 함께 시작하고 함께 기다린다.** 어느 쪽이 먼저 끝나도
      // 둘 다 결정되기 전에는 지도를 열지 않는다.
      final storeFuture = (widget.storeOpener ?? _openStore)();
      final mapFuture = (widget.mapLoader ?? MapData.load)();
      final d = await mapFuture;
      final (store, result) = await storeFuture;
      if (!mounted) return;
      setState(() {
        _data = d;
        _hitTester = RegionHitTester(d.regions);
        _searcher = RegionSearcher(d);
        _store = store;
        _loadResult = result;
        _scratched =
            result.snapshot.idsIn(d.regions.map((r) => r.scratchUnitId));
      });
      debugPrint('[BENCH] 로딩 ${d.loadMs}ms '
          '(읽기 ${d.readMs}ms · JSON ${d.decodeMs}ms · Path ${d.pathMs}ms) · '
          '지역 ${d.regions.length}개 · 정점 ${d.vertexCount}개');
      final unknown =
          result.snapshot.unknownIds(d.regions.map((r) => r.scratchUnitId));
      debugPrint('[STORE] ${result.status.name} · 수집 ${_scratched.length}개'
          '${unknown.isEmpty ? '' : ' · 알 수 없는 ID ${unknown.length}개(보존)'}'
          '${result.detail == null ? '' : ' · ${result.detail}'}');
      // **조용히 넘어가지 않는다.** 손상으로 빈 상태가 됐는데 알리지 않으면
      // 사용자는 기록이 사라진 것을 모른 채 새로 긁기 시작한다(Codex 16회차).
      if (result.status != CollectionLoadStatus.ok) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showStoreProblem(result));
      }
      if (_autoBench) _runAutoBench();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// 저장소 열기는 실패해도 **앱을 못 켜게 만들지 않는다.**
  /// 지도는 보여주되 쓸 수 없는 상태로 두고 사용자에게 알린다.
  Future<(CollectionStore, CollectionLoadResult)> _openStore() async {
    try {
      final storage = await FileCollectionStorage.open();
      final store = CollectionStore(storage);
      return (store, await store.load());
    } catch (e) {
      final store = CollectionStore(_UnavailableStorage());
      return (
        store,
        CollectionLoadResult(
            CollectionLoadStatus.readFailed, CollectionSnapshot.empty,
            detail: '$e')
      );
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

  /// 검색으로 고른 지역은 **탭한 것과 똑같이** 다룬다.
  ///
  /// 별도 경로를 만들지 않는다 — 검색은 접근 수단일 뿐이고, 그 뒤 흐름은
  /// 소개 팝업 → 긁기로 하나여야 한다.
  Future<void> _openSearch(MapData d) async {
    final searcher = _searcher;
    if (searcher == null) return;
    final picked = await showModalBottomSheet<Region>(
      context: context,
      isScrollControlled: true, // 키보드가 올라와도 결과가 가려지지 않게
      backgroundColor: AppThemeScope.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SearchSheet(searcher: searcher, scratched: _scratched),
    );
    if (picked == null || !mounted) return;
    setState(() => _selected = picked);
    await _openRegion(picked, d);
  }

  /// 지역 탭 → 소개 팝업 → "지역 긁기" → 전용 긁기 화면 → 완료 시 컬러 채움.
  Future<void> _openRegion(Region r, MapData d) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      // **기본값은 화면의 9/16 까지만 쓴다.** S25(360×780) 기준 약 439px 인데
      // 아트 150 + 헤더 + 설명 + 진행률 + 버튼을 더하면 그걸 넘는다.
      // 그대로 두면 스크롤은 되지만 **버튼이 처음부터 화면 밖**이다(Codex 20회차).
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppThemeScope.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _RegionSheet(
        region: r,
        sidoName: d.sidoNames[r.sido],
        // 수집 기록 원본에서 꺼낸다. 화면용 `Set` 에는 수집일시·메모가 없다.
        collected: _store?.snapshot[r.scratchUnitId],
        progress: sidoProgressOf(d, _scratched, r.sido),
        onSaveMemo: _saveMemo,
      ),
    );
    if (go != true || !mounted) return;

    // **쓸 수 없는 상태면 긁게 두지 않는다.** 긁고 나서 저장이 안 되면
    // 사용자가 한 일이 통째로 버려진다. 먼저 왜 안 되는지 알린다.
    final result = _loadResult;
    if (_store == null || result == null || !result.writable) {
      _showStoreProblem(result);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScratchPage(
          region: r,
          sidoName: d.sidoNames[r.sido],
          onCollected: _commitCollected,
        ),
      ),
    );
  }

  void _showStoreProblem(CollectionLoadResult? r) {
    if (!mounted) return;
    final msg = switch (r?.status) {
      CollectionLoadStatus.quarantined =>
        '저장된 수집 기록을 읽을 수 없어 빈 상태로 시작합니다.\n'
            '원본 파일은 지우지 않고 따로 보관했습니다.',
      CollectionLoadStatus.unsupportedVersion =>
        '더 새로운 버전이 만든 기록이 있습니다. 앱을 업데이트한 뒤 사용해 주세요.\n'
            '기존 기록을 지우지 않기 위해 저장을 멈춥니다.',
      _ => '수집 기록을 불러오지 못했습니다. 긁기를 시작할 수 없습니다.\n'
          '앱을 다시 실행해 보세요.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 8)),
    );
  }

  /// 긁기 화면이 **완료 도달 즉시** 부른다. 화면을 닫을 때가 아니다.
  ///
  /// 예전에는 `Navigator.pop(true)` 가 커밋 신호였는데, 그러면 완료 연출을 보고
  /// 버튼을 누르기 전까지가 통째로 손실 창이 된다 — 그 사이 앱이 죽으면
  /// "긁었는데 기록이 안 남는다" 가 된다(Codex 15회차).
  ///
  /// 저장에 실패하면 예외를 그대로 올려보내 긁기 화면이 재시도를 띄우게 한다.
  /// **성공해야 지도에 반영한다.**
  Future<void> _commitCollected(CollectedUnit unit) async {
    final store = _store;
    final d = _data;
    if (store == null || d == null) {
      throw StateError('저장소가 아직 준비되지 않았다');
    }
    // **메달은 긁기 전후를 비교해서 안다.** 저장하지 않으므로 그 두 값이
    // 같은 호출 안에 있어야 "새로 땄다" 를 알 수 있다(M7 에서 연출을 뺀 이유).
    final medals = MedalSet.of(d);
    final before = medals.achievedCount(_scratched.length);

    final next = await store.collect(unit);
    if (!mounted) return;
    setState(() {
      _scratched = next.idsIn(d.regions.map((r) => r.scratchUnitId));
    });
    debugPrint('[SCRATCH] 지도 반영 ${unit.scratchUnitId} · '
        '수집 ${_scratched.length}/${d.regions.length}');

    // **저장에 성공해야 축하한다.** 실패하면 위에서 예외가 올라가 긁기 화면이
    // 재시도를 띄우고 여기까지 오지 않는다.
    final after = medals.achievedCount(_scratched.length);
    if (after <= before) return;
    // 새로 열린 것 중 가장 높은 메달 하나만 축하한다. 임계치 간격이 넓어
    // 한 번에 둘이 열리는 일은 없지만, 생겨도 조용히 삼키지 않는다.
    final earned = medals.medals[after - 1];
    // **기다리지 않는다.** 긁기 화면은 `onCollected` 가 끝나야 "기록하는 중" 을
    // 지우고 이탈을 허용한다(M1). 여기서 팝업이 닫힐 때까지 기다리면 저장이
    // 이미 끝났는데도 저장 중으로 보이고 화면을 나갈 수 없다 — 실기기에서
    // 눈으로 보고 찾았다.
    unawaited(showMedalCelebration(
      context,
      medal: earned,
      collected: _scratched.length,
      total: d.regions.length,
    ));
  }

  /// 팝업이 메모를 저장할 때 부른다. **저장에 성공한 레코드**를 돌려준다.
  ///
  /// 실패는 그대로 올려보낸다 — 입력 화면이 오류를 보여 주고 내용을 붙잡고 있어야 한다.
  /// 메모는 지도 표시에 영향이 없으므로 `_scratched` 는 건드리지 않는다.
  Future<CollectedUnit> _saveMemo(String scratchUnitId, String? memo) async {
    final store = _store;
    if (store == null) throw StateError('저장소가 아직 준비되지 않았다');
    final next = await store.setMemo(scratchUnitId, memo);
    return next[scratchUnitId]!;
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
                : IndexedStack(
                    index: _tab,
                    children: [
                      _buildMapTab(d),
                      GalleryPage(
                        data: d,
                        // **원본 스냅샷을 매 build 마다 그대로 넘긴다.**
                        // 갤러리가 자기 State 에 복사하면 지도 탭에서 긁고
                        // 돌아왔을 때 stale 이 된다.
                        snapshot: _store?.snapshot ?? CollectionSnapshot.empty,
                        // **기존 팝업 경로를 그대로 탄다.** 저장 불가 상태에서
                        // 긁기 화면을 막는 게이트가 `_openRegion` 안에 있다.
                        onOpenRegion: (r) => _openRegion(r, d),
                      ),
                      // **파생 상태를 넘긴다.** 기록 탭은 수집일시·메모가
                      // 필요 없고, `_scratched` 는 이미 카탈로그와 교집합돼 있어
                      // 알 수 없는 ID 가 달성률에 섞이지 않는다.
                      RecordsPage(data: d, scratched: _scratched),
                    ],
                  ),
      ),
      bottomNavigationBar: (_error != null || d == null)
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: '지도',
                ),
                NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library),
                  label: '갤러리',
                ),
                NavigationDestination(
                  icon: Icon(Icons.emoji_events_outlined),
                  selectedIcon: Icon(Icons.emoji_events),
                  label: '기록',
                ),
              ],
            ),
    );
  }

  /// 지도 탭의 내용. 원래 `build` 안에 있던 것을 그대로 옮겼다.
  Widget _buildMapTab(MapData d) {
    return Column(
      children: [
                      Expanded(
                        // 인셋 판이 **지도 영역** 높이를 알아야 한다.
                        // 화면 높이로 자르면 아래에 고정된 판이 위로 밀려
                        // 머리글과 닫기 버튼이 화면 밖으로 나간다.
                        child: LayoutBuilder(
                          builder: (context, area) => Stack(
                            children: [
                              Positioned.fill(child: _buildMap(d)),
                            // 검색은 지도 위에 얹는다. 지도를 가리지 않게
                            // 상단에 얇게 두고, 누르면 시트가 열린다.
                            // **좌우 배치로 판을 펼치면 상단 검색·설정 줄을
                            // 감춘다.** 568px 폭에 그 줄과 390px 판을 함께 두면
                            // 39px 넘친다. 판에는 자체 지역 목록이 있고, 판을
                            // 닫으면 곧바로 돌아온다(Codex 28회차).
                            if (!(_inset && _insetOpen && shouldUseWideInset(area.biggest)))
                            Positioned(
                              left: 12,
                              right: 12,
                              top: 10,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _SearchBar(
                                        key: const Key('searchBar'),
                                        onTap: () => _openSearch(d)),
                                  ),
                                  if (widget.onOpenSettings != null) ...[
                                    const SizedBox(width: 8),
                                    _SettingsButton(
                                      onTap: () =>
                                          widget.onOpenSettings!(context),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // **인셋은 지도의 형제다.** `InteractiveViewer` 안에
                            // 넣으면 확대·이동을 따라가고, 지도 `GestureDetector`
                            // 안에 넣으면 같은 탭을 지도가 또 받는다.
                            // 여기 두면 확대와 무관하고 탭도 인셋이 먼저 먹는다
                            // (Codex 27회차).
                            if (_inset)
                            Positioned(
                              // **key 는 `Stack` 의 직접 자식에 준다.** 가로에서
                              // 판을 펼치면 검색줄이 트리에서 빠져 자식 순서가
                              // 바뀌는데, `Positioned` 에 key 가 없으면 순서로
                              // 짝을 맞추다 판의 State 가 폐기돼 펼침이 즉시
                              // 풀린다. 안쪽 위젯에 줘도 소용없다(Codex 28회차).
                              key: const ValueKey('insetPanelSlot'),
                              right: 12,
                              bottom: 12,
                              child: MapInsetPanel(
                                // 검색줄 자리를 빼고 남는 높이만 쓴다.
                                //
                                // **고정값으로 빼면 안 된다.** 검색줄은 큰
                                // 글꼴에서 커지는데 판 상단은 그대로라, 가로
                                // 화면 + 2.5배 글꼴에서 7px 겹쳤다
                                // (Codex 28회차 추측 → 테스트로 재현).
                                wide: shouldUseWideInset(area.biggest),
                                onOpenChanged: (v) =>
                                    setState(() => _insetOpen = v),
                                // 좌우 배치일 때는 검색줄과 비켜 서므로 세로를
                                // 거의 다 쓴다. 세로 배치일 때만 검색줄 자리를
                                // 뺀다 — 고정값으로 빼면 큰 글꼴에서 겹친다.
                                maxHeight: (shouldUseWideInset(area.biggest)
                                        ? area.maxHeight - 24
                                        : area.maxHeight -
                                            MediaQuery.textScalerOf(context)
                                                .scale(56) -
                                            20)
                                    // **하한을 두지 않는다.** 120 을 보장하면
                                    // 지도 영역이 그보다 짧을 때 판이 영역을
                                    // 넘어 위쪽이 잘린다 — debug 가로에서
                                    // 진단 UI 때문에 지도가 210px 로 눌리자
                                    // 실제로 그렇게 됐다. 남는 만큼만 쓰고
                                    // 모자라면 판 안에서 스크롤한다.
                                    .clamp(0.0, double.infinity),
                                data: d,
                                scratched: _scratched,
                                selected: _selected,
                                onOpenRegion: (r) {
                                  // 본지도와 선택을 맞춘다 — 인셋에서 고른 곳이
                                  // 지도에서도 외곽선으로 보여야 한다.
                                  setState(() => _selected = r);
                                  return _openRegion(r, d);
                                },
                              ),
                            ),
                          ],
                          ),
                        ),
                      ),
                      // **S1 스파이크 잔재라 릴리스에서는 내보내지 않는다.**
                      // 벤치마크·시도선·3배 확대·데모 채움은 최종 사용자 UI 가
                      // 아닌데 릴리스에도 나오고 있었다. 게다가 이 자리가
                      // 세로 공간을 크게 먹어, M6 하단 탭 도입 뒤 360×640 에서
                      // 지도 폭이 278.1 → 215.3 까지 줄었다(Codex 24회차).
                      if (_diagnostics) ...[
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
                        // **실제 기록을 건드리지 않는다.** 화면에만 얹는 표시이며
                        // 저장을 호출하지 않는다. 릴리스 빌드에는 버튼이 없다.
                        //
                        // `kDebugMode` 가 아니라 `!kReleaseMode` 인 이유는
                        // **성능 측정을 profile 에서 하기 때문**이다. `kDebugMode`
                        // 로 막았더니 정작 필요한 곳에서 버튼이 사라졌다.
                        onFillDemo: kReleaseMode
                            ? null
                            : () => setState(() => _demoFill = !_demoFill),
                      ),
                      ],
                    ],
    );
  }

  Widget _buildMap(MapData d) {
    return LayoutBuilder(
      builder: (context, c) {
        final aspect = d.size.height / d.size.width;
        var w = c.maxWidth;
        if (w * aspect > c.maxHeight) w = c.maxHeight / aspect;
        // 데모 채움은 **그릴 때만** 얹는다. `_scratched` 자체는 건드리지 않으므로
        // 저장에도, 팝업의 수집 여부 판정에도 섞이지 않는다.
        final painted = _demoFill
            ? {
                ..._scratched,
                ...d.regions.take(60).map((r) => r.scratchUnitId),
              }
            : _scratched;
        Widget map = CustomPaint(
          // 탭 전환이 지도 State 를 버리지 않는지 테스트가 이 key 로 확인한다.
          key: const Key('koreaMap'),
          painter: KoreaMapPainter(
            data: d,
            scratched: painted,
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
        final h = w * aspect;
        final viewport = Size(c.maxWidth, c.maxHeight);
        // 지도 위젯이 뷰포트 안에서 중앙에 놓이는 위치.
        final mapOrigin =
            Offset((viewport.width - w) / 2, (viewport.height - h) / 2);

        // **탭을 InteractiveViewer 바깥에서 받는다.**
        //
        // 배경 땅(북한)은 지도 위젯 밖(음수 y)에 그려지므로 `Clip.none` 이
        // 필요한데, 그러면 그 영역은 **자식 경계 밖이라 제스처를 받지 못한다.**
        // 안쪽에 두면 북한을 탭했을 때 `null` 이 아니라 아예 무시되어 이전
        // 선택이 남는다 (Codex 13회차 지적).
        //
        // 바깥에서 받고 `toScene` 으로 직접 변환하면 배경 영역 탭도 정상적으로
        // "바다(=선택 없음)" 로 판정된다.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // **`mapOrigin` 을 `toScene` 앞에서 뺀다.**
          //
          // `Center` 가 `InteractiveViewer` **밖**에 있으므로 변환은 지도 위젯
          // 좌표계에서 일어난다. 순서를 바꾸면(`toScene(x) - origin`) 확대율이
          // 1이 아닐 때 어긋난다 — `M⁻¹(s−o)` 와 `M⁻¹(s)−o` 는 다르다.
          // **`onTapDown` 이 아니라 `onTapUp` 이다.**
          //
          // 누르는 순간 팝업을 열면 지도를 끌려고 손을 댄 것까지 선택으로
          // 처리된다. `onTapUp` 은 제스처 판정이 "탭" 으로 끝났을 때만 오므로
          // 드래그·확대와 섞이지 않는다 (Codex 1회차 Medium #6, S1 이월).
          onTapUp: (e) =>
              _onTapMap(_tc.toScene(e.localPosition - mapOrigin), d, w),
          // 바다 바탕을 뷰포트에 정확히 채운다. painter 안에서 큰 사각형으로
          // 칠하면 범위가 매직 넘버가 되고 변환까지 따라 움직인다.
          child: ColoredBox(
            color: _sea.base,
            // 화면 밖으로 넘치는 배경까지 그려지지 않도록 여기서 한 번 자른다.
            child: ClipRect(
            // **지도 밖 빈 공간이 보이지 않게 이동·축소를 제한한다.**
            //
            // `boundaryMargin` 이 400 이면 사방 400px 까지 끌어낼 수 있어 지도가
            // 화면 밖으로 밀려나고 배경만 남는다. `minScale` 이 1 미만이면 축소
            // 했을 때 지도가 화면보다 작아져 같은 문제가 생긴다.
            //
            // **`Center` 는 `InteractiveViewer` 바깥이어야 한다.**
            //
            // 안쪽에 두면 자식이 뷰포트 크기가 되어, `boundaryMargin` 이 제한하는
            // 대상이 남한 지도가 아니라 **뷰포트 전체**가 된다. 그러면 크게 확대해
            // 끝까지 끌었을 때 지도가 화면 밖으로 나가고 바다만 남는다
            // (Codex 13회차 재검토 지적 — M13 을 M14 가 깨뜨렸다).
            child: Center(
              child: InteractiveViewer(
                transformationController: _tc,
                minScale: 1.0,
                maxScale: 16,
                boundaryMargin: EdgeInsets.zero,
                // 배경 땅은 지도 위젯 위쪽으로 벗어나 있다. 여기서 자르면 안 보인다.
                clipBehavior: Clip.none,
                child: SizedBox(width: w, height: h, child: map),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

/// 지역 소개 팝업.
///
/// **수집 전과 후가 다른 화면이다.**
/// - 수집 전: 아트를 은박으로 가리고 **랜드마크 이름도 설명도 내보내지 않는다.**
///   "가리고 긁을 때 공개" 결정의 핵심이라 이름 한 단어도 힌트가 된다
/// - 수집 후: 아트를 공개하고 설명·수집일·메모·시도 진행률을 함께 보여준다 —
///   상태 통보가 아니라 성취 표시로
///
/// 양쪽 모두 **시도 진행률**을 넣는다. 232번 반복되는 고정 문구만 두면
/// 수집 앱으로서 심심하고, 다음 목표도 보이지 않는다.
/// 메모 저장 콜백. 저장에 **성공한 레코드**를 돌려주고, 실패는 예외로 올린다.
typedef MemoSaver = Future<CollectedUnit> Function(
    String scratchUnitId, String? memo);

/// **Stateful 이어야 한다.** 메모를 저장한 뒤 팝업을 닫았다 열지 않고도
/// 그 자리에서 반영되어야 하기 때문이다(Codex 21회차).
class _RegionSheet extends StatefulWidget {
  const _RegionSheet({
    required this.region,
    required this.sidoName,
    required this.collected,
    required this.progress,
    required this.onSaveMemo,
  });

  final Region region;
  final String sidoName;

  /// 수집 기록. `null` 이면 아직 안 긁은 지역이다.
  final CollectedUnit? collected;

  final SidoProgress progress;
  final MemoSaver onSaveMemo;

  @override
  State<_RegionSheet> createState() => _RegionSheetState();
}

class _RegionSheetState extends State<_RegionSheet> {
  late CollectedUnit? collected = widget.collected;

  Region get region => widget.region;
  String get sidoName => widget.sidoName;
  SidoProgress get progress => widget.progress;

  bool get scratched => collected != null;

  Future<void> _editMemo() async {
    final unit = collected;
    if (unit == null) return;
    final saved = await showModalBottomSheet<CollectedUnit>(
      context: context,
      // **키보드 때문에 반드시 필요하다.** 없으면 시트가 화면의 9/16 까지만 쓸 수
      // 있어 키보드 높이만큼 밀어 올릴 자리가 없다. 짧은 화면만으로는 드러나지
      // 않는다 — 이 시트는 9/16 안에 들어간다.
      isScrollControlled: true,
      useSafeArea: true,
      // **저장 중에 닫히면 안 된다.** 저장은 됐는데 바깥 팝업이 결과를 못 받거나,
      // 실패했다면 입력과 오류가 함께 사라진다.
      //
      // 셋을 다 막아야 한다 — 배경 탭(`isDismissible`), 아래로 끌기(`enableDrag`),
      // 뒤로가기(시트 안 `PopScope`). **드래그는 `Navigator.pop` 을 직접 부르므로
      // `PopScope` 를 우회한다**(Codex 21회차. 테스트로 재현했다).
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppThemeScope.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _MemoSheet(
        regionName: region.name,
        initial: unit.memo,
        onSave: (memo) => widget.onSaveMemo(region.scratchUnitId, memo),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => collected = saved);
  }

  @override
  Widget build(BuildContext context) {
    final color = sidoColorOf(sidoName);
    final t = AppThemeScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        // **세로가 짧은 기기에서 넘치지 않게 스크롤을 준다.**
        // 800×600 테스트 화면에서 30px 넘치는 것을 M3 에서 발견했다.
        child: SingleChildScrollView(
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
            ..._body(t, color),
            const SizedBox(height: 18),
            if (scratched) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('regionMemoEdit'),
                  onPressed: _editMemo,
                  // 본문이 메모 칸을 숨기는 기준과 **같아야 한다.** `!= null` 만
                  // 보면 공백뿐인 메모에서 "고치기" 인데 보이는 메모가 없다
                  // (Codex 21회차). 밖에서 쓴 파일에 그런 값이 들어올 수 있다.
                  child: Text(
                    normalizeMemo(collected!.memo) == null
                        ? '메모 남기기'
                        : '메모 고치기',
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: scratched
                  ? TextButton(
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
      ),
    );
  }

  List<Widget> _body(AppTheme t, Color color) {
    final body = TextStyle(color: t.onSurfaceMuted, fontSize: 14, height: 1.5);
    final unit = collected;

    if (unit == null) {
      // **여기에 랜드마크 이름이나 설명을 넣지 않는다.**
      return [
        Text(
          '복권처럼 긁어서 이 지역을 수집해 보세요. '
          '무엇이 나올지는 긁어야 알 수 있어요.',
          style: body,
        ),
        const SizedBox(height: 14),
        _ProgressLine(progress: progress, color: color),
      ];
    }

    return [
      Text(descriptionFor(region.scratchUnitId), style: body),
      const SizedBox(height: 10),
      Text(
        '${_formatDate(unit.localDate)}에 수집했어요.',
        style: TextStyle(color: t.onSurfaceFaint, fontSize: 13),
      ),
      if (unit.memo != null && unit.memo!.trim().isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          key: const Key('regionMemo'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(unit.memo!, style: body),
        ),
      ],
      const SizedBox(height: 14),
      _ProgressLine(progress: progress, color: color),
    ];
  }

  /// 수집 **당시** 사용자의 날짜다. 지금 기기의 시간대로 다시 풀지 않는다.
  static String _formatDate(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';
}

/// 한 줄 메모 입력. 저장에 성공하면 갱신된 레코드를 `pop` 으로 돌려준다.
///
/// **선택 입력이고 짧은 한 줄이다.** 긁기 완료 직후에 묻지 않고 여기서만 받는다 —
/// 브리프가 메모를 제외했던 이유(입력 비용이 높으면 오래 못 쓴다)가 완료 흐름에
/// 돌아오지 않게 하기 위해서다(2026-08-16 사용자 결정).
class _MemoSheet extends StatefulWidget {
  const _MemoSheet({
    required this.regionName,
    required this.initial,
    required this.onSave,
  });

  final String regionName;
  final String? initial;

  /// 저장. 실패는 예외로 올라오며 **입력 내용을 버리지 않는다.**
  final Future<CollectedUnit> Function(String? memo) onSave;

  @override
  State<_MemoSheet> createState() => _MemoSheetState();
}

class _MemoSheetState extends State<_MemoSheet> {
  late final _text = TextEditingController(text: widget.initial ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(_text.text);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      // **SnackBar 를 쓰지 않는다.** 루트 `ScaffoldMessenger` 가 띄우면 모달 시트
      // 뒤나 아래에 깔려 보이지 않을 수 있다(Codex 21회차). 시트 안에 직접 보여 준다.
      setState(() {
        _saving = false;
        _error = e is MemoTooLongException
            ? '메모가 너무 깁니다. $kMemoMaxLength 자까지 쓸 수 있어요.'
            : '메모를 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return PopScope(
      // 저장 중에는 뒤로가기로 나갈 수 없다. 저장은 됐는데 결과를 못 받는 경로를 막는다.
      canPop: !_saving,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            // 키보드 높이만큼 밀어 올린다. 없으면 입력창이 키보드에 가린다.
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.regionName}에 한 줄 남기기',
                  style: TextStyle(
                    color: t.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '비워 두고 저장하면 메모가 지워집니다.',
                  style: TextStyle(color: t.onSurfaceFaint, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('memoField'),
                  controller: _text,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: kMemoMaxLength,
                  // 화면에서도 한 줄로 묶지만 **최종 방어선은 모델이다** —
                  // 붙여넣기와 IME 는 이 설정을 우회할 수 있다.
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: TextStyle(color: t.onSurface),
                  decoration: InputDecoration(
                    hintText: '그날 기억나는 것 하나',
                    hintStyle: TextStyle(color: t.onSurfaceGhost),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    key: const Key('memoError'),
                    style: TextStyle(color: t.bad, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const Key('memoSave'),
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '저장 중…' : '저장'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 시도 진행률 한 줄. 수집 전후 모두에 들어간다.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress, required this.color});

  final SidoProgress progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    // **통합 단위는 1/1 이라 "남은 곳" 이 늘 0 이다.** 분수만 보여주면
    // 이상해 보이므로 끝난 시도는 말로 알린다.
    final label = progress.complete
        ? '${progress.sidoName} 전부 모았어요!'
        : '${progress.sidoName} ${progress.collected}/${progress.total} · '
            '${progress.remaining}곳 남았어요';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress.ratio,
            minHeight: 6,
            backgroundColor: t.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(color: t.onSurfaceMuted, fontSize: 13)),
      ],
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
                // `Row` 로 두면 좁은 화면에서 넘친다. 수치 길이가 상황마다
                // 달라지므로 줄바꿈되게 둔다.
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${stats.measuredFps.toStringAsFixed(0)} fps',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: ok ? t.good : t.bad)),
                    Text('여유 ${stats.headroomFps.toStringAsFixed(0)}'),
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

/// 지도 위에 얹는 검색 진입점. 실제 입력은 시트에서 받는다.
///
/// 여기에 `TextField` 를 두지 않는 이유는 **키보드가 지도를 반쯤 덮기** 때문이다.
/// 시트로 열면 결과 목록과 키보드가 한 화면에 정리된다.
class _SearchBar extends StatelessWidget {
  const _SearchBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Material(
      color: t.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: t.onSurfaceMuted),
              const SizedBox(width: 10),
              Text('지역 검색',
                  style: TextStyle(color: t.onSurfaceFaint, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설정 진입. 검색줄 오른쪽에 붙는다.
///
/// **최소 48×48 을 지킨다.** 지도 위에 얹히는 작은 버튼이라 더 줄이면
/// 누르기 어렵다.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Material(
      color: t.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: const Key('openSettings'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Semantics(
            button: true,
            label: '설정',
            child: Icon(Icons.settings, size: 20, color: t.onSurfaceMuted),
          ),
        ),
      ),
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
  final VoidCallback onBenchmark, onSidoLines, onReset, onZoom3x;

  /// 릴리스 빌드에서는 `null` 이라 버튼 자체가 나오지 않는다.
  final VoidCallback? onFillDemo;

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
          if (onFillDemo != null)
            OutlinedButton(
                onPressed: onFillDemo, child: const Text('60칸 채우기')),
          // adb 로는 핀치 줌을 넣을 수 없어, 확대 상태의 좌표 변환을 검증하려면
          // 배율을 코드로 고정하는 수단이 필요하다.
          OutlinedButton(onPressed: onZoom3x, child: const Text('3배 확대')),
          OutlinedButton(onPressed: onReset, child: const Text('초기화')),
        ],
      ),
    );
  }
}
