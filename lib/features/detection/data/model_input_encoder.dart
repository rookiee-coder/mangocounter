import 'dart:typed_data';

/// Encodes normalized model values using the tensor's actual quantization.
class ModelInputEncoder {
  static List<num> encode(
    Float32List values, {
    required String type,
    double scale = 1,
    int zeroPoint = 0,
  }) {
    if (type == 'float32') return values;
    if (type != 'int8' && type != 'uint8') {
      throw ArgumentError('Unsupported model input type: $type');
    }
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError('Quantized input requires a positive scale');
    }
    final signed = type == 'int8';
    final List<int> result =
        signed ? Int8List(values.length) : Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      result[i] = ((values[i] / scale).round() + zeroPoint)
          .clamp(signed ? -128 : 0, signed ? 127 : 255);
    }
    return result;
  }
}
