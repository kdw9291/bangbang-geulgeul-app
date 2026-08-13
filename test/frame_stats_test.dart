import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/frame_stats.dart';

/// vsync 시각과 처리 시간을 따로 지정해 가짜 프레임을 만든다.
/// 실제 프레임 속도와 처리 여유가 서로 독립임을 시험하기 위한 것.
FrameTiming frame({
  required int vsyncUs,
  required int buildUs,
  required int rasterUs,
}) {
  final buildStart = vsyncUs;
  final buildFinish = buildStart + buildUs;
  final rasterStart = buildFinish;
  final rasterFinish = rasterStart + rasterUs;
  return FrameTiming(
    vsyncStart: vsyncUs,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('실제 fps 는 vsync 간격으로 계산한다', () {
    final s = FrameStats();
    // 8.33ms 간격 = 120fps, 프레임당 처리 2ms
    for (var i = 0; i < 121; i++) {
      s.ingest([frame(vsyncUs: i * 8333, buildUs: 1000, rasterUs: 1000)]);
    }
    expect(s.frames, 121);
    expect(s.measuredFps, closeTo(120, 1));
    s.dispose();
  });

  // 초기 구현이 틀렸던 지점. 프레임이 거의 안 나와도 처리가 빠르면
  // 높은 fps 로 보고됐다.
  test('프레임이 드물면 처리가 빨라도 fps 가 낮게 나온다', () {
    final s = FrameStats();
    // 1초 간격으로 4프레임, 각각 처리 2ms
    for (var i = 0; i < 4; i++) {
      s.ingest([frame(vsyncUs: i * 1000000, buildUs: 1000, rasterUs: 1000)]);
    }
    expect(s.measuredFps, closeTo(1.0, 0.01), reason: '초당 1프레임이어야 한다');
    expect(s.headroomFps, greaterThan(100), reason: '처리 여유는 여전히 크다');
    s.dispose();
  });

  test('누적 통계가 최근 구간 크기에 잘리지 않는다', () {
    final s = FrameStats(recentWindow: 10);
    // 앞쪽 20프레임만 예산 초과(20ms), 뒤쪽 80프레임은 정상(2ms)
    for (var i = 0; i < 20; i++) {
      s.ingest([frame(vsyncUs: i * 8333, buildUs: 1000, rasterUs: 19000)]);
    }
    for (var i = 20; i < 100; i++) {
      s.ingest([frame(vsyncUs: i * 8333, buildUs: 1000, rasterUs: 1000)]);
    }
    expect(s.frames, 100);
    // 링 버퍼(10개)만 봤다면 0% 가 나왔을 것이다
    expect(s.jankRatio, closeTo(0.20, 0.001));
    expect(s.worstTotalMs, greaterThan(19));
    s.dispose();
  });

  test('reset 은 누적과 최근 구간을 모두 비운다', () {
    final s = FrameStats();
    for (var i = 0; i < 10; i++) {
      s.ingest([frame(vsyncUs: i * 8333, buildUs: 1000, rasterUs: 30000)]);
    }
    expect(s.frames, 10);
    expect(s.jankRatio, greaterThan(0));

    s.reset();
    expect(s.frames, 0);
    expect(s.jankRatio, 0);
    expect(s.worstTotalMs, 0);
    expect(s.measuredFps, 0);
    expect(s.elapsedSeconds, 0);
    s.dispose();
  });

  test('프레임이 1개 이하면 fps 는 0 이다', () {
    final s = FrameStats();
    expect(s.measuredFps, 0);
    s.ingest([frame(vsyncUs: 0, buildUs: 1000, rasterUs: 1000)]);
    expect(s.measuredFps, 0, reason: '간격을 잴 수 없으므로 0');
    s.dispose();
  });

  test('알림은 지정 간격보다 자주 발생하지 않는다', () async {
    final s = FrameStats(notifyInterval: const Duration(milliseconds: 200));
    var notifications = 0;
    s.addListener(() => notifications++);

    // 프레임 30개를 즉시 밀어 넣는다
    for (var i = 0; i < 30; i++) {
      s.ingest([frame(vsyncUs: i * 8333, buildUs: 1000, rasterUs: 1000)]);
    }
    // 매 프레임 알렸다면 30회였을 것이다
    expect(notifications, lessThanOrEqualTo(2),
        reason: '알림이 throttle 되어야 측정 대상에 부하를 얹지 않는다');
    s.dispose();
  });

  test('예산 초과 판정은 16.67ms 기준이다', () {
    final s = FrameStats();
    s.ingest([frame(vsyncUs: 0, buildUs: 1000, rasterUs: 15000)]); // 16ms
    expect(s.jankRatio, 0);
    s.ingest([frame(vsyncUs: 8333, buildUs: 1000, rasterUs: 17000)]); // 18ms
    expect(s.jankRatio, closeTo(0.5, 0.001));
    s.dispose();
  });
}
