import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycling_app/main.dart';
import 'helpers.dart';

void main() {
  late Directory folder;
  late FakePhotos photos;
  late FakeApi api;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('recycling_widget_');
    final file = File('${folder.path}/photo.png'); await file.writeAsBytes(tinyPng);
    photos = FakePhotos()..nextPath = file.path;
    api = FakeApi();
  });
  tearDown(() async { await folder.delete(recursive: true); });

  Future<void> analyze(WidgetTester tester) async {
    await tester.pumpWidget(MyApp(photos: photos, api: api));
    await tester.pumpAndSettle();
    final gallery = find.text('갤러리에서 선택');
    await tester.ensureVisible(gallery); await tester.tap(gallery); await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('analyze'));
    await tester.ensureVisible(button); await tester.tap(button); await tester.pumpAndSettle();
  }

  testWidgets('two numbered cards survive selection, guide route, exclusion and restore', (tester) async {
    await analyze(tester);
    expect(find.text('AI 탐지 2개 · 확인 완료 0개'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('confirm-1'));
    await tester.ensureVisible(confirm); await tester.tap(confirm); await tester.pumpAndSettle();
    final pet = find.byKey(const ValueKey('item-plastic_clear_pet'));
    await tester.ensureVisible(pet); await tester.tap(pet);
    await tester.tap(find.text('이 품목으로 확인')); await tester.pumpAndSettle();
    expect(find.text('AI 탐지 2개 · 확인 완료 1개'), findsOneWidget);
    final guide = find.byKey(const ValueKey('guide-1'));
    await tester.ensureVisible(guide); await tester.tap(guide); await tester.pumpAndSettle();
    expect(find.text('이 품목의 안내는 준비 중입니다'), findsOneWidget);
    expect(find.text('공식 원문 보기'), findsNothing);
    await tester.tap(find.text('품목 변경')); await tester.pumpAndSettle();
    await tester.tap(find.text('종이')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '이 품목으로 확인')).onPressed, isNull);
    final carton = find.byKey(const ValueKey('item-paper_carton'));
    await tester.ensureVisible(carton); await tester.tap(carton);
    await tester.tap(find.text('이 품목으로 확인')); await tester.pumpAndSettle();
    expect(find.text('음료용 종이팩'), findsOneWidget);
    expect(find.text('투명 음료·생수 페트병'), findsNothing);
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(find.text('확인 완료: 종이 · 음료용 종이팩'), findsOneWidget);
    expect(find.text('AI는 플라스틱으로 예상했어요'), findsOneWidget);
    expect(find.text('AI 탐지 2개 · 확인 완료 1개'), findsOneWidget);
    final exclude = find.byKey(const ValueKey('exclude-1'));
    await tester.ensureVisible(exclude); await tester.tap(exclude); await tester.pumpAndSettle();
    expect(find.text('AI 탐지 2개 · 확인 완료 0개'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-1'))); await tester.pumpAndSettle();
    expect(find.text('AI 탐지 2개 · 확인 완료 1개'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero detections offers retake and manual lookup, never general waste', (tester) async {
    api.result = sampleResult(count: 0);
    await analyze(tester);
    expect(find.text('물건을 찾지 못했어요'), findsOneWidget);
    expect(find.text('다시 촬영'), findsOneWidget);
    expect(find.text('직접 배출 방법 찾기'), findsWidgets);
    expect(find.textContaining('일반쓰레기'), findsNothing);
  });

  testWidgets('manual lookup works before a photo on a small screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(photos: photos, api: api)); await tester.pumpAndSettle();
    await tester.tap(find.text('직접 배출 방법 찾기')); await tester.pumpAndSettle();
    await tester.tap(find.text('기타')); await tester.pumpAndSettle();
    final glass = find.byKey(const ValueKey('item-other_glass'));
    await tester.ensureVisible(glass); await tester.tap(glass);
    await tester.ensureVisible(find.text('이 품목으로 확인'));
    await tester.tap(find.text('이 품목으로 확인')); await tester.pumpAndSettle();
    expect(find.text('이 품목의 안내는 준비 중입니다'), findsOneWidget);
    expect(api.calls, 0); expect(tester.takeException(), isNull);
  });

  testWidgets('long results list scrolls to independent last card on small screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.result = sampleResult(count: 12);
    await analyze(tester);
    final last = find.byKey(const ValueKey('exclude-12'));
    await tester.scrollUntilVisible(last, 250, maxScrolls: 60);
    await tester.tap(last); await tester.pumpAndSettle();
    expect(find.text('#12 물건 · 제외됨'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-12'))); await tester.pumpAndSettle();
    expect(find.text('#12 물건'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
