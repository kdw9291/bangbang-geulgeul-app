import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 프레임 타이밍을 모아 60fps 기준으로 판정한다.
///
/// `FrameTiming.rasterDuration` 은 GPU 제출까지의 시간이고
/// `buildDuration` 은 위젯 빌드 + 레이아웃 시간이다.
/// 지도 렌더는 래스터 쪽이 병목이므로 둘을 나눠서 본다.
class FrameStats extends ChangeNotifier {
  FrameStats({this.window = 120});

  final int window;
  final Queue<FrameTiming> _q = Queue();
  bool _listening = false;

  static const double budgetMs = 1000 / 60; // 16.67ms

  void start() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _q.add(t);
      if (_q.length > window) _q.removeFirst();
    }
    notifyListeners();
  }

  void reset() {
    _q.clear();
    notifyListeners();
  }

  int get frames => _q.length;

  double _avg(double Function(FrameTiming) f) =>
      _q.isEmpty ? 0 : _q.map(f).reduce((a, b) => a + b) / _q.length;

  double get avgBuildMs => _avg((t) => t.buildDuration.inMicroseconds / 1000);
  double get avgRasterMs => _avg((t) => t.rasterDuration.inMicroseconds / 1000);

  double get worstTotalMs => _q.isEmpty
      ? 0
      : _q
          .map((t) => t.totalSpan.inMicroseconds / 1000)
          .reduce((a, b) => a > b ? a : b);

  /// 16.67ms 예산을 넘긴 프레임 비율.
  double get jankRatio {
    if (_q.isEmpty) return 0;
    final over = _q
        .where((t) => t.totalSpan.inMicroseconds / 1000 > budgetMs)
        .length;
    return over / _q.length;
  }

  double get estimatedFps {
    final avg = _avg((t) => t.totalSpan.inMicroseconds / 1000);
    if (avg <= 0) return 0;
    return (1000 / avg).clamp(0, 120);
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
