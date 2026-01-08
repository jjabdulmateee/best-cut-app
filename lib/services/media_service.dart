import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  /// Pick an image from gallery or camera
  Future<File?> pickImage({bool fromGallery = true}) async {
    final XFile? image = await _picker.pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 70, // Compress for faster upload
      maxWidth: 1000,
    );
    
    if (image != null) {
      return File(image.path);
    }
    return null;
  }

  /// Upload image to Firebase Storage and return the URL
  Future<String?> uploadImage({
    required File file,
    required String path, // e.g., 'barbers/userId/profile.jpg'
  }) async {
    try {
      final ref = _storage.ref().child(path);
      
      // For web support, we'd need to use putData or putBlob
      // This implementation handles mobile.
      UploadTask uploadTask = ref.putFile(file);
      
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  /// Delete an image from storage
  Future<void> deleteImage(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }
}

