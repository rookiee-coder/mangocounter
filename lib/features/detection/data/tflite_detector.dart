import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/detection.dart';
import '../domain/detection_result.dart';
import '../domain/detector.dart';
import 'inference_tiles.dart';
import 'model_input_encoder.dart';
import 'yolo_postprocessor.dart';

class _InferenceRequest {
  final SendPort replyPort;
  final Uint8List imageBytes;
  final double confThreshold;
  final double iouThreshold;
  final bool enableTiling;

  _InferenceRequest(
    this.replyPort,
    this.imageBytes,
    this.confThreshold,
    this.iouThreshold, {
    this.enableTiling = true,
  });
}

class _InitRequest {
  final SendPort replyPort;
  final Uint8List modelBytes;

  _InitRequest(this.replyPort, this.modelBytes);
}

class TfliteDetector implements Detector {
  Isolate? _isolate;
  SendPort? _sendPort;
  bool _isInitialized = false;

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    // Load model from rootBundle
    final ByteData modelData = await rootBundle.load(AppConstants.modelPath);
    final Uint8List modelBytes = modelData.buffer
        .asUint8List(modelData.offsetInBytes, modelData.lengthInBytes);
    final labels = (await rootBundle.loadString(AppConstants.labelsPath))
        .trim()
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim().toLowerCase())
        .toList();
    if (labels.join(',') != 'over ripe,ripe,unripe') {
      throw ModelFormatException('Expected labels: Over ripe, Ripe, Unripe');
    }

    final receivePort = ReceivePort();
    final initReplyPort = ReceivePort();
    try {
      _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
      _sendPort = await receivePort.first.timeout(const Duration(seconds: 30))
          as SendPort;
      _sendPort!.send(_InitRequest(initReplyPort.sendPort, modelBytes));
      final initResult =
          await initReplyPort.first.timeout(const Duration(seconds: 60));
      if (initResult is Exception) throw initResult;
      _isInitialized = true;
    } catch (_) {
      dispose();
      rethrow;
    } finally {
      receivePort.close();
      initReplyPort.close();
    }
  }

  @override
  Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double confThreshold = 0.40,
    double iouThreshold = 0.45,
    bool enableTiling = true,
  }) async {
    if (!_isInitialized || _sendPort == null) {
      throw AppException('Detector not initialized');
    }

    final replyPort = ReceivePort();
    _sendPort!.send(_InferenceRequest(
      replyPort.sendPort,
      imageBytes,
      confThreshold,
      iouThreshold,
      enableTiling: enableTiling,
    ));

    try {
      final result = await replyPort.first.timeout(const Duration(minutes: 2));
      if (result is Exception) throw result;
      return result as DetectionResult;
    } finally {
      replyPort.close();
    }
  }

  @override
  void dispose() {
    if (_sendPort != null) {
      // Let an in-flight native invocation finish before releasing its tensors.
      _sendPort!.send(null);
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _isolate = null;
    _sendPort = null;
    _isInitialized = false;
  }

  // --- ISOLATE CODE ---

  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    Interpreter? interpreter;

    int modelInputSize = AppConstants.defaultInputSize;

    TensorType inputType = TensorType.float32;
    List<int> outputShape = [];
    // true when the model expects channels-first input [1, 3, H, W]
    // (newer Ultralytics TFLite exports), false for [1, H, W, 3].
    bool isNchw = false;

    receivePort.listen((message) async {
      if (message == null) {
        interpreter?.close();
        receivePort.close();
        return;
      } else if (message is _InitRequest) {
        try {
          final options = InterpreterOptions()..threads = 4;
          interpreter =
              Interpreter.fromBuffer(message.modelBytes, options: options);

          final inputTensors = interpreter!.getInputTensors();
          final outputTensors = interpreter!.getOutputTensors();

          if (inputTensors.isEmpty || outputTensors.isEmpty) {
            throw ModelFormatException('Model has no inputs or outputs');
          }

          final inShape = inputTensors.first.shape;
          if (inputTensors.length != 1 ||
              outputTensors.length != 1 ||
              inShape.length != 4 ||
              inShape[0] != 1 ||
              !((inShape[1] == 3 && inShape[2] == inShape[3]) ||
                  (inShape[3] == 3 && inShape[1] == inShape[2]))) {
            throw ModelFormatException(
                'Expected one square RGB input and one raw YOLO output');
          }
          if (inShape.length == 4) {
            if (inShape[1] == 3 && inShape[3] != 3) {
              // NCHW: [1, 3, H, W]
              isNchw = true;
              modelInputSize = inShape[2]; // assuming square H=W
            } else {
              // NHWC: [1, H, W, 3]
              isNchw = false;
              modelInputSize = inShape[1]; // assuming square H=W
            }
          }
          inputType = inputTensors.first.type;
          outputShape = outputTensors.first.shape;
          if (outputShape.length != 3 ||
              outputShape[0] != 1 ||
              !(outputShape[1] == 7 || outputShape[2] == 7)) {
            throw ModelFormatException(
                'Expected raw YOLO output with 3 ripeness classes; export with nms=False');
          }
          if (![TensorType.float32, TensorType.int8, TensorType.uint8]
              .contains(outputTensors.first.type)) {
            throw ModelFormatException('Unsupported YOLO output type');
          }

          // Warm up the interpreter so first inference has no allocation delay
          final inputShape = isNchw
              ? [1, 3, modelInputSize, modelInputSize]
              : [1, modelInputSize, modelInputSize, 3];
          final warmupInput =
              Float32List(1 * 3 * modelInputSize * modelInputSize);
          var warmupOutput = List.generate(outputShape[0], (_) {
            if (outputShape.length == 3) {
              return List.generate(
                  outputShape[1], (_) => List<num>.filled(outputShape[2], 0));
            } else if (outputShape.length == 2) {
              return List.filled(outputShape[1], 0.0);
            }
            return [];
          });
          final warmupTensor = inputTensors.first;
          final warmupEncoded = ModelInputEncoder.encode(warmupInput,
              type: inputType.name,
              scale: warmupTensor.params.scale,
              zeroPoint: warmupTensor.params.zeroPoint);
          interpreter!.run(warmupEncoded.reshape(inputShape), warmupOutput);

          message.replyPort.send(true); // Success
        } catch (e) {
          message.replyPort.send(AppException('Failed to load model: $e'));
        }
      } else if (message is _InferenceRequest) {
        if (interpreter == null) {
          message.replyPort
              .send(AppException('Interpreter not loaded in isolate'));
          return;
        }

        try {
          final totalStart = DateTime.now().millisecondsSinceEpoch;

          // 1. Decode & Preprocess
          img.Image? decoded = img.decodeImage(message.imageBytes);
          if (decoded == null) throw AppException('Image decode failed');
          decoded = img.bakeOrientation(decoded);

          final int origW = decoded.width;
          final int origH = decoded.height;

          final preprocessTime =
              DateTime.now().millisecondsSinceEpoch - totalStart;

          // Inference & Tiling
          final inferStart = DateTime.now().millisecondsSinceEpoch;

          final outTensor = interpreter!.getOutputTensor(0);
          final isQuantizedYolo = outTensor.type == TensorType.uint8 ||
              outTensor.type == TensorType.int8;
          final double yoloScale =
              isQuantizedYolo ? outTensor.params.scale : 1.0;
          final int yoloZeroPoint =
              isQuantizedYolo ? outTensor.params.zeroPoint : 0;

          List<dynamic> lastOutDynamic = [];
          List<Detection> runInference(
              img.Image imgPart, int offsetX, int offsetY) {
            final int w = imgPart.width;
            final int h = imgPart.height;

            // Letterbox (pad with 114, 114, 114)
            final double scale = modelInputSize / (w > h ? w : h);
            final int newW = (w * scale).round();
            final int newH = (h * scale).round();
            final int padX = (modelInputSize - newW) ~/ 2;
            final int padY = (modelInputSize - newH) ~/ 2;

            final img.Image resized = img.copyResize(
              imgPart,
              width: newW,
              height: newH,
              interpolation: img.Interpolation.linear,
            );
            final img.Image padded =
                img.Image(width: modelInputSize, height: modelInputSize);
            img.fill(padded, color: img.ColorInt8.rgb(114, 114, 114));
            img.compositeImage(padded, resized, dstX: padX, dstY: padY);

            // YOLO expects real RGB values in [0, 1], including quantized exports.
            const double div = 255.0;
            final int plane = modelInputSize * modelInputSize;
            final inputTensor = Float32List(plane * 3);
            int bufferIndex = 0;
            for (int y = 0; y < modelInputSize; y++) {
              for (int x = 0; x < modelInputSize; x++) {
                final img.Pixel pixel = padded.getPixel(x, y);
                if (isNchw) {
                  final int idx = y * modelInputSize + x;
                  inputTensor[idx] = pixel.r / div;
                  inputTensor[plane + idx] = pixel.g / div;
                  inputTensor[2 * plane + idx] = pixel.b / div;
                } else {
                  inputTensor[bufferIndex++] = pixel.r / div;
                  inputTensor[bufferIndex++] = pixel.g / div;
                  inputTensor[bufferIndex++] = pixel.b / div;
                }
              }
            }

            var outputBuffer = List.generate(outputShape[0], (_) {
              if (outputShape.length == 3) {
                return List.generate(
                    outputShape[1], (_) => List<num>.filled(outputShape[2], 0));
              } else if (outputShape.length == 2) {
                return List.filled(outputShape[1], 0.0);
              }
              return [];
            });

            final inputShape = isNchw
                ? [1, 3, modelInputSize, modelInputSize]
                : [1, modelInputSize, modelInputSize, 3];
            final tensor = interpreter!.getInputTensor(0);
            final encoded = ModelInputEncoder.encode(inputTensor,
                type: inputType.name,
                scale: tensor.params.scale,
                zeroPoint: tensor.params.zeroPoint);
            interpreter!.run(encoded.reshape(inputShape), outputBuffer);

            final List<dynamic> outDynamic = outputBuffer;
            lastOutDynamic = outDynamic;
            final parsed = YoloPostprocessor.processSync(
              outDynamic,
              confThreshold: message.confThreshold,
              iouThreshold: message.iouThreshold,
              scale: scale,
              padX: padX,
              padY: padY,
              originalWidth: w,
              originalHeight: h,
              modelInputSize: modelInputSize,
              isQuantized: isQuantizedYolo,
              quantScale: yoloScale,
              quantZeroPoint: yoloZeroPoint,
              classAgnostic: true,
              boxesNormalized: true,
            );
            // A fruit clipped by an internal crop edge is seen completely in
            // an overlapping crop or the full frame. Avoid counting fragments.
            final dets = parsed
                .where((d) =>
                    !(offsetX > 0 && d.x1 <= 1) &&
                    !(offsetY > 0 && d.y1 <= 1) &&
                    !(offsetX + w < origW && d.x2 >= w - 1) &&
                    !(offsetY + h < origH && d.y2 >= h - 1))
                .toList();

            if (offsetX != 0 || offsetY != 0) {
              return dets
                  .map((d) => d.copyWith(
                        x1: (d.x1 + offsetX).clamp(0.0, origW.toDouble()),
                        y1: (d.y1 + offsetY).clamp(0.0, origH.toDouble()),
                        x2: (d.x2 + offsetX).clamp(0.0, origW.toDouble()),
                        y2: (d.y2 + offsetY).clamp(0.0, origH.toDouble()),
                      ))
                  .toList();
            }
            return dets;
          }

          final List<Detection> allCandidates = [];
          // 1. Full image inference
          allCandidates.addAll(runInference(decoded, 0, 0));

          // 2. Bounded overlapping detail crops for all image aspect ratios.
          if (message.enableTiling) {
            for (final tile
                in InferenceTile.plan(origW, origH, modelInputSize)) {
              final crop = img.copyCrop(decoded,
                  x: tile.x, y: tile.y, width: tile.width, height: tile.height);
              allCandidates.addAll(runInference(crop, tile.x, tile.y));
            }
          }

          // Global class-agnostic NMS
          final detections = YoloPostprocessor.nms(
              allCandidates, message.iouThreshold,
              classAgnostic: true);
          final inferTime = DateTime.now().millisecondsSinceEpoch - inferStart;

          // 3. Postprocess
          final postStart = DateTime.now().millisecondsSinceEpoch;

          List<Detection> finalDetections = detections;
          final postTime = DateTime.now().millisecondsSinceEpoch - postStart;

          String dbg = 'shape: $outputShape';
          if (lastOutDynamic.isNotEmpty) {
            final t = lastOutDynamic[0];
            if (t is List) {
              dbg += ', r:${t.length}';
              if (t.isNotEmpty && t[0] is List) {
                dbg += ' c:${t[0].length}';
                if (t[0].isNotEmpty) {
                  dbg += ' v[0][0]:${t[0][0]}';
                }

                // Quick scan for max confidence
                try {
                  double maxC = 0.0;
                  if (t.length > 4) {
                    for (int i = 0; i < t[0].length; i++) {
                      double c = (t[4][i] as num).toDouble();
                      if (c > maxC) maxC = c;
                    }
                  } else if (t.isNotEmpty && t[0].length > 4) {
                    for (int i = 0; i < t.length; i++) {
                      double c = (t[i][4] as num).toDouble();
                      if (c > maxC) maxC = c;
                    }
                  }
                  dbg += ' maxC:${maxC.toStringAsFixed(3)}';
                } catch (_) {}
              }
            }
          }
          if (isQuantizedYolo) {
            dbg += ', INT8(s:$yoloScale z:$yoloZeroPoint)';
          } else {
            dbg += ', F32';
          }

          final result = DetectionResult(
            detections: finalDetections,
            imageWidth: origW,
            imageHeight: origH,
            inferenceTimeMs: inferTime,
            preprocessTimeMs: preprocessTime,
            postprocessTimeMs: postTime,
            confThreshold: message.confThreshold,
            iouThreshold: message.iouThreshold,
            modelInputSize: modelInputSize,
            debugString: dbg,
          );

          message.replyPort.send(result);
        } catch (e) {
          message.replyPort.send(AppException('Inference error: $e'));
        }
      }
    });
  }
}
