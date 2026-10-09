import 'dart:math';
import 'package:flutter/foundation.dart';
import '../domain/detection.dart';
import '../domain/mango_class.dart';

class YoloPostprocessor {
  /// Parses model output and runs NMS.
  static Future<List<Detection>> process(
    List<dynamic> outputTensor, {
    required double confThreshold,
    required double iouThreshold,
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
    required int modelInputSize,
    bool classAgnostic = true,
  }) async {
    return await compute(_processTask, {
      'output': outputTensor,
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'scale': scale,
      'padX': padX,
      'padY': padY,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
      'modelInputSize': modelInputSize,
      'classAgnostic': classAgnostic,
    });
  }

  static List<Detection> processSync(
    List<dynamic> outputTensor, {
    required double confThreshold,
    required double iouThreshold,
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
    required int modelInputSize,
    bool isQuantized = false,
    double quantScale = 1.0,
    int quantZeroPoint = 0,
    bool classAgnostic = true,
  }) {
    return _processTask({
      'output': outputTensor,
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'scale': scale,
      'padX': padX,
      'padY': padY,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
      'modelInputSize': modelInputSize,
      'isQuantized': isQuantized,
      'quantScale': quantScale,
      'quantZeroPoint': quantZeroPoint,
      'classAgnostic': classAgnostic,
    });
  }

  static List<Detection> _processTask(Map<String, dynamic> args) {
    final List<dynamic> output = args['output'];
    final double confThreshold = args['confThreshold'];
    final double iouThreshold = args['iouThreshold'];
    final double scale = args['scale'];
    final int padX = args['padX'];
    final int padY = args['padY'];
    final int originalWidth = args['originalWidth'];
    final int originalHeight = args['originalHeight'];
    final int modelInputSize = args['modelInputSize'];
    final bool isQuantized = args['isQuantized'] ?? false;
    final double quantScale = args['quantScale'] ?? 1.0;
    final int quantZeroPoint = args['quantZeroPoint'] ?? 0;
    final bool classAgnostic = args['classAgnostic'] ?? true;

    if (output.isEmpty) return [];

    final tensor = output[0] as List<dynamic>; // Remove batch dim (1)
    if (tensor.isEmpty) return [];

    int rows, cols;
    rows = tensor.length;
    cols = tensor[0].length;
    bool isChannelsFirst = rows < cols;
    
    // Check for NMS-included export [1, N, 6] where N is small (e.g. <= 300)
    // and format is x1, y1, x2, y2, score, class
    if (cols == 6 && rows < 1000) {
      // Assume already post-processed by the model
      return _parseNmsIncluded(tensor, confThreshold, scale, padX, padY, originalWidth, originalHeight, modelInputSize);
    }

    double dq(dynamic val) {
      if (isQuantized) {
        return ((val as num) - quantZeroPoint) * quantScale;
      }
      return (val as num).toDouble();
    }

    // Determine if boxes are normalized
    double maxBoxVal = 0;
    if (isChannelsFirst) {
      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < cols; j++) {
           maxBoxVal = max(maxBoxVal, dq(tensor[i][j]));
        }
      }
    } else {
       for (int i = 0; i < rows; i++) {
          for (int j = 0; j < 4; j++) {
             maxBoxVal = max(maxBoxVal, dq(tensor[i][j]));
          }
       }
    }
    // If it's pixel coordinates, maxBoxVal will be close to modelInputSize (e.g. 640).
    // If it's normalized, maxBoxVal is usually 1.0, but untrained models might output
    // stray boxes with w=2.0 or 5.0. So 20.0 is a safe threshold.
    final bool isNormalized = maxBoxVal <= 20.0;

    List<Detection> rawDetections = [];
    final int numBoxes = isChannelsFirst ? cols : rows;

    double globalMaxConf = 0.0;
    for (int i = 0; i < numBoxes; i++) {
      double cx = dq(isChannelsFirst ? tensor[0][i] : tensor[i][0]);
      double cy = dq(isChannelsFirst ? tensor[1][i] : tensor[i][1]);
      double w  = dq(isChannelsFirst ? tensor[2][i] : tensor[i][2]);
      double h  = dq(isChannelsFirst ? tensor[3][i] : tensor[i][3]);

      final int numClasses = max(1, (isChannelsFirst ? rows : cols) - 4);
      int classIndex = 0;
      double confidence = 0.0;

      if (numClasses == 1) {
        confidence = dq(isChannelsFirst ? tensor[4][i] : tensor[i][4]);
        classIndex = 0;
      } else {
        for (int c = 0; c < numClasses; c++) {
          final double p = dq(isChannelsFirst ? tensor[4 + c][i] : tensor[i][4 + c]);
          if (p > confidence) {
            confidence = p;
            classIndex = c;
          }
        }
      }

      if (confidence > globalMaxConf) {
        globalMaxConf = confidence;
      }
      if (confidence < confThreshold) continue;

      if (isNormalized) {
        cx *= modelInputSize;
        cy *= modelInputSize;
        w *= modelInputSize;
        h *= modelInputSize;
      }

      // Convert cx,cy,w,h to x1,y1,x2,y2 (model size pixels)
      double modelX1 = cx - w / 2;
      double modelY1 = cy - h / 2;
      double modelX2 = cx + w / 2;
      double modelY2 = cy + h / 2;

      // Map back to original image
      double x1 = (modelX1 - padX) / scale;
      double y1 = (modelY1 - padY) / scale;
      double x2 = (modelX2 - padX) / scale;
      double y2 = (modelY2 - padY) / scale;

      // Clamp
      x1 = x1.clamp(0, originalWidth.toDouble());
      y1 = y1.clamp(0, originalHeight.toDouble());
      x2 = x2.clamp(0, originalWidth.toDouble());
      y2 = y2.clamp(0, originalHeight.toDouble());

      if (x2 > x1 && y2 > y1) {
        final bw = x2 - x1;
        final bh = y2 - y1;

        // Geometric sanity check for low-confidence candidates (< 0.45):
        // 1. Extreme aspect ratio: Mangoes are oval hanging fruits. A wide, flat box (width > 2.0 * height)
        //    or extremely thin needle (height > 3.5 * width) with low confidence is ground, horizon, or twig noise.
        // 2. Giant background hallucination: A box covering > 10% of the total image area with low confidence
        //    is an FPN P5 scale background artifact (real close-up mangoes have high confidence >= 0.70).
        if (confidence < 0.45) {
          final isAnomalousFlat = bw > bh * 2.0;
          final isAnomalousNeedle = bh > bw * 3.5;
          final totalImageArea = originalWidth * originalHeight;
          final isAnomalousGiant = totalImageArea > 0 && ((bw * bh) / totalImageArea) > 0.10;
          if (isAnomalousFlat || isAnomalousNeedle || isAnomalousGiant) {
            continue;
          }
        }

        rawDetections.add(Detection(
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          mangoClass: MangoClass.fromIndex(classIndex),
          confidence: confidence,
        ));
      }
    }

    return _nms(rawDetections, iouThreshold, classAgnostic: classAgnostic);
  }

  static List<Detection> _parseNmsIncluded(
    List<dynamic> tensor, 
    double confThreshold,
    double scale,
    int padX,
    int padY,
    int originalWidth,
    int originalHeight,
    int modelInputSize
  ) {
    List<Detection> list = [];
    bool isNormalized = false;
    double maxBoxVal = 0;
    for (int i = 0; i < tensor.length; i++) {
        for (int j = 0; j < 4; j++) {
            maxBoxVal = max(maxBoxVal, (tensor[i][j] as num).toDouble());
        }
    }
    isNormalized = maxBoxVal <= 1.5;

    for (int i = 0; i < tensor.length; i++) {
       double x1 = (tensor[i][0] as num).toDouble();
       double y1 = (tensor[i][1] as num).toDouble();
       double x2 = (tensor[i][2] as num).toDouble();
       double y2 = (tensor[i][3] as num).toDouble();
       double score = (tensor[i][4] as num).toDouble();
       int classIndex = (tensor[i][5] as num).toInt();

       if (score < confThreshold) continue;

       if (isNormalized) {
           x1 *= modelInputSize;
           y1 *= modelInputSize;
           x2 *= modelInputSize;
           y2 *= modelInputSize;
       }

       // Map back
       x1 = (x1 - padX) / scale;
       y1 = (y1 - padY) / scale;
       x2 = (x2 - padX) / scale;
       y2 = (y2 - padY) / scale;

       x1 = x1.clamp(0, originalWidth.toDouble());
       y1 = y1.clamp(0, originalHeight.toDouble());
       x2 = x2.clamp(0, originalWidth.toDouble());
       y2 = y2.clamp(0, originalHeight.toDouble());

       if (x2 > x1 && y2 > y1) {
           list.add(Detection(
             x1: x1, y1: y1, x2: x2, y2: y2,
             mangoClass: MangoClass.fromIndex(classIndex),
             confidence: score
           ));
       }
    }
    return list;
  }

  /// Global NMS (class-agnostic or per-class).
  static List<Detection> nms(
    List<Detection> boxes,
    double iouThreshold, {
    bool classAgnostic = true,
  }) {
    return _nms(boxes, iouThreshold, classAgnostic: classAgnostic);
  }

  static List<Detection> _nms(
    List<Detection> boxes,
    double iouThreshold, {
    bool classAgnostic = true,
  }) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    List<Detection> result = [];
    
    for (int i = 0; i < boxes.length; i++) {
      bool keep = true;
      for (int j = 0; j < result.length; j++) {
        // If class-agnostic (default true), merge overlapping duplicates across classes
        if (classAgnostic || boxes[i].mangoClass == result[j].mangoClass) {
          double iou = _calculateIou(boxes[i], result[j]);
          if (iou > iouThreshold) {
            keep = false;
            break;
          }
        }
      }
      if (keep) {
        result.add(boxes[i]);
      }
    }
    return result;
  }

  static double _calculateIou(Detection a, Detection b) {
    double interX1 = max(a.x1, b.x1);
    double interY1 = max(a.y1, b.y1);
    double interX2 = min(a.x2, b.x2);
    double interY2 = min(a.y2, b.y2);

    if (interX2 <= interX1 || interY2 <= interY1) return 0.0;

    double interArea = (interX2 - interX1) * (interY2 - interY1);
    double aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
    double bArea = (b.x2 - b.x1) * (b.y2 - b.y1);

    return interArea / (aArea + bArea - interArea);
  }
}
