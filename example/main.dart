import 'dart:io';
import 'dart:typed_data';

import 'package:dartface/dartface.dart';

/// Detects faces in the image path supplied on the command line.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/dartface_example.dart <image>');
    exitCode = 64;
    return;
  }

  final Uint8List encodedImage = await File(arguments.single).readAsBytes();
  final FaceDetector detector = await FaceDetector.create();
  try {
    final List<DetectedFace> faces = await detector.detectFacesFromBytes(encodedImage);
    stdout.writeln('Detected ${faces.length} face(s).');
    for (int index = 0; index < faces.length; index++) {
      final DetectedFace face = faces[index];
      stdout.writeln('#${index + 1}: ${face.boundingBox} (${(face.confidence * 100).toStringAsFixed(1)}%)');
    }
  } on DartfaceException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await detector.dispose();
  }
}
