// lib/services/cloudinary_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  static const String cloudName = 'zyvukzwf';
  static const String uploadPreset = 'flutter_unsigned';

  static Future<String?> uploadImage(XFile imageFile) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final response = await request.send();
    final resBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final data = jsonDecode(resBody);
      return data['secure_url'] as String;
    } else {
      // ignore: avoid_print
      print('Cloudinary upload failed: $resBody');
      return null;
    }
  }
}
