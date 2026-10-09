class AppConstants {
  static const String appName = 'MangoCount';
  static const String modelPath = 'assets/models/mango_yolo.tflite';
  static const String classifierModelPath = 'assets/models/mangoripe_unripe.tflite';
  static const String labelsPath = 'assets/models/labels.txt';
  
  static const int defaultInputSize = 640;
  static const double defaultConfThreshold = 0.25;
  static const double defaultIouThreshold = 0.45;
  static const int modelMaxResolution = 1920;
}
