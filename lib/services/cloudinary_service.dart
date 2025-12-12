import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crypto/crypto.dart'; // Pastikan package crypto ada di pubspec.yaml

class CloudinaryResponse {
  final String? secureUrl;
  final String? publicId;
  final String? error;

  CloudinaryResponse({this.secureUrl, this.publicId, this.error});
}

class CloudinaryService {
  final String _cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  final String _uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';
  final String _apiKey = dotenv.env['CLOUDINARY_API_KEY'] ?? '';
  final String _apiSecret = dotenv.env['CLOUDINARY_API_SECRET'] ?? '';

  // Helper lama tetap ada tapi dibungkus untuk backward compatibility
  Future<String?> uploadFile(File file, String resourceType) async {
    final response = await uploadFileWithDetails(file, resourceType);
    return response.secureUrl;
  }

  Future<String?> uploadImage(File file) => uploadFile(file, 'image');
  Future<String?> uploadMedia(File file) => uploadFile(file, 'auto');

  // Method BARU yang mengembalikan detail lengkap (URL + Public ID)
  Future<CloudinaryResponse> uploadFileWithDetails(File file, String resourceType) async {
    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      return CloudinaryResponse(error: "Cloudinary credentials missing.");
    }
    
    final uploadUrl = 'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload';

    try {
      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'file', 
          file.path,
          filename: file.path.split('/').last,
        ),
      );
      
      request.fields['upload_preset'] = _uploadPreset;
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final data = json.decode(responseBody);
      
      if (response.statusCode == 200) {
        return CloudinaryResponse(
          secureUrl: data['secure_url'],
          publicId: data['public_id'],
        );
      } else {
        print('Cloudinary upload failed: ${response.statusCode} - $responseBody');
        return CloudinaryResponse(error: data['error']?['message'] ?? 'Upload failed');
      }
    } catch (e) {
      print('Cloudinary exception: $e');
      return CloudinaryResponse(error: e.toString());
    }
  }

  // Method BARU untuk menghapus file di Cloudinary
  Future<bool> deleteResource(String publicId, {String resourceType = 'image'}) async {
    if (_apiKey.isEmpty || _apiSecret.isEmpty) {
      print("WARNING: API Key/Secret missing. Cannot delete from Cloudinary.");
      return false;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Cloudinary signature generation
    final String paramsToSign = 'public_id=$publicId&timestamp=$timestamp';
    final List<int> bytes = utf8.encode(paramsToSign + _apiSecret);
    final String signature = sha1.convert(bytes).toString();

    final deleteUrl = 'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy';

    try {
      final response = await http.post(
        Uri.parse(deleteUrl),
        body: {
          'public_id': publicId,
          'timestamp': timestamp,
          'api_key': _apiKey,
          'signature': signature,
        },
      );

      final data = json.decode(response.body);
      if (data['result'] == 'ok') {
        print("Cloudinary: Deleted $publicId");
        return true;
      } else {
        print("Cloudinary Delete Failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Cloudinary Delete Exception: $e");
      return false;
    }
  }
}