import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:recycling_app/models/detection.dart';
import 'package:recycling_app/services/detection_api.dart';
import 'package:recycling_app/services/photo_service.dart';

final tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAIAAAACUFjqAAAAFUlEQVR4nGP8//8/A27AhEduBEsDAKXjAxF9kqZqAAAAAElFTkSuQmCC');

class FakePhotos implements PhotoService {
  String? nextPath;
  String? recovered;
  @override
  Future<String?> pick(ImageSource source) async => nextPath;
  @override
  Future<String?> recover() async => recovered;
}

class FakeApi implements DetectionApi {
  int calls = 0;
  AnalysisResult result = sampleResult();
  final List<Completer<AnalysisResult>> pending = [];
  @override
  Future<AnalysisResult> analyze(File photo) {
    calls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    return Future.value(result);
  }
}

AnalysisResult sampleResult({int count = 2, String prefix = 'batch'}) => AnalysisResult(
  predictions: List.generate(count, (i) => DetectionPrediction(id: '$prefix:$i',
    number: i + 1, classId: i % 3, className: classNames[i % 3]!,
    confidence: .99, bbox: [1, 2, 3, 4])),
  annotatedImage: Uint8List.fromList(tinyPng), width: 10, height: 10);
