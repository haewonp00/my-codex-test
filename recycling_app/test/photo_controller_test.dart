import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recycling_app/data/items.dart';
import 'package:recycling_app/models/detection.dart';
import 'package:recycling_app/services/detection_api.dart';
import 'package:recycling_app/state/photo_controller.dart';
import 'helpers.dart';

void main() {
  late FakePhotos photos;
  late FakeApi api;
  late PhotoController controller;
  setUp(() async {
    photos = FakePhotos()..nextPath = '/first.jpg';
    api = FakeApi();
    controller = PhotoController(api: api, photos: photos);
    await controller.recover();
    await controller.pick(ImageSource.gallery);
  });
  tearDown(() => controller.dispose());

  test('high confidence still needs confirmation; cards are independent', () async {
    await controller.analyze();
    expect(controller.entries.length, 2);
    expect(controller.confirmedCount, 0);
    final first = controller.entries.first;
    controller.confirm(first.prediction.id, ItemSelection(category: ItemCategory.paper, itemId: 'paper_carton'));
    expect(controller.confirmedCount, 1);
    expect(controller.entries[1].isConfirmed, false);
    expect(controller.entries[0].prediction.className, 'plastic');
    controller.confirm(first.prediction.id, ItemSelection(category: ItemCategory.other, itemId: 'other_glass'));
    expect(controller.entries[0].selection!.itemId, 'other_glass');
    expect(controller.entries[0].prediction.confidence, .99);
  });

  test('exclude all and restore keeps IDs, cards and confirmed selection', () async {
    await controller.analyze();
    final ids = controller.entries.map((e) => e.prediction.id).toList();
    controller.confirm(ids[0], ItemSelection(category: ItemCategory.metal, itemId: 'metal_can'));
    for (final id in ids) { controller.exclude(id, true); }
    expect(controller.entries.length, 2);
    expect(controller.activeCount, 0);
    expect(controller.confirmedCount, 0);
    controller.exclude(ids[0], false);
    expect(controller.confirmedCount, 1);
    expect(controller.entries[0].selection!.itemId, 'metal_can');
    expect(controller.entries.map((e) => e.prediction.id), ids);
  });

  test('cancel picking retains photo, results and confirmation', () async {
    await controller.analyze();
    controller.confirm(controller.entries[0].prediction.id,
      ItemSelection(category: ItemCategory.plastic, itemId: 'plastic_clear_pet'));
    photos.nextPath = null;
    await controller.pick(ImageSource.camera);
    expect(controller.photo!.path, '/first.jpg');
    expect(controller.hasResult, true);
    expect(controller.confirmedCount, 1);
  });

  test('new photo resets all result state', () async {
    await controller.analyze();
    controller.exclude(controller.entries.first.prediction.id, true);
    photos.nextPath = '/second.jpg';
    await controller.pick(ImageSource.gallery);
    expect(controller.entries, isEmpty);
    expect(controller.annotatedImage, isNull);
    expect(controller.hasResult, false);
    expect(controller.excludedCount, 0);
  });

  test('new request wins even when old response finishes later', () async {
    final first = Completer<AnalysisResult>();
    final second = Completer<AnalysisResult>();
    api.pending.addAll([first, second]);
    final oldWork = controller.analyze();
    photos.nextPath = '/second.jpg';
    await controller.pick(ImageSource.gallery);
    final newWork = controller.analyze();
    second.complete(sampleResult(count: 1, prefix: 'new'));
    await newWork;
    first.complete(sampleResult(count: 3, prefix: 'old'));
    await oldWork;
    expect(controller.entries.length, 1);
    expect(controller.entries.first.prediction.id, startsWith('new:'));
    expect(controller.analyzing, false);
  });

  test('late old failure does not show an error on new photo', () async {
    final pending = Completer<AnalysisResult>(); api.pending.add(pending);
    final oldWork = controller.analyze();
    photos.nextPath = '/second.jpg'; await controller.pick(ImageSource.gallery);
    pending.completeError(const AnalysisException('old error'));
    await oldWork;
    expect(controller.error, isNull);
    expect(controller.photo!.path, '/second.jpg');
  });

  test('cancel during request preserves request; duplicate analyze is ignored', () async {
    final pending = Completer<AnalysisResult>(); api.pending.add(pending);
    final work = controller.analyze();
    await controller.analyze(); expect(api.calls, 1);
    photos.nextPath = null; await controller.pick(ImageSource.gallery);
    expect(controller.analyzing, true);
    pending.complete(sampleResult()); await work;
    expect(controller.hasResult, true);
  });

  test('failed analysis can be retried', () async {
    final pending = Completer<AnalysisResult>(); api.pending.add(pending);
    final work = controller.analyze(); pending.completeError(const AnalysisException('다시 시도'));
    await work; expect(controller.error, '다시 시도'); expect(controller.analyzing, false);
    await controller.analyze(); expect(controller.error, isNull); expect(controller.hasResult, true);
  });

  test('zero detections is a valid completed result', () async {
    api.result = sampleResult(count: 0);
    await controller.analyze();
    expect(controller.hasResult, true); expect(controller.entries, isEmpty);
  });
}
