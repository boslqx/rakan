import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Handles the profile-picture pipeline: pick -> crop -> compress -> base64-encode
class ProfilePictureService {
  final ImagePicker _picker = ImagePicker();

  /// Runs pick -> crop -> compress and returns the final JPEG bytes
  Future<Uint8List?> pickCropAndCompress() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90, // light pre-compression from the OS picker itself
    );
    if (picked == null) return null;

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Photo',
          toolbarColor: const Color(0xFF0C0E10),
          toolbarWidgetColor: const Color(0xFFE8E8E9),
          statusBarColor: const Color(0xFF0C0E10),
          backgroundColor: const Color(0xFF0C0E10),
          activeControlsWidgetColor: const Color(0xFFC6C6C7),
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Adjust Photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return null;

    // Compressed tighter than a Storage-hosted image would need to be
    final compressed = await FlutterImageCompress.compressWithFile(
      cropped.path,
      minWidth: 384,
      minHeight: 384,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    return compressed;
  }

  /// Base64-encodes compressed JPEG bytes for Firestore storage.
  String encodeToBase64(Uint8List bytes) => base64Encode(bytes);
}