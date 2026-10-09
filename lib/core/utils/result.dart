sealed class Result<T, E extends Exception> {
  const Result();
}

class Success<T, E extends Exception> extends Result<T, E> {
  final T value;
  const Success(this.value);
}

class Failure<T, E extends Exception> extends Result<T, E> {
  final E error;
  const Failure(this.error);
}
