import 'package:flutter/material.dart';

import 'app_info.dart';
import 'app_theme.dart';
import 'sea_background.dart';
import 'settings.dart';

/// M12 설정 화면.
///
/// **하단 시트가 아니라 전체 화면이다.** 출처 문구와 앱 정보가 길어 시트에 담으면
/// 스크롤만 길어진다(Codex 22회차).
///
/// 여기 없는 것 — 계정·로그인(S3), 데이터 초기화·백업(출시 후 결정),
/// 시스템 테마 연동, 사용자 색 조합.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.seaName,
    required this.onSeaChanged,
    this.seaLocked = false,
  });

  /// 화면을 열 때의 바다. 이후 선택은 이 화면이 들고 있는다.
  final String seaName;

  /// 고른 바다 이름을 넘긴다. 저장 실패는 호출부가 알린다.
  final ValueChanged<String> onSeaChanged;

  /// `--dart-define=SEA` 로 팔레트를 고정한 실행. 측정 중에 화면에서
  /// 바꿔 버리면 무엇을 쟀는지 알 수 없게 된다.
  final bool seaLocked;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// **Stateful 이어야 한다.** 이 화면은 `MaterialPageRoute` 안에 있어서
/// 최상위가 다시 빌드돼도 여기 넘어온 `seaName` 은 **열 때의 값 그대로다.**
/// Stateless 로 두면 색은 바뀌는데 **체크 표시가 옛 항목에 남는다**(Codex 22회차).
class _SettingsPageState extends State<SettingsPage> {
  late String _seaName = widget.seaName;

  bool get seaLocked => widget.seaLocked;
  String get seaName => _seaName;

  void _pick(String name) {
    setState(() => _seaName = name);
    widget.onSeaChanged(name);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: t.surface,
        foregroundColor: t.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _SectionTitle('바다 색'),
          Text(
            '바다를 고르면 앱 전체 밝기가 함께 바뀝니다.',
            style: TextStyle(color: t.onSurfaceFaint, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (seaLocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '측정용으로 바다가 고정된 실행이라 바꿀 수 없습니다.',
                key: const Key('seaLocked'),
                style: TextStyle(color: t.bad, fontSize: 13),
              ),
            ),
          for (final name in kSelectableSeaNames)
            _SeaOption(
              name: name,
              selected: name == _seaName,
              enabled: !seaLocked,
              onTap: () => _pick(name),
            ),
          const SizedBox(height: 28),

          _SectionTitle('지도 데이터 출처'),
          // **CC BY 4.0 의무다.** 지우면 라이선스 위반이라 출시할 수 없다.
          _Body(kMapAttributionBody),
          const SizedBox(height: 10),
          _Body(kMapAttributionChanges),
          const SizedBox(height: 10),
          const _Url('배포본', kMapDistributionUrl),
          const _Url('라이선스', kMapLicenseUrl),
          const _Url('원자료', kMapSourceUrl),
          const SizedBox(height: 28),

          _SectionTitle('앱 정보'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('방방긁긁', style: TextStyle(color: t.onSurface, fontSize: 15)),
              Text(appVersionLabel,
                  key: const Key('appVersion'),
                  style: TextStyle(color: t.onSurfaceFaint, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('openSourceLicenses'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: '방방긁긁',
                applicationVersion: appVersionLabel,
              ),
              child: const Text('오픈소스 라이선스'),
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: t.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Text(text,
        style: TextStyle(color: t.onSurfaceMuted, fontSize: 13, height: 1.6));
  }
}

/// URL 은 **고를 수 있게** 둔다. `url_launcher` 없이도 복사해서 열 수 있다.
class _Url extends StatelessWidget {
  const _Url(this.label, this.url);
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: t.onSurfaceFaint, fontSize: 12)),
          SelectableText(
            url,
            style: TextStyle(color: t.onSurfaceMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 바다 후보 하나.
///
/// **색만으로 구분하지 않는다.** 이름과 체크 표시를 함께 둬야 색을 구분하기
/// 어려운 사용자도 고를 수 있다(Codex 22회차).
class _SeaOption extends StatelessWidget {
  const _SeaOption({
    required this.name,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  static const _labels = {
    'cerulean': ('맑은 바다', '한낮의 푸른 바다. 밝은 화면'),
    'sunset': ('노을 바다', '해 질 무렵의 주황빛. 밝은 화면'),
    'deep': ('깊은 바다', '밤바다의 짙은 남색. 어두운 화면'),
  };

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    final palette = seaPaletteByName(name);
    final (title, desc) = _labels[name] ?? (name, '');

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? t.surfaceVariant : t.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: Key('sea_$name'),
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.base,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: t.onSurfaceGhost),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: t.onSurface,
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        Text(desc,
                            style: TextStyle(
                                color: t.onSurfaceFaint, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check, color: t.onSurface, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
