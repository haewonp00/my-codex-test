import 'package:image_picker/image_picker.dart';

abstract class PhotoService {
  Future<String?> recover();
  Future<String?> pick(ImageSource source);
}

class PickerPhotoService implements PhotoService {
  final ImagePicker _picker = ImagePicker();
  @override
  Future<String?> recover() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty ? null : files.first.path;
  }
  @override
  Future<String?> pick(ImageSource source) async {
    final result = await _picker.pickImage(source: source, maxWidth: 1600,
      maxHeight: 1600, imageQuality: 90);
    return result?.path;
  }
}
