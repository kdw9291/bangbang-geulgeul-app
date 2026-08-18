import 'dart:collection';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 프레임 타이밍을 모아 60fps 기준으로 판정한다.
///
/// `FrameTiming.buildDuration` 은 위젯 빌드 + 레이아웃 시간이고
/// `rasterDuration` 은 GPU 제출까지의 시간이다. 지도 렌더는 래스터가 병목이므로
/// 둘을 나눠서 본다.
///
/// **fps 는 두 가지를 구분해서 낸다.**
/// - [measuredFps] 는 vsync 타임스탬프 간격으로 잰 **실제 프레임 생성 속도**다.
/// - [headroomFps] 는 프레임 하나를 처리하는 데 쓴 시간의 역수, 즉 **처리 여유**다.
///
/// 초기 구현은 후자만 계산하면서 fps 라고 표시했다. 그래서 4초에 4프레임만
/// 나온 구간이 "23fps" 로 보고됐다 — 프레임이 거의 안 나와도 각 프레임의 처리가
/// 빠르면 높은 값이 나오기 때문이다. 성능 판정에는 [measuredFps] 를 쓴다.
///
/// 누적 통계와 최근 구간 통계도 분리한다. 링 버퍼 하나만 쓰면 고주사율 기기에서
/// 측정 구간의 마지막 일부만 남아 전체 jank 비율을 대표하지 못한다.
class FrameStats extends ChangeNotifier {
  FrameStats({
    this.recentWindow = 60,
    this.notifyInterval = const Duration(milliseconds: 250),
  });

  /// UI 표시용 최근 프레임 개수. 누적 통계와 무관하다.
  final int recentWindow;

  /// 알림 최소 간격. 매 프레임 알리면 통계 UI 리빌드가 다시 프레임을 만들어
  /// 측정 대상에 부하를 얹는다.
  final Duration notifyInterval;

  static const double budgetMs = 1000 / 60; // 16.67ms

  final Queue<FrameTiming> _recent = Queue();
  bool _listening = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  // 측정 구간 전체 누적
  int _count = 0;
  int _over = 0;
  double _sumBuildMs = 0;
  double _sumRasterMs = 0;
  double _sumTotalMs = 0;
  double _worstTotalMs = 0;
  int? _firstVsyncUs;
  int? _lastVsyncUs;

  void start() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// 지금 프레임 타이밍을 받고 있는가. 진단을 껐는데 콜백이 남아 있는지를
  /// 테스트가 이걸로 본다.
  @visibleForTesting
  bool get listening => _listening;

  /// 수집을 멈춘다. 진단을 끄면 콜백을 떼야 한다 — UI 만 감추면
  /// 쓰지 않는 집계가 매 프레임 계속 돈다(Codex 25회차).
  void stop() {
    if (!_listening) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _listening = false;
  }

  @visibleForTesting
  void ingest(List<FrameTiming> timings) => _onTimings(timings);

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _recent.add(t);
      if (_recent.length > recentWindow) _recent.removeFirst();

      final total = t.totalSpan.inMicroseconds / 1000;
      _count++;
      _sumBuildMs += t.buildDuration.inMicroseconds / 1000;
      _sumRasterMs += t.rasterDuration.inMicroseconds / 1000;
      _sumTotalMs += total;
      if (total > budgetMs) _over++;
      if (total > _worstTotalMs) _worstTotalMs = total;

      final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
      _firstVsyncUs ??= vsync;
      _lastVsyncUs = vsync;
    }

    final now = DateTime.now();
    if (now.difference(_lastNotify) >= notifyInterval) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void reset() {
    _recent.clear();
    _count = 0;
    _over = 0;
    _sumBuildMs = 0;
    _sumRasterMs = 0;
    _sumTotalMs = 0;
    _worstTotalMs = 0;
    _firstVsyncUs = null;
    _lastVsyncUs = null;
    notifyListeners();
  }

  /// 측정 구간 전체의 프레임 수.
  int get frames => _count;

  /// 측정 구간의 실제 경과 시간(초). vsync 타임스탬프 기준.
  double get elapsedSeconds {
    if (_firstVsyncUs == null || _lastVsyncUs == null) return 0;
    final us = _lastVsyncUs! - _firstVsyncUs!;
    return us <= 0 ? 0 : us / 1e6;
  }

  /// **실제 프레임 생성 속도.** 연속한 vsync 사이 간격으로 계산한다.
  /// 프레임이 안 나오면 그만큼 낮게 나온다 — 이것이 성능 판정 기준이다.
  double get measuredFps {
    if (_count < 2) return 0;
    final s = elapsedSeconds;
    return s <= 0 ? 0 : (_count - 1) / s;
  }

  /// **처리 여유.** 프레임 하나를 처리하는 데 쓴 평균 시간의 역수다.
  /// 프레임 속도가 아니므로 성능 판정에 단독으로 쓰지 않는다.
  double get headroomFps {
    final avg = avgTotalMs;
    return avg <= 0 ? 0 : 1000 / avg;
  }

  double get avgBuildMs => _count == 0 ? 0 : _sumBuildMs / _count;
  double get avgRasterMs => _count == 0 ? 0 : _sumRasterMs / _count;
  double get avgTotalMs => _count == 0 ? 0 : _sumTotalMs / _count;
  double get worstTotalMs => _worstTotalMs;

  /// 16.67ms 예산을 넘긴 프레임 비율. **측정 구간 전체** 기준이다.
  double get jankRatio => _count == 0 ? 0 : _over / _count;

  /// UI 표시용 최근 구간 평균 래스터 시간.
  double get recentAvgRasterMs {
    if (_recent.isEmpty) return 0;
    var sum = 0.0;
    for (final t in _recent) {
      sum += t.rasterDuration.inMicroseconds / 1000;
    }
    return sum / _recent.length;
  }

  @override
  void dispose() {
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
    super.dispose();
  }
}
