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
import '../domain/mango_class.dart';
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
  final Uint8List? classifierBytes;
  _InitRequest(this.replyPort, this.modelBytes, this.classifierBytes);
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
    final Uint8List modelBytes = modelData.buffer.asUint8List();

    Uint8List? classifierBytes;
    try {
      final ByteData classifierData = await rootBundle.load(AppConstants.classifierModelPath);
      classifierBytes = classifierData.buffer.asUint8List();
    } catch (_) {}

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);

    final broadcastPort = receivePort.asBroadcastStream();
    _sendPort = await broadcastPort.first as SendPort;

    final initReplyPort = ReceivePort();
    _sendPort!.send(_InitRequest(initReplyPort.sendPort, modelBytes, classifierBytes));
    final initResult = await initReplyPort.first;
    
    if (initResult is Exception) {
      throw initResult;
    }
    
    _isInitialized = true;
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
    
    final result = await replyPort.first;
    if (result is Exception) {
      throw result;
    }
    return result as DetectionResult;
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _isInitialized = false;
  }

  // --- ISOLATE CODE ---

  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    Interpreter? interpreter;
    Interpreter? classifierInterpreter;
    int modelInputSize = AppConstants.defaultInputSize;
    int classifierInputSize = 224;
    TensorType inputType = TensorType.float32;
    List<int> outputShape = [];
    // true when the model expects channels-first input [1, 3, H, W]
    // (newer Ultralytics TFLite exports), false for [1, H, W, 3].
    bool isNchw = false;

    receivePort.listen((message) async {
      if (message is _InitRequest) {
        try {
          final options = InterpreterOptions()..threads = 4;
          interpreter = Interpreter.fromBuffer(message.modelBytes, options: options);
          
          final inputTensors = interpreter!.getInputTensors();
          final outputTensors = interpreter!.getOutputTensors();
          
          if (inputTensors.isEmpty || outputTensors.isEmpty) {
            throw ModelFormatException('Model has no inputs or outputs');
          }
          
          final inShape = inputTensors.first.shape;
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
          
          if (message.classifierBytes != null) {
            classifierInterpreter = Interpreter.fromBuffer(message.classifierBytes!, options: options);
            final classInputs = classifierInterpreter!.getInputTensors();
            if (classInputs.isNotEmpty && classInputs.first.shape.length == 4) {
               final shape = classInputs.first.shape;
               classifierInputSize = shape[1] > 3 ? shape[1] : shape[2];
            } else {
               classifierInputSize = 224;
            }
          }

          // Warm up the interpreter so first inference has no allocation delay
          final inputShape = isNchw
              ? [1, 3, modelInputSize, modelInputSize]
              : [1, modelInputSize, modelInputSize, 3];
          final warmupInput = Float32List(1 * 3 * modelInputSize * modelInputSize);
          var warmupOutput = List.generate(outputShape[0], (_) {
             if (outputShape.length == 3) {
                 return List.generate(outputShape[1], (_) => List.filled(outputShape[2], 0.0));
             } else if (outputShape.length == 2) {
                 return List.filled(outputShape[1], 0.0);
             }
             return [];
          });
          interpreter!.run(warmupInput.reshape(inputShape), warmupOutput);

          message.replyPort.send(true); // Success
        } catch (e) {
          message.replyPort.send(AppException('Failed to load model: $e'));
        }
      } else if (message is _InferenceRequest) {
        if (interpreter == null) {
          message.replyPort.send(AppException('Interpreter not loaded in isolate'));
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

          final preprocessTime = DateTime.now().millisecondsSinceEpoch - totalStart;

          // Inference & Tiling
          final inferStart = DateTime.now().millisecondsSinceEpoch;

          final outTensor = interpreter!.getOutputTensor(0);
          final isQuantizedYolo = outTensor.type == TensorType.uint8 || outTensor.type == TensorType.int8;
          final double yoloScale = isQuantizedYolo ? outTensor.params.scale : 1.0;
          final int yoloZeroPoint = isQuantizedYolo ? outTensor.params.zeroPoint : 0;

          List<dynamic> lastOutDynamic = [];
          List<Detection> runInference(img.Image imgPart, int offsetX, int offsetY) {
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
            final img.Image padded = img.Image(width: modelInputSize, height: modelInputSize);
            img.fill(padded, color: img.ColorInt8.rgb(114, 114, 114));
            img.compositeImage(padded, resized, dstX: padX, dstY: padY);

            final bool normalize = inputType == TensorType.float32;
            final double div = normalize ? 255.0 : 1.0;
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
                   return List.generate(outputShape[1], (_) => List.filled(outputShape[2], 0.0));
               } else if (outputShape.length == 2) {
                   return List.filled(outputShape[1], 0.0);
               }
               return [];
            });

            final inputShape = isNchw
                ? [1, 3, modelInputSize, modelInputSize]
                : [1, modelInputSize, modelInputSize, 3];
            interpreter!.run(inputTensor.reshape(inputShape), outputBuffer);

            final List<dynamic> outDynamic = outputBuffer;
            lastOutDynamic = outDynamic;
            final dets = YoloPostprocessor.processSync(
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
            );

            if (offsetX != 0 || offsetY != 0) {
              return dets.map((d) => d.copyWith(
                x1: (d.x1 + offsetX).clamp(0.0, origW.toDouble()),
                y1: (d.y1 + offsetY).clamp(0.0, origH.toDouble()),
                x2: (d.x2 + offsetX).clamp(0.0, origW.toDouble()),
                y2: (d.y2 + offsetY).clamp(0.0, origH.toDouble()),
              )).toList();
            }
            return dets;
          }

          final List<Detection> allCandidates = [];
          // 1. Full image inference
          allCandidates.addAll(runInference(decoded, 0, 0));

          // 2. Optional tiled inference for high aspect ratio (> 1.5) with ~20% overlap
          final double aspect = origW > origH ? origW / origH : origH / origW;
          if (message.enableTiling && aspect > 1.5) {
            if (origH > origW) {
              // Tall portrait: 2 overlapping vertical slices
              final int tileH = (origH * 0.60).round();
              final int step = (origH * 0.40).round();

              final topTile = img.copyCrop(decoded, x: 0, y: 0, width: origW, height: tileH);
              allCandidates.addAll(runInference(topTile, 0, 0));

              final botTile = img.copyCrop(decoded, x: 0, y: step, width: origW, height: origH - step);
              allCandidates.addAll(runInference(botTile, 0, step));
            } else {
              // Wide landscape: 2 overlapping horizontal slices
              final int tileW = (origW * 0.60).round();
              final int step = (origW * 0.40).round();

              final leftTile = img.copyCrop(decoded, x: 0, y: 0, width: tileW, height: origH);
              allCandidates.addAll(runInference(leftTile, 0, 0));

              final rightTile = img.copyCrop(decoded, x: step, y: 0, width: origW - step, height: origH);
              allCandidates.addAll(runInference(rightTile, step, 0));
            }
          }

          // Global class-agnostic NMS
          final detections = YoloPostprocessor.nms(allCandidates, message.iouThreshold, classAgnostic: true);
          final inferTime = DateTime.now().millisecondsSinceEpoch - inferStart;

          // 3. Postprocess
          final postStart = DateTime.now().millisecondsSinceEpoch;
          
          List<Detection> finalDetections = detections;
          final int yoloClassCount = (outputShape.length == 3 ? (outputShape[1] < outputShape[2] ? outputShape[1] : outputShape[2]) : 5) - 4;
          if (classifierInterpreter != null && detections.isNotEmpty && yoloClassCount <= 1) {
             finalDetections = [];
             for (var det in detections) {
                int x = det.x1.toInt().clamp(0, origW - 1);
                int y = det.y1.toInt().clamp(0, origH - 1);
                int w = (det.x2 - det.x1).toInt();
                int h = (det.y2 - det.y1).toInt();
                
                if (x + w > origW) w = origW - x;
                if (y + h > origH) h = origH - y;
                
                if (w > 0 && h > 0) {
                   img.Image crop = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
                   img.Image resized = img.copyResize(crop, width: classifierInputSize, height: classifierInputSize);
                   
                   final classInputType = classifierInterpreter!.getInputTensors().first.type;
                   final classOutputType = classifierInterpreter!.getOutputTensors().first.type;
                   final isQuantizedInput = classInputType == TensorType.uint8 || classInputType == TensorType.int8;
                   
                   dynamic inputTensor = isQuantizedInput ? Uint8List(1 * classifierInputSize * classifierInputSize * 3) : Float32List(1 * classifierInputSize * classifierInputSize * 3);
                   int bufferIndex = 0;
                   for (int cy = 0; cy < classifierInputSize; cy++) {
                     for (int cx = 0; cx < classifierInputSize; cx++) {
                       final img.Pixel pixel = resized.getPixel(cx, cy);
                       if (isQuantizedInput) {
                          inputTensor[bufferIndex++] = pixel.r.toInt();
                          inputTensor[bufferIndex++] = pixel.g.toInt();
                          inputTensor[bufferIndex++] = pixel.b.toInt();
                       } else {
                          inputTensor[bufferIndex++] = pixel.r / 127.5 - 1.0;
                          inputTensor[bufferIndex++] = pixel.g / 127.5 - 1.0;
                          inputTensor[bufferIndex++] = pixel.b / 127.5 - 1.0;
                       }
                     }
                   }
                   
                   final isQuantizedOutput = classOutputType == TensorType.uint8 || classOutputType == TensorType.int8;
                   
                   final classOutShape = classifierInterpreter!.getOutputTensors().first.shape;
                   final numClasses = classOutShape.length > 1 ? classOutShape[1] : 2;
                   
                   if (isQuantizedOutput) {
                      var outBuffer = List.generate(1, (_) => List.filled(numClasses, 0));
                      classifierInterpreter!.run(
                          isQuantizedInput ? (inputTensor as Uint8List).buffer.asUint8List().reshape([1, classifierInputSize, classifierInputSize, 3]) 
                                           : (inputTensor as Float32List).buffer.asFloat32List().reshape([1, classifierInputSize, classifierInputSize, 3]),
                          outBuffer
                      );
                      MangoClass finalClass = MangoClass.unripe;
                      if (numClasses == 3) {
                          int ripeProb = outBuffer[0][0];
                          int halfProb = outBuffer[0][1];
                          int unripeProb = outBuffer[0][2];
                          if (halfProb >= ripeProb && halfProb >= unripeProb) {
                            finalClass = MangoClass.over_ripe;
                          } else if (ripeProb >= halfProb && ripeProb >= unripeProb) {
                            finalClass = MangoClass.ripe;
                          }
                      } else {
                          int ripeProb = outBuffer[0][0];
                          int unripeProb = outBuffer[0][1];
                          finalClass = ripeProb >= unripeProb ? MangoClass.ripe : MangoClass.unripe;
                      }
                      finalDetections.add(det.copyWith(mangoClass: finalClass));
                   } else {
                      var outBuffer = List.generate(1, (_) => List.filled(numClasses, 0.0));
                      classifierInterpreter!.run(
                          isQuantizedInput ? (inputTensor as Uint8List).buffer.asUint8List().reshape([1, classifierInputSize, classifierInputSize, 3]) 
                                           : (inputTensor as Float32List).buffer.asFloat32List().reshape([1, classifierInputSize, classifierInputSize, 3]),
                          outBuffer
                      );
                      MangoClass finalClass = MangoClass.unripe;
                      if (numClasses == 3) {
                          double ripeProb = outBuffer[0][0];
                          double halfProb = outBuffer[0][1];
                          double unripeProb = outBuffer[0][2];
                          if (halfProb >= ripeProb && halfProb >= unripeProb) {
                            finalClass = MangoClass.over_ripe;
                          } else if (ripeProb >= halfProb && ripeProb >= unripeProb) {
                            finalClass = MangoClass.ripe;
                          }
                      } else {
                          double ripeProb = outBuffer[0][0];
                          double unripeProb = outBuffer[0][1];
                          finalClass = ripeProb >= unripeProb ? MangoClass.ripe : MangoClass.unripe;
                      }
                      finalDetections.add(det.copyWith(mangoClass: finalClass));
                   }
                } else {
                   finalDetections.add(det);
                }
             }
          }

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
