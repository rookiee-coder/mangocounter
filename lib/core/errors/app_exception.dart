class AppException implements Exception {
  final String message;
  final dynamic originalError;

  AppException(this.message, [this.originalError]);

  @override
  String toString() => 'AppException: $message\n${originalError ?? ''}'.trim();
}

class ModelFormatException extends AppException {
  ModelFormatException(super.message, [super.originalError]);
}
