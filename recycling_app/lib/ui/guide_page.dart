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
  void initState() { super.initState(); _selection = widget.selection; }

  Future<void> _change() async {
    final selected = await showItemPicker(context, initialSelection: _selection,
      title: '안내 품목 변경');
    if (!mounted || selected == null) return;
    widget.onSelectionChanged?.call(selected);
    setState(() => _selection = selected);
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _message('원문을 열지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } catch (_) { _message('원문을 열지 못했습니다. 잠시 후 다시 시도해 주세요.'); }
  }

  Widget _officialImage(Uri uri) => Image.network(uri.toString(), fit: BoxFit.contain,
    errorBuilder: (_, error, stack) => const Padding(padding: EdgeInsets.all(20),
      child: Text('공식 안내 이미지를 불러오지 못했습니다.')));

  @override
  Widget build(BuildContext context) {
    final guide = guideFor(_selection.itemId);
    final imageUri = officialWebUri(guide?.officialImageUrl);
    final sourceUri = officialWebUri(guide?.sourceUrl);
    return Scaffold(appBar: AppBar(title: const Text('품목별 배출 안내')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
        Text(_selection.item.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('확인한 종류: ${_selection.category.label}'),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _change, icon: const Icon(Icons.edit_outlined),
          label: const Text('품목 변경')),
        const SizedBox(height: 16),
        if (guide == null)
          const Card(child: Padding(padding: EdgeInsets.all(24),
            child: Text('이 품목의 안내는 준비 중입니다')))
        else ...[
          Text('핵심 배출 행동', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < guide.actions.length; i++)
            Padding(padding: const EdgeInsets.only(bottom: 10),
              child: Text('${i + 1}. ${guide.actions[i]}')),
          if (guide.cautions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('주의사항', style: Theme.of(context).textTheme.titleLarge),
            for (final caution in guide.cautions)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('• $caution')),
          ],
          if (imageUri != null) ...[
            const SizedBox(height: 20),
            Semantics(button: true, label: '공식 안내 이미지 확대',
              child: InkWell(onTap: () => showDialog<void>(context: context,
                builder: (context) => Dialog(child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.8,
                  width: double.maxFinite,
                  child: Column(
                  children: [
                    Expanded(child: InteractiveViewer(minScale: 0.5, maxScale: 5,
                      child: _officialImage(imageUri))),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
                  ])))), child: _officialImage(imageUri))),
            const Text('이미지를 누르면 확대할 수 있어요.'),
          ],
          const SizedBox(height: 24),
          Text('출처 기관: ${guide.institution}'),
          Text('자료 제목: ${guide.documentTitle}'),
          if (guide.verifiedReferenceDate?.trim().isNotEmpty ?? false)
            Text('작성일·기준일: ${guide.verifiedReferenceDate}'),
          Text('이용 조건: ${guide.usageTerms}'),
          if (sourceUri != null)
            OutlinedButton.icon(onPressed: () => _open(sourceUri),
              icon: const Icon(Icons.open_in_new), label: const Text('공식 원문 보기')),
        ],
      ])));
  }
}
