import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycling_app/main.dart';
import 'package:recycling_app/data/items.dart';
import 'package:recycling_app/ui/guide_page.dart';
import 'helpers.dart';

void main() {
  late Directory folder;
  late FakePhotos photos;
  late FakeApi api;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('recycling_widget_');
    final file = File('${folder.path}/photo.png');
    await file.writeAsBytes(tinyPng);
    photos = FakePhotos()..nextPath = file.path;
    api = FakeApi();
  });
  tearDown(() async { await folder.delete(recursive: true); });

  // A ListView lazily creates its children. First build the target by scrolling
  // its OWN list; ensureVisible alone cannot find a not-yet-created element.
  Future<void> reveal(WidgetTester tester, String listKey, Finder target) async {
    final list = find.byKey(ValueKey(listKey));
    expect(list, findsOneWidget);
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 150,
      scrollable: scrollable, maxScrolls: 100);
    await tester.pumpAndSettle();
    expect(target, findsOneWidget);
  }

  Future<void> tapInList(WidgetTester tester, String listKey, Finder target) async {
    await reveal(tester, listKey, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> checkCount(WidgetTester tester, String expected) async {
    final count = find.byKey(const ValueKey('result-count'));
    await reveal(tester, 'photo-scroll', count);
    expect(tester.widget<Text>(count).data, expected);
  }

  Future<void> confirmPicker(WidgetTester tester, String itemId) async {
    await tapInList(tester, 'item-picker-scroll', find.byKey(ValueKey('item-$itemId')));
    // Wait for the selection's setState before tapping the previously disabled
    // confirmation button. tapInList already pumped the new frame.
    final confirm = find.byKey(const ValueKey('picker-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }

  Future<void> analyze(WidgetTester tester) async {
    await tester.pumpWidget(MyApp(photos: photos, api: api));
    await tester.pumpAndSettle();
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('pick-gallery')));
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('analyze')));
  }

  testWidgets('two numbered cards survive selection, guide route, exclusion and restore', (tester) async {
    await analyze(tester);
    await checkCount(tester, 'AI 탐지 2개 · 확인 완료 0개');
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('confirm-1')));
    await confirmPicker(tester, 'plastic_clear_pet');
    await checkCount(tester, 'AI 탐지 2개 · 확인 완료 1개');
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('guide-1')));
    await reveal(tester, 'guide-scroll', find.byKey(const ValueKey('guide-inline-image')));
    expect(tester.widget<Image>(find.byKey(const ValueKey('guide-inline-image'))).image,
      isA<AssetImage>().having((image) => image.assetName, 'assetName', 'assets/guides/clear_pet.png'));
    expect(find.text('공식 원문 보기'), findsNothing);
    await tapInList(tester, 'guide-scroll', find.byKey(const ValueKey('guide-change-item')));
    await tester.tap(find.byKey(const ValueKey('category-paper')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('picker-confirm'))).onPressed, isNull);
    await confirmPicker(tester, 'paper_carton');
    final name = find.byKey(const ValueKey('guide-item-name'));
    await reveal(tester, 'guide-scroll', name);
    expect(tester.widget<Text>(name).data, '음료용 종이팩');
    await reveal(tester, 'guide-scroll', find.byKey(const ValueKey('guide-inline-image')));
    expect(tester.widget<Image>(find.byKey(const ValueKey('guide-inline-image'))).image,
      isA<AssetImage>().having((image) => image.assetName, 'assetName', 'assets/guides/paper.png'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await checkCount(tester, 'AI 탐지 2개 · 확인 완료 1개');
    await reveal(tester, 'photo-scroll', find.text('확인 완료: 종이 · 음료용 종이팩'));
    expect(find.text('AI는 플라스틱으로 예상했어요'), findsOneWidget);
    await reveal(tester, 'photo-scroll', find.text('#2 물건'));
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('exclude-1')));
    await checkCount(tester, 'AI 탐지 2개 · 확인 완료 0개');
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('restore-1')));
    await checkCount(tester, 'AI 탐지 2개 · 확인 완료 1개');
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero detections offers retake and manual lookup, never general waste', (tester) async {
    api.result = sampleResult(count: 0);
    await analyze(tester);
    await reveal(tester, 'photo-scroll', find.text('물건을 찾지 못했어요'));
    expect(find.text('다시 촬영'), findsOneWidget);
    expect(find.text('직접 배출 방법 찾기'), findsWidgets);
    expect(find.textContaining('일반쓰레기'), findsNothing);
  });

  testWidgets('manual lookup works before a photo on a small screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(photos: photos, api: api));
    await tester.pumpAndSettle();
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('manual-guide')));
    await tester.tap(find.byKey(const ValueKey('category-other')));
    await tester.pumpAndSettle();
    await confirmPicker(tester, 'other_glass');
    await reveal(tester, 'guide-scroll', find.byKey(const ValueKey('guide-pending')));
    final name = find.byKey(const ValueKey('guide-item-name'));
    await reveal(tester, 'guide-scroll', name);
    expect(tester.widget<Text>(name).data, '유리');
    expect(api.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long results list scrolls to independent last card on small screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.result = sampleResult(count: 12);
    await analyze(tester);
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('exclude-12')));
    await reveal(tester, 'photo-scroll', find.text('#12 물건 · 제외됨'));
    await tapInList(tester, 'photo-scroll', find.byKey(const ValueKey('restore-12')));
    await reveal(tester, 'photo-scroll', find.text('#12 물건'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bundled guide image opens in zoom dialog and closes without network', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: GuidePage(selection:
      ItemSelection(category: ItemCategory.metal, itemId: 'metal_can'))));
    await tester.pumpAndSettle();
    await reveal(tester, 'guide-scroll', find.byKey(const ValueKey('guide-open-image')));
    final inline = tester.widget<Image>(find.byKey(const ValueKey('guide-inline-image')));
    expect(inline.image, isA<AssetImage>());
    await tester.tap(find.byKey(const ValueKey('guide-open-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-image-dialog')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.widget<Image>(find.byKey(const ValueKey('guide-expanded-image'))).image,
      isA<AssetImage>().having((image) => image.assetName, 'assetName', 'assets/guides/metal_can.png'));
    await tester.tap(find.byKey(const ValueKey('guide-close-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-image-dialog')), findsNothing);
    await tapInList(tester, 'guide-scroll', find.byKey(const ValueKey('guide-change-item')));
    await tester.tap(find.byKey(const ValueKey('category-other')));
    await tester.pumpAndSettle();
    await confirmPicker(tester, 'other_glass');
    await reveal(tester, 'guide-scroll', find.byKey(const ValueKey('guide-pending')));
    expect(find.byKey(const ValueKey('guide-inline-image')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
