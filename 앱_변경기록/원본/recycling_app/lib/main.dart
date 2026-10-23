import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '분리수거 도우미',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20845A),
        ),
        useMaterial3: true,
      ),
      home: const PhotoPage(),
    );
  }
}

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  final ImagePicker _picker = ImagePicker();

  static final Uri _predictUrl =
      Uri.parse('http://127.0.0.1:8000/predict');

  File? _photo;

  // 서버에서 받은 사각형 표시 이미지입니다.
  Uint8List? _annotatedImage;

  bool _busy = true;
  bool _analyzing = false;
  String? _error;
  List<Map<String, dynamic>>? _detections;

  @override
  void initState() {
    super.initState();
    _recoverPhoto();
  }

  Future<void> _recoverPhoto() async {
    try {
      final response = await _picker.retrieveLostData();
      if (!mounted) return;

      final files = response.files;
      if (files != null && files.isNotEmpty) {
        setState(() {
          _photo = File(files.first.path);
          _detections = null;
          _annotatedImage = null;
        });
      } else if (response.exception != null) {
        _setError('이전 사진을 복구하지 못했습니다. 다시 선택해 주세요.');
      }
    } catch (e) {
      debugPrint('사진 복구 오류: $e');
      _setError('사진을 다시 선택해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (!mounted || picked == null) return;

      setState(() {
        _photo = File(picked.path);
        _detections = null;
        _annotatedImage = null;
      });
    } catch (e) {
      debugPrint('사진 선택 오류: $e');
      _setError('사진을 가져오지 못했습니다. 권한을 확인해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<http.Response> _uploadPhoto(
    http.Client client,
    File photo,
  ) async {
    final request = http.MultipartRequest('POST', _predictUrl);

    request.files.add(
      await http.MultipartFile.fromPath('file', photo.path),
    );

    final streamedResponse = await client.send(request);
    return http.Response.fromStream(streamedResponse);
  }

  Future<void> _analyzePhoto() async {
    final photo = _photo;
    if (photo == null || _busy) return;

    setState(() {
      _busy = true;
      _analyzing = true;
      _error = null;
      _detections = null;
      _annotatedImage = null;
    });

    final client = http.Client();

    try {
      if (await photo.length() > 10 * 1024 * 1024) {
        throw Exception('10MB 이하 사진을 선택해 주세요.');
      }

      final response = await _uploadPhoto(client, photo).timeout(
        const Duration(seconds: 60),
      );

      if (response.statusCode != 200) {
        String message = '서버 오류 (${response.statusCode})';

        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map && body['detail'] is String) {
            message = body['detail'] as String;
          }
        } catch (_) {}

        throw Exception(message);
      }

      final body =
          jsonDecode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;

      final detections = (body['detections'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      // Base64 문자열을 이미지 바이트로 복원합니다.
      final encodedImage = body['annotated_image'];
      Uint8List? annotatedImage;

      if (encodedImage is String && encodedImage.isNotEmpty) {
        annotatedImage = base64Decode(encodedImage);
      }

      if (!mounted) return;

      setState(() {
        _detections = detections;
        _annotatedImage = annotatedImage;

        if (annotatedImage == null) {
          _error = '분석 결과는 받았지만 사각형 이미지는 없습니다. '
              'server.py 수정 내용이 저장·적용됐는지 확인해 주세요.';
        }
      });
    } on TimeoutException {
      _setError('분석 시간이 초과됐습니다. 서버 상태를 확인해 주세요.');
    } on SocketException {
      _setError('서버에 연결할 수 없습니다. 서버 실행과 USB 연결을 확인해 주세요.');
    } on http.ClientException {
      _setError('서버 통신에 실패했습니다. USB 연결과 서버 상태를 확인해 주세요.');
    } catch (e) {
      debugPrint('분석 오류: $e');
      _setError(
        '분석 실패: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      client.close();

      if (mounted) {
        setState(() {
          _busy = false;
          _analyzing = false;
        });
      }
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() => _error = message);
    }
  }

  // 분석 후에는 사각형 이미지, 분석 전에는 원본을 보여 줍니다.
  Widget _buildPhotoPreview() {
    final annotated = _annotatedImage;

    if (annotated != null) {
      return Image.memory(
        annotated,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Text('분석 이미지를 표시하지 못했습니다. 다시 분석해 주세요.'),
          );
        },
      );
    }

    if (_photo != null) {
      return Image.file(
        _photo!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Text('사진을 다시 선택해 주세요.'),
          );
        },
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 64,
          color: Colors.grey,
        ),
        SizedBox(height: 12),
        Text('선택한 사진이 여기에 표시됩니다.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final detections = _detections;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F5),
      appBar: AppBar(
        title: const Text('분리수거 도우미'),
        backgroundColor: const Color(0xFFF5F8F5),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.recycling,
              size: 56,
              color: Color(0xFF20845A),
            ),
            const SizedBox(height: 16),
            const Text(
              '어떤 물건을 버리시나요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '사진을 선택하고 분석하기를 눌러 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Container(
              height: 320,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFDCE6DE),
                ),
              ),
              child: _buildPhotoPreview(),
            ),
            if (_annotatedImage != null) ...[
              const SizedBox(height: 8),
              const Text(
                '사각형은 AI가 물체로 탐지한 영역입니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed:
                  _busy ? null : () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('사진 촬영'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  _busy ? null : () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('갤러리에서 선택'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _photo == null ? null : _analyzePhoto,
              icon: const Icon(Icons.search),
              label: Text(_analyzing ? '분석 중…' : '분석하기'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (detections != null) ...[
              const SizedBox(height: 24),
              Text(
                '분석 결과 · ${detections.length}개 탐지',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (detections.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '물체를 찾지 못했습니다.\n'
                      '물건 전체가 잘 보이도록 밝은 곳에서 다시 촬영해 주세요.',
                    ),
                  ),
                ),
              for (final item in detections)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.recycling,
                      color: Color(0xFF20845A),
                    ),
                    title: Text(
                      '${item['label_ko']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '모델 신뢰도 '
                      '${((item['confidence'] as num) * 100).toStringAsFixed(1)}%',
                    ),
                  ),
                ),
              if (detections.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'AI 예측은 틀릴 수 있습니다. '
                    '신뢰도는 모델 전체 정확도를 뜻하지 않습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
