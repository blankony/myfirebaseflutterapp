import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CloudinaryService {
  final String _cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  final String _uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';

  Future<String?> uploadFile(File file, String resourceType) async {
    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      print("ERROR: Cloudinary credentials missing.");
      return null;
    }
    
    // Construct the upload URL
    final uploadUrl = 'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload';

    try {
      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      
      // Add the file to the request
      request.files.add(
        await http.MultipartFile.fromPath(
          'file', // Field name for the file
          file.path,
          filename: file.path.split('/').last,
        ),
      );
      
      // Add the required upload preset
      request.fields['upload_preset'] = _uploadPreset;
      
      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return data['secure_url']; // Return the secure URL of the uploaded asset
      } else {
        print('Cloudinary upload failed: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      print('Cloudinary exception during upload: $e');
      return null;
    }
  }

  // Wrapper function for Image uploads (e.g., Profile Picture)
  Future<String?> uploadImage(File file) {
    return uploadFile(file, 'image');
  }

  // Wrapper function for Video uploads (and other media)
  Future<String?> uploadMedia(File file) {
    // Cloudinary can auto-detect image/video/raw, but 'auto' is safer for general posts
    return uploadFile(file, 'auto');
  }
}