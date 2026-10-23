import 'dart:convert';
import 'dart:typed_data';
import '../data/items.dart';

const classNames = {0: 'plastic', 1: 'paper', 2: 'metal'};
const classLabels = {0: '플라스틱', 1: '종이', 2: '금속'};

class DetectionPrediction {
  DetectionPrediction({required this.id, required this.number,
    required this.classId, required this.className, required this.confidence,
    required List<double> bbox}) : bbox = List.unmodifiable(bbox);
  final String id;
  final int number;
  final int classId;
  final String className;
  final double confidence;
  final List<double> bbox; // EXIF 보정된 원본 이미지의 xyxy 픽셀 좌표
  String get labelKo => classLabels[classId]!;
  ItemCategory get category => switch (classId) {
    0 => ItemCategory.plastic,
    1 => ItemCategory.paper,
    _ => ItemCategory.metal,
  };
}

class DetectionEntry {
  const DetectionEntry({required this.prediction, this.selection,
    this.isExcluded = false});
  final DetectionPrediction prediction; // 사용자 수정으로 절대 변경하지 않음
  final ItemSelection? selection;
  final bool isExcluded;
  bool get isConfirmed => selection != null;
  DetectionEntry confirm(ItemSelection value) => DetectionEntry(
    prediction: prediction, selection: value, isExcluded: isExcluded);
  DetectionEntry excluded(bool value) => DetectionEntry(
    prediction: prediction, selection: selection, isExcluded: value);
}

class AnalysisResult {
  AnalysisResult({required List<DetectionPrediction> predictions,
    required this.annotatedImage, required this.width, required this.height})
    : predictions = List.unmodifiable(predictions);
  final List<DetectionPrediction> predictions;
  final Uint8List annotatedImage;
  final int width;
  final int height;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final width = json['image_width'];
    final height = json['image_height'];
    final raw = json['detections'];
    final image = json['annotated_image'];
    if (width is! int || height is! int || width <= 0 || height <= 0 ||
        raw is! List || json['count'] != raw.length ||
        image is! String || image.isEmpty) {
      throw const FormatException('분석 응답 형식이 올바르지 않습니다.');
    }
    final predictions = <DetectionPrediction>[];
    final ids = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      if (row is! Map) throw const FormatException('탐지 형식 오류');
      final id = row['detection_id'];
      final cls = row['class_id'];
      final confidence = row['confidence'];
      final bbox = row['bbox'];
      if (id is! String || id.isEmpty || !ids.add(id) ||
          row['number'] != i + 1 || cls is! int ||
          !classNames.containsKey(cls) || row['label'] != classNames[cls] ||
          confidence is! num || !confidence.isFinite ||
          confidence < 0 || confidence > 1 || bbox is! List ||
          bbox.length != 4 || bbox.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('탐지 번호나 클래스 형식을 확인해 주세요.');
      }
      final coords = bbox.map((v) => (v as num).toDouble()).toList();
      if (coords[0] < 0 || coords[1] < 0 || coords[2] > width ||
          coords[3] > height || coords[0] >= coords[2] || coords[1] >= coords[3]) {
        throw const FormatException('물체 위치 형식이 올바르지 않습니다.');
      }
      predictions.add(DetectionPrediction(id: id, number: i + 1,
        classId: cls, className: classNames[cls]!,
        confidence: confidence.toDouble(), bbox: coords));
    }
    final bytes = base64Decode(image);
    if (bytes.isEmpty) throw const FormatException('분석 이미지가 없습니다.');
    return AnalysisResult(predictions: predictions, annotatedImage: bytes,
      width: width, height: height);
  }
}
