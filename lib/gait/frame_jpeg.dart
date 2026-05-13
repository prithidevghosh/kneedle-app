import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Encode a single [CameraImage] as a JPEG so it can be attached to Gemma's
/// multimodal analysis prompt. Handles Android (YUV_420_888) and iOS
/// (BGRA8888) plane layouts, applies the camera's sensor-orientation rotation
/// so the patient appears upright, and downscales the long edge to 512 px to
/// keep vision-encoder prefill bounded (~600 tokens / frame on Gemma E2B).
///
/// Returns `null` if the input format is unrecognised; never throws on shape
/// edge-cases (capture loop must not abort on one bad frame).
Uint8List? encodeCameraImageAsJpeg(
  CameraImage image, {
  required int sensorOrientation,
  int longEdge = 512,
  int quality = 80,
}) {
  img.Image? rgb;
  if (Platform.isAndroid &&
      (image.format.group == ImageFormatGroup.yuv420 ||
          image.format.group == ImageFormatGroup.nv21)) {
    rgb = _yuv420ToImage(image);
  } else if (image.format.group == ImageFormatGroup.bgra8888) {
    rgb = _bgra8888ToImage(image);
  } else {
    return null;
  }

  // Rotate so the patient is upright. Sensor orientation reports the angle
  // the sensor is mounted relative to the device's natural orientation, which
  // is the same angle we need to rotate the raw frame by to display it
  // correctly. For most phones: back camera 90°, front camera 270°.
  if (sensorOrientation % 360 != 0) {
    rgb = img.copyRotate(rgb, angle: sensorOrientation);
  }

  // Downscale: vision encoders resample everything to 224–448 px anyway, so
  // sending 720p just burns CPU on JPEG encode and bandwidth on the prefill.
  if (rgb.width > longEdge || rgb.height > longEdge) {
    if (rgb.width >= rgb.height) {
      rgb = img.copyResize(rgb, width: longEdge);
    } else {
      rgb = img.copyResize(rgb, height: longEdge);
    }
  }

  return Uint8List.fromList(img.encodeJpg(rgb, quality: quality));
}

img.Image _bgra8888ToImage(CameraImage image) {
  final plane = image.planes.first;
  final width = image.width;
  final height = image.height;
  final out = img.Image(width: width, height: height);
  final src = plane.bytes;
  final stride = plane.bytesPerRow;
  for (var y = 0; y < height; y++) {
    final row = y * stride;
    for (var x = 0; x < width; x++) {
      final i = row + x * 4;
      final b = src[i];
      final g = src[i + 1];
      final r = src[i + 2];
      out.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return out;
}

/// Convert a YUV_420_888 [CameraImage] to an RGB [img.Image]. Handles the
/// common pixelStride==2 / interleaved-VU layout and the rarer planar
/// pixelStride==1 layout. Uses the BT.601 limited-range coefficients.
img.Image _yuv420ToImage(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;
  final yStride = yPlane.bytesPerRow;
  final uStride = uPlane.bytesPerRow;
  final vStride = vPlane.bytesPerRow;
  final uPx = uPlane.bytesPerPixel ?? 1;
  final vPx = vPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final yRow = y * yStride;
    final uvRow = (y >> 1);
    final uRowBase = uvRow * uStride;
    final vRowBase = uvRow * vStride;
    for (var x = 0; x < width; x++) {
      final uvCol = x >> 1;
      final yVal = yBytes[yRow + x] & 0xff;
      final uIdx = uRowBase + uvCol * uPx;
      final vIdx = vRowBase + uvCol * vPx;
      final uVal = (uIdx < uBytes.length ? uBytes[uIdx] & 0xff : 128) - 128;
      final vVal = (vIdx < vBytes.length ? vBytes[vIdx] & 0xff : 128) - 128;
      // BT.601 limited-range YUV→RGB, fixed-point ×1024.
      final y1192 = 1192 * (yVal - 16);
      final r = ((y1192 + 1634 * vVal) >> 10).clamp(0, 255);
      final g = ((y1192 - 833 * vVal - 400 * uVal) >> 10).clamp(0, 255);
      final b = ((y1192 + 2066 * uVal) >> 10).clamp(0, 255);
      out.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return out;
}
