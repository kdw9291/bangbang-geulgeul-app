import 'package:flutter/material.dart';

import 'achievement.dart';
import 'app_theme.dart';
import 'map_data.dart';
import 'sido_progress.dart';

/// M7 기록 탭. 전체 달성률 · 메달 · 시도 16개를 한 화면에 둔다.
///
/// ## 모집단은 현재 카탈로그다
///
/// [CollectionSummary] 가 `data.regions` 를 훑어 만든 값만 쓴다.
/// `CollectionSnapshot.length` 를 쓰면 **알 수 없는 ID 까지 세어 233/232** 가
/// 된다(M1 계약 — 저장은 보존하되 표시·달성률에서 제외).
///
/// ## 16행뿐이라 지연 생성을 쓰지 않는다
///
/// `SliverList` 로 만들면 보이는 줄만 생겨 **테스트가 한 화면만 보고 통과**한다 —
/// M6 갤러리에서 겪었다. 여기서는 16개를 전부 마운트한다.
class RecordsPage extends StatelessWidget {
  const RecordsPage({
    super.key,
    required this.data,
    required this.scratched,
  });

  final MapData data;

  /// **이미 카탈로그와 교집합된 파생 상태다.** 원본 스냅샷이 아니다.
  final Set<String> scratched;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    final summary = collectionSummaryOf(data, scratched);
    final medals = MedalSet.of(data);

    return SingleChildScrollView(
      key: const Key('recordsScroll'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Overall(summary: summary, medals: medals),
          const SizedBox(height: 22),
          _SectionTitle('메달'),
          const SizedBox(height: 10),
          _Medals(medals: medals, collected: summary.collected),
          const SizedBox(height: 24),
          _SectionTitle('시도'),
          const SizedBox(height: 4),
          Text(
            '${summary.sidos.where((s) => s.complete).length}/'
            '${summary.sidos.length}곳 완성',
            style: TextStyle(color: t.onSurfaceMuted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          for (final s in summary.sidos) _SidoRow(progress: s),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Text(text,
        style: TextStyle(
          color: t.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ));
  }
}

class _Overall extends StatelessWidget {
  const _Overall({required this.summary, required this.medals});

  final CollectionSummary summary;
  final MedalSet medals;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    final next = medals.nextAfter(summary.collected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // **`Row` 를 쓰지 않는다.** 큰 글꼴에서 제목과 숫자가 한 줄에 안 들어가
        // 오른쪽으로 넘친다 — M6 헤더에서 정확히 그렇게 깨졌다.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 2,
          children: [
            Text('전국',
                style: TextStyle(
                  color: t.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                )),
            Text('${summary.collected}/${summary.total}',
                key: const Key('overallProgress'),
                style: TextStyle(
                  color: t.onSurfaceMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
        const SizedBox(height: 8),
        _Bar(ratio: summary.ratio),
        const SizedBox(height: 8),
        Text(
          // 완주 후 "0곳 남았어요" 가 나오지 않게 `next` 가 `null` 이다.
          next == null
              ? '전국을 다 모았어요!'
              : '${next.label} 메달까지 ${next.threshold - summary.collected}곳 남았어요',
          key: const Key('nextMedal'),
          style: TextStyle(color: t.onSurfaceMuted, fontSize: 13),
        ),
      ],
    );
  }
}

class _Medals extends StatelessWidget {
  const _Medals({required this.medals, required this.collected});

  final MedalSet medals;
  final int collected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in medals.medals)
          _MedalChip(medal: m, got: medals.achieved(m, collected)),
      ],
    );
  }
}

class _MedalChip extends StatelessWidget {
  const _MedalChip({required this.medal, required this.got});

  final Medal medal;
  final bool got;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Semantics(
      label: '${medal.label} 메달 ${got ? '획득' : '미획득'}',
      excludeSemantics: true,
      child: Container(
        key: Key('medal:${medal.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: got ? t.surfaceVariant : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: got ? t.good : t.onSurfaceGhost,
            width: got ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              got ? Icons.workspace_premium : Icons.lock_outline,
              color: got ? t.good : t.onSurfaceFaint,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(medal.label,
                style: TextStyle(
                  color: got ? t.onSurface : t.onSurfaceFaint,
                  fontSize: 13,
                  fontWeight: got ? FontWeight.bold : FontWeight.normal,
                )),
            // **색과 테두리만으로 상태를 말하지 않는다.** 글자로도 적는다.
            Text(got ? '획득' : '미획득',
                style: TextStyle(
                  color: got ? t.good : t.onSurfaceFaint,
                  fontSize: 11,
                )),
          ],
        ),
      ),
    );
  }
}

class _SidoRow extends StatelessWidget {
  const _SidoRow({required this.progress});

  final SidoProgress progress;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Semantics(
      // 분모를 넣는다. "완료" 만 읽으면 몇 곳짜리인지 알 수 없다.
      label: '${progress.sidoName}, ${progress.total}곳 중 '
          '${progress.collected}곳${progress.complete ? ', 완료' : ''}',
      excludeSemantics: true,
      child: Padding(
        key: Key('sido:${progress.sidoName}'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(progress.sidoName,
                    style: TextStyle(
                      color: t.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
                // **완료 표기는 1/1 시도만의 것이 아니다.** 서울·세종·제주가
                // 1/1 이라 유독 쉬워 보이지만, 경기 47/47 도 같은 완료다.
                // 완주한 시도는 전부 같은 표기를 쓴다(Codex 25회차).
                if (progress.complete)
                  Text('완료',
                      style: TextStyle(
                        color: t.good,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ))
                else
                  Text('${progress.collected}/${progress.total}',
                      style:
                          TextStyle(color: t.onSurfaceMuted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            _Bar(ratio: progress.ratio),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: t.surfaceVariant,
        valueColor: AlwaysStoppedAnimation(t.good),
      ),
    );
  }
}
