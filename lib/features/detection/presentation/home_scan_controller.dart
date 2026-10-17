import 'package:flutter/foundation.dart';

/// Lets the application shell open the scanner while keeping the camera,
/// permissions, and tree assignment logic inside [HomeScreen].
class HomeScanController {
  VoidCallback? _openScan;

  void attach(VoidCallback action) => _openScan = action;

  void detach() => _openScan = null;

  void openScan() => _openScan?.call();
}
