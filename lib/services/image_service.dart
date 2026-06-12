import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickFromCamera() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (xfile == null) return null;
    final cropped = await _cropImage(xfile.path);
    return _persistFile(cropped ?? xfile.path);
  }

  Future<List<String>> pickFromGallery() async {
    final xfiles = await _picker.pickMultiImage();
    if (xfiles.isEmpty) return [];
    final results = <String>[];
    for (final xfile in xfiles) {
      results.add(await _persistFile(xfile.path));
    }
    return results;
  }

  Future<String?> _cropImage(String sourcePath) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '框选区域',
            toolbarColor: Color(0xFF5A328C),
            toolbarWidgetColor: Color(0xFFFFFFFF),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            cropStyle: CropStyle.rectangle,
            activeControlsWidgetColor: Color(0xFF5A328C),
            cropFrameStrokeWidth: 2,
            cropGridStrokeWidth: 1,
          ),
          IOSUiSettings(
            title: '框选区域',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            cropStyle: CropStyle.rectangle,
          ),
        ],
      );
      return cropped?.path;
    } catch (e) {
      debugPrint('Crop failed: $e');
      return null;
    }
  }

  Future<String> _persistFile(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(dir.path, 'images'));
    if (!await imgDir.exists()) await imgDir.create(recursive: true);
    final ext = p.extension(sourcePath);
    final target = p.join(imgDir.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(target);
    return target;
  }
}
