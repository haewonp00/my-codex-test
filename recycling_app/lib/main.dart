import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'data/items.dart';
import 'models/detection.dart';
import 'services/detection_api.dart';
import 'services/photo_service.dart';
import 'state/photo_controller.dart';
import 'ui/guide_page.dart';
import 'ui/item_picker.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.photos, this.api});
  final PhotoService? photos;
  final DetectionApi? api;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '분리수거 도우미', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF20845A)),
      useMaterial3: true),
    home: PhotoPage(photos: photos, api: api));
}

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key, this.photos, this.api});
  final PhotoService? photos;
  final DetectionApi? api;
  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  late final PhotoController _controller;
  @override
  void initState() {
    super.initState();
    _controller = PhotoController(api: widget.api ?? HttpDetectionApi(),
      photos: widget.photos ?? PickerPhotoService());
    _controller.recover();
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _manualGuide() async {
    final selected = await showItemPicker(context, title: '직접 배출 방법 찾기');
    if (!mounted || selected == null) {
return;
}
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => GuidePage(selection: selected)));
  }

  Future<void> _confirm(DetectionEntry entry, {bool changing = false}) async {
    final id = entry.prediction.id;
    final selected = await showItemPicker(context,
      initialSelection: entry.selection, initialCategory: entry.prediction.category,
      title: changing ? '종류 바꾸기 / 세부 품목 선택' : '종류 확인 / 세부 품목 선택');
    if (!mounted || selected == null) {
return;
}
    // 선택 창이 열린 사이 결과가 바뀌면 이전 카드를 변경하지 않습니다.
    if (!_controller.entries.any((e) => e.prediction.id == id)) {
return;
}
    _controller.confirm(id, selected);
  }

  Future<void> _guide(DetectionEntry entry) async {
    final selection = entry.selection;
    if (selection == null || entry.isExcluded) {
return;
}
    final id = entry.prediction.id;
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => GuidePage(
      selection: selection, onSelectionChanged: (selected) {
        if (_controller.entries.any((e) => e.prediction.id == id)) {
          _controller.confirm(id, selected);
        }
      })));
  }

  Widget _preview() {
    final annotated = _controller.annotatedImage;
    if (annotated != null) {
return Image.memory(annotated, fit: BoxFit.contain,
      errorBuilder: (_, error, stack) => const Center(child: Text('분석 이미지를 표시하지 못했습니다. 다시 분석해 주세요.')));
}
    final photo = _controller.photo;
    if (photo != null) {
return Image.file(photo, fit: BoxFit.contain,
      errorBuilder: (_, error, stack) => const Center(child: Text('사진을 다시 선택해 주세요.')));
}
    return const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.add_photo_alternate_outlined, size: 64, color: Colors.grey),
      SizedBox(height: 12), Text('선택한 사진이 여기에 표시됩니다.'),
    ]);
  }

  Widget _card(DetectionEntry entry) {
    final prediction = entry.prediction;
    final selection = entry.selection;
    final n = prediction.number;
    return Card(key: ValueKey('detection-${prediction.id}'), child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('#$n 물건${entry.isExcluded ? ' · 제외됨' : ''}',
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('AI는 ${prediction.labelKo}${prediction.classId == 1 ? '로' : '으로'} 예상했어요'),
        Text('모델 신뢰도 ${(prediction.confidence * 100).toStringAsFixed(1)}%'),
        const SizedBox(height: 8),
        if (entry.isExcluded) ...[
          const Text('이 결과는 안내 대상에서 제외했어요.'),
          TextButton.icon(key: ValueKey('restore-$n'),
            onPressed: () => _controller.exclude(prediction.id, false),
            icon: const Icon(Icons.undo), label: const Text('복원하기')),
        ] else ...[
          if (selection != null)
            Text('확인 완료: ${selection.category.label} · ${selection.item.name}',
              style: const TextStyle(color: Color(0xFF20845A), fontWeight: FontWeight.bold))
          else const Text('종류와 세부 품목을 직접 확인해 주세요.'),
          const SizedBox(height: 8),
          OutlinedButton(key: ValueKey('confirm-$n'),
            onPressed: () => _confirm(entry), child: const Text('종류 확인 / 세부 품목 선택')),
          Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton(key: ValueKey('change-$n'), onPressed: () => _confirm(entry, changing: true),
              child: const Text('종류 바꾸기')),
            TextButton(key: ValueKey('exclude-$n'),
              onPressed: () => _controller.exclude(prediction.id, true),
              child: const Text('물건이 아니에요')),
          ]),
          FilledButton(key: ValueKey('guide-$n'),
            onPressed: selection == null ? null : () => _guide(entry),
            child: const Text('이 물건 배출 안내 보기')),
        ],
      ])));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _controller,
    builder: (context, _) {
      final c = _controller;
      return Scaffold(backgroundColor: const Color(0xFFF5F8F5),
        appBar: AppBar(title: const Text('분리수거 도우미'), backgroundColor: const Color(0xFFF5F8F5)),
        body: SafeArea(child: ListView(key: const ValueKey('photo-scroll'), padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.recycling, size: 56, color: Color(0xFF20845A)),
          const SizedBox(height: 16),
          const Text('어떤 물건을 버리시나요?', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('사진을 선택하고 분석하기를 눌러 주세요.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(key: const ValueKey('manual-guide'), onPressed: _manualGuide, icon: const Icon(Icons.menu_book_outlined),
            label: const Text('직접 배출 방법 찾기')),
          const SizedBox(height: 16),
          Container(height: 320, clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDCE6DE))), child: _preview()),
          if (c.annotatedImage != null) ...[
            const SizedBox(height: 8),
            const Text('사진의 #번호와 같은 번호의 카드를 확인해 주세요.\n제외한 물건의 번호도 사진에는 남아 있어요.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(key: const ValueKey('pick-camera'), onPressed: c.initializing || c.picking ? null : () => c.pick(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined), label: const Text('사진 촬영')),
          OutlinedButton.icon(key: const ValueKey('pick-gallery'), onPressed: c.initializing || c.picking ? null : () => c.pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('갤러리에서 선택')),
          const SizedBox(height: 16),
          FilledButton.icon(key: const ValueKey('analyze'),
            onPressed: c.busy || c.photo == null ? null : c.analyze,
            icon: const Icon(Icons.search), label: Text(c.analyzing ? '분석 중…' : '분석하기'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52))),
          if (c.busy) ...[const SizedBox(height: 16), const Center(child: CircularProgressIndicator())],
          if (c.error != null) ...[
            const SizedBox(height: 16),
            Text(c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (c.photo != null)
              OutlinedButton(onPressed: c.busy ? null : c.analyze, child: const Text('다시 분석하기')),
          ],
          if (c.hasResult) ...[
            const SizedBox(height: 24),
            Text('AI 탐지 ${c.entries.length}개 · 확인 완료 ${c.confirmedCount}개',
              key: const ValueKey('result-count'),
              style: Theme.of(context).textTheme.titleLarge),
            Text('안내 대상 ${c.activeCount}개 · 제외 ${c.excludedCount}개'),
            const SizedBox(height: 12),
            if (c.entries.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
                const Text('물건을 찾지 못했어요'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: c.picking ? null : () => c.pick(ImageSource.camera),
                  child: const Text('다시 촬영')),
                TextButton(onPressed: _manualGuide, child: const Text('직접 배출 방법 찾기')),
              ]))),
            if (c.entries.isNotEmpty && c.activeCount == 0)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('모든 탐지를 제외했어요. 아래 카드에서 복원하거나 직접 배출 방법을 찾아보세요.')),
            for (final entry in c.entries) _card(entry),
            if (c.entries.isNotEmpty)
              const Padding(padding: EdgeInsets.only(top: 8),
                child: Text('AI 예측은 틀릴 수 있습니다. 모델 신뢰도는 정답일 확률이나 전체 정확도를 뜻하지 않습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black54))),
          ],
        ])));
    });
}
