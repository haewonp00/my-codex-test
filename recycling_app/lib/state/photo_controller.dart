import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../data/items.dart';
import '../models/detection.dart';
import '../services/detection_api.dart';
import '../services/photo_service.dart';

class PhotoController extends ChangeNotifier {
  PhotoController({required this.api, required this.photos});
  final DetectionApi api;
  final PhotoService photos;
  File? photo;
  Uint8List? annotatedImage;
  List<DetectionEntry> _entries = [];
  List<DetectionEntry> get entries => List.unmodifiable(_entries);
  bool initializing = true;
  bool picking = false;
  bool analyzing = false;
  bool hasResult = false;
  String? error;
  int _request = 0;
  bool _disposed = false;
  bool get busy => initializing || picking || analyzing;
  int get confirmedCount => _entries.where((e) => e.isConfirmed && !e.isExcluded).length;
  int get excludedCount => _entries.where((e) => e.isExcluded).length;
  int get activeCount => _entries.length - excludedCount;
  void _notify() { if (!_disposed) notifyListeners(); }

  void _acceptPhoto(String path) {
    _request++; // 이전 사진 요청의 성공·실패 응답 모두 무시합니다.
    photo = File(path);
    _entries = [];
    annotatedImage = null;
    hasResult = false;
    analyzing = false;
    error = null;
  }

  Future<void> recover() async {
    try {
      final path = await photos.recover();
      if (_disposed) return;
      if (path != null) _acceptPhoto(path);
    } catch (_) {
      if (!_disposed) error = '사진을 복구하지 못했습니다. 다시 선택해 주세요.';
    } finally {
      if (!_disposed) { initializing = false; _notify(); }
    }
  }

  Future<void> pick(ImageSource source) async {
    if (initializing || picking || _disposed) return;
    picking = true; _notify();
    try {
      final path = await photos.pick(source);
      if (_disposed) return;
      // 취소하면 사진·확인 상태·진행 중 분석을 그대로 유지합니다.
      if (path != null) _acceptPhoto(path);
    } catch (_) {
      if (!_disposed) error = '사진을 가져오지 못했습니다. 권한을 확인하고 다시 선택해 주세요.';
    } finally {
      if (!_disposed) { picking = false; _notify(); }
    }
  }

  Future<void> analyze() async {
    final selected = photo;
    if (selected == null || busy || _disposed) return;
    final request = ++_request;
    analyzing = true; error = null;
    _entries = []; annotatedImage = null; hasResult = false;
    _notify();
    try {
      final result = await api.analyze(selected);
      if (_disposed || request != _request) return;
      _entries = result.predictions.map((p) => DetectionEntry(prediction: p)).toList();
      annotatedImage = result.annotatedImage;
      hasResult = true;
    } catch (e) {
      if (_disposed || request != _request) return;
      error = e is AnalysisException ? e.message : '분석에 실패했습니다. 잠시 후 다시 시도해 주세요.';
    } finally {
      if (!_disposed && request == _request) { analyzing = false; _notify(); }
    }
  }

  DetectionEntry entry(String id) => _entries.firstWhere((e) => e.prediction.id == id);
  void confirm(String id, ItemSelection value) {
    _entries = _entries.map((e) => e.prediction.id == id ? e.confirm(value) : e).toList();
    _notify();
  }
  void exclude(String id, bool value) {
    _entries = _entries.map((e) => e.prediction.id == id ? e.excluded(value) : e).toList();
    _notify();
  }
  @override
  void dispose() { _disposed = true; _request++; super.dispose(); }
}
