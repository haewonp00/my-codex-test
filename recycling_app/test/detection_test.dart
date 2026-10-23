import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycling_app/models/detection.dart';
import 'package:recycling_app/data/items.dart';
import 'package:recycling_app/data/guides.dart';
import 'helpers.dart';

void main() {
  Map<String, dynamic> body() => {
    'count': 1, 'image_width': 100, 'image_height': 100,
    'annotated_image': base64Encode(tinyPng),
    'detections': [<String, dynamic>{'detection_id': 'request:1', 'number': 1,
      'class_id': 0, 'label': 'plastic', 'label_ko': '플라스틱',
      'confidence': .38, 'bbox': [1, 2, 40, 80]}],
  };
  test('actual numbered API shape parses and keeps low confidence', () {
    final parsed = AnalysisResult.fromJson(body());
    expect(parsed.predictions[0].confidence, .38);
    expect(parsed.predictions[0].bbox, [1.0, 2.0, 40.0, 80.0]);
    expect(() => parsed.predictions[0].bbox.add(0), throwsUnsupportedError);
  });
  test('wrong class mapping and unnumbered old server are rejected', () {
    final wrong = body(); (wrong['detections'] as List)[0]['label'] = 'paper';
    expect(() => AnalysisResult.fromJson(wrong), throwsFormatException);
    final old = body(); (old['detections'] as List)[0].remove('number');
    expect(() => AnalysisResult.fromJson(old), throwsFormatException);
  });
  test('invalid bbox and count are rejected', () {
    final wrong = body(); wrong['count'] = 9;
    expect(() => AnalysisResult.fromJson(wrong), throwsFormatException);
    final box = body(); (box['detections'] as List)[0]['bbox'] = [1,2,200,90];
    expect(() => AnalysisResult.fromJson(box), throwsFormatException);
  });
  test('all 16 items are unique and no official guide is fabricated', () {
    expect(disposalItems.length, 16);
    expect(disposalItems.map((i) => i.id).toSet().length, 16);
    for (final item in disposalItems) { expect(guideFor(item.id), isNull); }
    expect(officialWebUri(null), isNull);
    expect(officialWebUri('javascript:alert(1)'), isNull);
    expect(() => ItemSelection(category: ItemCategory.paper, itemId: 'metal_can'), throwsArgumentError);
  });
}
