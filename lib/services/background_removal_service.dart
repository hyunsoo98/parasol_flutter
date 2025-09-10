import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class BackgroundRemovalService {
  final FaceDetector _faceDetector;
  bool _isProcessing = false;
  
  // Background mask settings
  bool _enableBackgroundMask = true;
  Color _maskColor = Colors.black;
  
  BackgroundRemovalService() 
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableLandmarks: false,
            enableClassification: false,
            enableTracking: false,
            minFaceSize: 0.2,
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  bool get isBackgroundMaskEnabled => _enableBackgroundMask;
  Color get maskColor => _maskColor;
  
  void setMaskColor(Color color) {
    _maskColor = color;
  }
  
  void toggleBackgroundMask() {
    _enableBackgroundMask = !_enableBackgroundMask;
  }

  Future<Widget?> processFrameForBackground(CameraImage image, Size displaySize) async {
    if (_isProcessing || !_enableBackgroundMask) return null;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isNotEmpty) {
        return _createBackgroundMask(faces, displaySize);
      }
      
      return null;
    } catch (e) {
      debugPrint('Background processing error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  Widget _createBackgroundMask(List<Face> faces, Size displaySize) {
    return CustomPaint(
      painter: BackgroundMaskPainter(
        faces: faces,
        maskColor: _maskColor,
        displaySize: displaySize,
      ),
      size: displaySize,
    );
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = _concatenatePlanes(image.planes);
    
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      ),
    );
  }
  
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = <int>[];
    for (final plane in planes) {
      allBytes.addAll(plane.bytes);
    }
    return Uint8List.fromList(allBytes);
  }

  void dispose() {
    _faceDetector.close();
  }
}

class BackgroundMaskPainter extends CustomPainter {
  final List<Face> faces;
  final Color maskColor;
  final Size displaySize;

  BackgroundMaskPainter({
    required this.faces,
    required this.maskColor,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) {
      // If no faces detected, cover entire screen
      final fullMaskPaint = Paint()
        ..color = maskColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fullMaskPaint);
      return;
    }

    // Create a solid color mask that covers everything except the face area
    final backgroundPaint = Paint()
      ..color = maskColor.withValues(alpha: 0.95) // Almost opaque solid color
      ..style = PaintingStyle.fill;

    final facePaint = Paint()
      ..color = Colors.transparent
      ..blendMode = BlendMode.clear;

    // Save the canvas state
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Fill the entire area with semi-transparent black
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Cut out the face areas
    for (final face in faces) {
      final boundingBox = face.boundingBox;
      
      // Scale the bounding box to display coordinates
      final scaledBox = Rect.fromLTWH(
        boundingBox.left * (size.width / displaySize.width),
        boundingBox.top * (size.height / displaySize.height),
        boundingBox.width * (size.width / displaySize.width),
        boundingBox.height * (size.height / displaySize.height),
      );

      // Expand the face area significantly for better masking
      final expandedBox = Rect.fromCenter(
        center: scaledBox.center,
        width: scaledBox.width * 1.8,
        height: scaledBox.height * 2.2,
      );

      // Use face contours for more precise masking if available
      if (face.contours.isNotEmpty) {
        final path = Path();
        bool first = true;
        
        for (final contour in face.contours.values) {
          if (contour?.points != null) {
            for (final point in contour!.points) {
              final scaledPoint = Offset(
                point.x * (size.width / displaySize.width),
                point.y * (size.height / displaySize.height),
              );
              
              if (first) {
                path.moveTo(scaledPoint.dx, scaledPoint.dy);
                first = false;
              } else {
                path.lineTo(scaledPoint.dx, scaledPoint.dy);
              }
            }
          }
        }
        
        if (!first) {
          path.close();
          canvas.drawPath(path, facePaint);
        } else {
          // Fallback to bounding box if contours are invalid
          canvas.drawOval(expandedBox, facePaint);
        }
      } else {
        // Use oval shape for face area
        canvas.drawOval(expandedBox, facePaint);
      }
    }

    // Restore the canvas
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}