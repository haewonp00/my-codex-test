import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/guides.dart';
import '../data/items.dart';
import 'item_picker.dart';

class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.selection, this.onSelectionChanged});
  final ItemSelection selection;
  final ValueChanged<ItemSelection>? onSelectionChanged;
  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  late ItemSelection _selection;
  @override
  void initState() {
    super.initState();
    _selection = widget.selection;
  }

  Future<void> _change() async {
    final selected = await showItemPicker(context, initialSelection: _selection,
      title: '안내 품목 변경');
    if (!mounted || selected == null) {
      return;
    }
    widget.onSelectionChanged?.call(selected);
    setState(() => _selection = selected);
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _message('원문을 열지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } catch (_) {
      _message('원문을 열지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  Widget _guideImage(DisposalGuide guide, {required Key key}) {
    final asset = guide.assetImagePath;
    Widget unavailable() => const Padding(padding: EdgeInsets.all(20),
      child: Text('안내 이미지를 불러오지 못했습니다. 앱을 다시 실행해 주세요.'));
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(asset, key: key, fit: BoxFit.contain,
        semanticLabel: guide.documentTitle,
        errorBuilder: (_, error, stack) => unavailable());
    }
    final uri = officialWebUri(guide.officialImageUrl);
    if (uri != null) {
      return Image.network(uri.toString(), key: key, fit: BoxFit.contain,
        semanticLabel: guide.documentTitle,
        errorBuilder: (_, error, stack) => unavailable());
    }
    return unavailable();
  }

  void _expandImage(DisposalGuide guide) {
    showDialog<void>(context: context, builder: (context) => Dialog(
      key: const ValueKey('guide-image-dialog'),
      child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.8,
        width: double.maxFinite,
        child: Column(children: [
          Expanded(child: InteractiveViewer(minScale: 0.5, maxScale: 6,
            child: _guideImage(guide, key: const ValueKey('guide-expanded-image')))),
          TextButton(key: const ValueKey('guide-close-image'),
            onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ])),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final guide = guideFor(_selection.itemId);
    final sourceUri = officialWebUri(guide?.sourceUrl);
    return Scaffold(appBar: AppBar(title: const Text('품목별 배출 안내')),
      body: SafeArea(child: ListView(key: const ValueKey('guide-scroll'),
        padding: const EdgeInsets.all(24), children: [
        Text(_selection.item.name, key: const ValueKey('guide-item-name'),
          style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('확인한 종류: ${_selection.category.label}'),
        const SizedBox(height: 16),
        OutlinedButton.icon(key: const ValueKey('guide-change-item'),
          onPressed: _change, icon: const Icon(Icons.edit_outlined), label: const Text('품목 변경')),
        const SizedBox(height: 16),
        if (guide == null)
          const Card(child: Padding(padding: EdgeInsets.all(24),
            child: Text('이 품목의 안내는 준비 중입니다', key: ValueKey('guide-pending'))))
        else ...[
          if (guide.hasImage) ...[
            Semantics(button: true, label: '분리배출 안내 이미지 확대',
              child: InkWell(key: const ValueKey('guide-open-image'),
                onTap: () => _expandImage(guide),
                child: _guideImage(guide, key: const ValueKey('guide-inline-image')))),
            const SizedBox(height: 8),
            const Text('이미지를 누르면 확대할 수 있어요.\n배출 방법은 학교 또는 거주 지역의 안내도 확인해 주세요.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (guide.actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('핵심 배출 행동', style: Theme.of(context).textTheme.titleLarge),
            for (var i = 0; i < guide.actions.length; i++)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text('${i + 1}. ${guide.actions[i]}')),
          ],
          if (guide.cautions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('주의사항', style: Theme.of(context).textTheme.titleLarge),
            for (final caution in guide.cautions)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('• $caution')),
          ],
          const SizedBox(height: 24),
          Text('출처 표기: ${guide.institution}'),
          Text('자료 제목: ${guide.documentTitle}'),
          if (guide.verifiedReferenceDate?.trim().isNotEmpty ?? false)
            Text('작성일·기준일: ${guide.verifiedReferenceDate}'),
          Text('이용 조건 표기: ${guide.usageTerms}'),
          if (guide.sourceNote != null) ...[
            const SizedBox(height: 8),
            Text(guide.sourceNote!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (sourceUri != null)
            OutlinedButton.icon(onPressed: () => _open(sourceUri),
              icon: const Icon(Icons.open_in_new), label: const Text('공식 원문 보기')),
        ],
      ])));
  }
}
