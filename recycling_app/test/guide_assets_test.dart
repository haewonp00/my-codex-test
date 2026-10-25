import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycling_app/data/guides.dart';
import 'package:recycling_app/models/detection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const assets = {
    'assets/guides/paper.png',
    'assets/guides/metal_can.png',
    'assets/guides/clear_pet.png',
    'assets/guides/plastic.png',
    'assets/guides/film.png',
    'assets/guides/mixed_packaging.png',
  };
  for (final asset in assets) {
    test('real image is bundled: $asset', () async {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(bytes.length, greaterThan(1000));
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  }
  test('YOLO classes remain plastic, paper and metal only', () {
    expect(classNames, {0: 'plastic', 1: 'paper', 2: 'metal'});
  });
  test('nine guide items use six images; unsupported items stay pending', () {
    expect(disposalGuides.length, 9);
    expect(disposalGuides.values.map((g) => g.assetImagePath).toSet(), assets);
    expect(guideFor('paper_general'), same(guideFor('paper_cardboard')));
    expect(guideFor('paper_carton'), same(guideFor('paper_general')));
    expect(guideFor('metal_pressurized'), isNull);
    expect(guideFor('metal_other'), isNull);
    expect(guideFor('other_glass'), isNull);
    expect(guideFor('other_film')!.assetImagePath, 'assets/guides/film.png');
    expect(guideFor('other_mixed')!.assetImagePath, 'assets/guides/mixed_packaging.png');
    expect(guideFor('other_film')!.manualSelectionOnly, true);
    expect(guideFor('other_mixed')!.manualSelectionOnly, true);
    expect(guideFor('plastic_unknown'), isNull);
    for (final guide in disposalGuides.values) {
      expect(guide.isRegistered, true);
      expect(guide.hasImage, true);
      expect(guide.officialImageUrl, isNull);
      expect(guide.sourceUrl, isNull);
      expect(guide.verifiedReferenceDate, isNull);
      expect(guide.sourceVerified, false);
      expect(guide.actions, isEmpty); // Do not invent extra disposal text.
    }
  });
}
