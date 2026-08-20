import 'package:flutter/material.dart';

import 'achievement.dart';
import 'app_theme.dart';

/// 메달을 새로 딴 순간의 축하 팝업.
///
/// ## 잠정이다 (2026-08-19 사용자)
///
/// **문구·메달 이미지·메달 이름·애니메이션 효과가 모두 바뀔 수 있다.** 지금은
/// "연출이 있으면 좋겠다" 는 요구를 채우는 최소 형태다. 아이콘은 Material
/// 기본이고 문구도 임시다. 바꾸기 쉽게 이 파일 하나에 모아 두었다 —
/// 호출부는 어떤 메달을 땄는지만 넘긴다.
///
/// ## 저장 스키마를 바꾸지 않는다
///
/// M7 에서 연출을 뺀 이유는 **"새로 땄다" 를 알려면 직전 상태를 기억해야 하기
/// 때문**이었다. 메달은 수집 수에서 매번 계산할 뿐이라, 앱을 껐다 켜면 20곳은
/// 그냥 20곳이고 방금 넘었는지 어제 넘었는지 알 수 없다.
///
/// **긁기 완료 직후에만 보여 주기로 정하면 그 문제가 사라진다**(2026-08-19
/// 사용자 결정). 긁기 전후의 메달 수를 비교하면 되고, 그 두 값은 같은 호출
/// 안에 있다. 저장할 것이 없다.
///
/// ## 저장에 성공해야 축하한다
///
/// `_commitCollected` 는 저장에 실패하면 예외를 올려 긁기 화면이 재시도를
/// 띄운다. 그 경우 수집이 성립하지 않았으므로 축하도 하지 않는다.
Future<void> showMedalCelebration(
  BuildContext context, {
  required Medal medal,
  required int collected,
  required int total,
}) {
  final t = AppThemeScope.of(context);
  return showDialog<void>(
    context: context,
    // 배경을 눌러 닫을 수 있다. 축하는 막아설 일이 아니다.
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      key: const Key('medalCelebration'),
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // `Dialog` 가 이미 자식을 화면 크기로 묶는다. 따로 `ConstrainedBox` 를
      // 두어 봤지만 없어도 같아서 뺐다 — 지탱하는 것은 아래 `Flexible` 이다.
      child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // **버튼은 고정하고 내용만 줄인다.** 뒤에 두면 짧은 화면에서
              // 스크롤 아래로 밀려 닫을 수가 없다.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 등장할 때 살짝 커지며 나타난다. 긁기 완료 연출(600ms)과
                      // 결이 맞게 짧게 끝낸다 — 최대 다섯 번 보는 연출이라
                      // 길면 거슬린다.
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.6, end: 1),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutBack,
                        builder: (_, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: Icon(
                          medal.nationwide
                              ? Icons.emoji_events
                              : Icons.workspace_premium,
                          size: 64,
                          color: t.good,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        medal.nationwide
                            ? '전국을 다 모았어요!'
                            : '${medal.label} 메달을 땄어요',
                        key: const Key('medalCelebrationTitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.onSurface,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$collected/$total곳',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: t.onSurfaceMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const Key('medalCelebrationClose'),
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    // 최소 탭 영역.
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('좋아요'),
                ),
              ),
            ],
        ),
      ),
    ),
  );
}
