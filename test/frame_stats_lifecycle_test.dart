import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/frame_stats.dart';

/// 진단을 끄면 **집계도 멈춰야 한다.**
///
/// `_StatsBar` 만 감추면 타이밍 콜백이 매 프레임 계속 돌아, 릴리스에 쓰지 않는
/// S1 진단 작업이 남는다(Codex 25회차). `MapSpikePage` 는 `_syncStats()` 로
/// 이 둘을 함께 움직인다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 실제로 프레임 하나를 흘려 넣는다.
  ///
  /// **`listening` 플래그만 보면 안 된다.** `removeTimingsCallback` 을 빼먹고
  /// 플래그만 내려도 통과한다 — 처음 쓴 테스트가 정확히 그랬다. 위젯 테스트에서
  /// 타이밍 콜백은 저절로 돌지 않으므로 바인딩이 등록한 핸들러를 직접 부른다.
  void emitFrame() {
    SchedulerBinding.instance.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 1000,
        buildFinish: 3000,
        rasterStart: 3000,
        rasterFinish: 5000,
        rasterFinishWallTime: 5000,
      ),
    ]);
  }

  test('start 뒤에는 프레임이 쌓이고 stop 뒤에는 멈춘다', () {
    final s = FrameStats();
    addTearDown(s.dispose);

    expect(s.listening, isFalse);
    emitFrame();
    expect(s.frames, 0, reason: '시작도 안 했는데 쌓였다');

    s.start();
    expect(s.listening, isTrue);
    emitFrame();
    expect(s.frames, 1);

    s.stop();
    expect(s.listening, isFalse);
    emitFrame();
    expect(s.frames, 1, reason: '멈췄는데 콜백이 남아 계속 쌓인다');
  });

  test('여러 번 불러도 안전하고 다시 켜진다', () {
    final s = FrameStats();
    addTearDown(s.dispose);

    s.start();
    s.start();
    emitFrame();
    expect(s.frames, 1, reason: '두 번 등록돼 한 프레임이 두 번 세어졌다');

    s.stop();
    s.stop();
    emitFrame();
    expect(s.frames, 1);

    s.start();
    emitFrame();
    expect(s.frames, 2, reason: '멈춘 뒤 다시 켜지지 않는다');
  });
}
