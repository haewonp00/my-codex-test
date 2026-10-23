import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/detection.dart';

class AnalysisException implements Exception {
  const AnalysisException(this.message);
  final String message;
}

abstract class DetectionApi {
  Future<AnalysisResult> analyze(File photo);
}

class HttpDetectionApi implements DetectionApi {
  static final Uri predictUrl = Uri.parse('http://127.0.0.1:8000/predict');
  @override
  Future<AnalysisResult> analyze(File photo) async {
    final client = http.Client();
    try {
      if (await photo.length() > 10 * 1024 * 1024) {
        throw const AnalysisException('10MB 이하 사진을 선택해 주세요.');
      }
      final response = await (() async {
        final request = http.MultipartRequest('POST', predictUrl);
        request.files.add(await http.MultipartFile.fromPath('file', photo.path));
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        var message = '분석에 실패했습니다. 잠시 후 다시 시도해 주세요.';
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map && body['detail'] is String) {
            message = body['detail'] as String;
          }
        } catch (_) {}
        throw AnalysisException(message);
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException();
      return AnalysisResult.fromJson(body);
    } on AnalysisException {
      rethrow;
    } on TimeoutException {
      throw const AnalysisException('분석 시간이 초과됐습니다. 잠시 후 다시 분석해 주세요.');
    } on SocketException {
      throw const AnalysisException('서버에 연결할 수 없습니다. 서버 실행과 USB 연결을 확인한 뒤 다시 시도해 주세요.');
    } on http.ClientException {
      throw const AnalysisException('통신에 실패했습니다. 서버와 USB 연결을 확인한 뒤 다시 시도해 주세요.');
    } on FormatException {
      throw const AnalysisException('분석 결과를 읽지 못했습니다. 앱과 서버를 함께 업데이트한 뒤 다시 시도해 주세요.');
    } on FileSystemException {
      throw const AnalysisException('사진을 읽지 못했습니다. 다시 선택해 주세요.');
    } finally {
      client.close();
    }
  }
}
