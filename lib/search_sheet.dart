import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'map_data.dart';
import 'region_search.dart';

/// 지역 검색 하단 시트. 고른 지역을 `Navigator.pop` 으로 돌려준다.
///
/// 검색은 **접근**을 푼다 — 이름을 아는 곳으로 바로 간다. 고르고 나면 지도의
/// 기존 흐름(소개 팝업 → 긁기)에 그대로 얹힌다. 별도 경로를 만들지 않는다.
class SearchSheet extends StatefulWidget {
  const SearchSheet({
    super.key,
    required this.searcher,
    required this.scratched,
  });

  final RegionSearcher searcher;

  /// 이미 수집한 긁기 단위. 결과에 표시만 하고 순서는 바꾸지 않는다.
  final Set<String> scratched;

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<RegionSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    // 시트가 열리면 바로 칠 수 있어야 한다. 한 번 더 두드리게 만들지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) =>
      setState(() => _results = widget.searcher.search(q));

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context);
    // 키보드가 올라오면 그만큼 밀어 올린다. 안 그러면 결과가 가려진다.
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: t.onSurfaceGhost,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: t.onSurface),
                decoration: InputDecoration(
                  hintText: '지역 이름 또는 초성 (예: 순천, ㅅㅊ)',
                  hintStyle: TextStyle(color: t.onSurfaceFaint),
                  prefixIcon: Icon(Icons.search, color: t.onSurfaceMuted),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear, color: t.onSurfaceMuted),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: t.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppTheme t) {
    if (_controller.text.trim().isEmpty) {
      return _hint(t, '가고 싶은 지역 이름을 쳐 보세요.\n초성만 쳐도 찾아줍니다.');
    }
    if (_results.isEmpty) {
      // **왜 없는지까지 말한다.** 자모가 떨어져 있으면 무엇을 쳐도 0건이라,
      // "없습니다" 만으로는 사용자가 빠져나올 방법을 알 수 없다.
      return _hint(
        t,
        hasLooseJamo(_controller.text)
            ? '자음과 모음이 떨어져 있어요.\n지우고 다시 쳐 보세요.'
            : '찾는 지역이 없습니다.',
      );
    }
    // **개수를 항상 보여준다.** 예전에는 30개에서 조용히 끊어서, 찾는 곳이
    // 없는 것인지 잘린 것인지 알 수 없었다.
    final crowded = _results.length > RegionSearcher.crowded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text('${_results.length}곳',
                  style: TextStyle(color: t.onSurfaceMuted, fontSize: 13)),
              if (crowded) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '· 시도 이름을 함께 쳐 보세요 (예: 부산 중구)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.onSurfaceFaint, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, i) => _row(t, _results[i]),
          ),
        ),
      ],
    );
  }

  Widget _hint(AppTheme t, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.onSurfaceFaint, fontSize: 14),
          ),
        ),
      );

  Widget _row(AppTheme t, RegionSearchResult r) {
    final collected = widget.scratched.contains(r.region.scratchUnitId);
    final color = sidoColorOf(r.sidoName);

    // **이름이 겹치면 시도명을 반드시 보여준다.** `중구` 만으로는 여섯 곳 중
    // 어디인지 알 수 없다. 겹치지 않아도 시도명은 참고로 함께 둔다.
    final sameName = r.sidoName == r.region.name;

    return ListTile(
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              r.region.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.onSurface,
                fontWeight:
                    r.ambiguousName ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (!sameName) ...[
            const SizedBox(width: 8),
            Text(
              r.sidoName,
              style: TextStyle(color: t.onSurfaceFaint, fontSize: 12),
            ),
          ],
        ],
      ),
      trailing: collected
          ? Icon(Icons.check_circle, size: 18, color: color)
          : null,
      onTap: () => Navigator.of(context).pop(r.region),
    );
  }
}
