import 'package:dartz/dartz.dart';
import '../error/failures.dart';

/// Type alias for Either<Failure, T>.
/// 
/// This provides a cleaner API for domain layer operations that can fail.
/// Left represents failure, Right represents success.
/// 
/// Example:
/// ```dart
/// Result<User> getUser(String id) async {
///   try {
///     return Right(await _dataSource.fetchUser(id));
///   } catch (e) {
///     return Left(ServerFailure(message: e.toString()));
///   }
/// }
/// ```
typedef Result<T> = Either<Failure, T>;

/// Type alias for async operations that return Result.
typedef AsyncResult<T> = Future<Result<T>>;

/// Extension methods for working with Result types.
extension ResultExtensions<T> on Result<T> {
  /// Execute callback on success, return original result.
  Result<T> onSuccess(void Function(T value) callback) {
    fold((_) {}, callback);
    return this;
  }
  
  /// Execute callback on failure, return original result.
  Result<T> onFailure(void Function(Failure failure) callback) {
    fold(callback, (_) {});
    return this;
  }
  
  /// Get value or throw the failure.
  /// Use sparingly - prefer fold() for explicit error handling.
  T getOrThrow() {
    return fold(
      (failure) => throw StateError('Result was failure: ${failure.message}'),
      (value) => value,
    );
  }
  
  /// Get value or return default.
  T getOrElse(T defaultValue) {
    return fold((_) => defaultValue, (value) => value);
  }
  
  /// Get value or compute default from failure.
  T getOrElseCompute(T Function(Failure failure) compute) {
    return fold(compute, (value) => value);
  }
  
  /// Transform success value.
  Result<U> mapSuccess<U>(U Function(T value) transform) {
    return fold(
      (failure) => Left(failure),
      (value) => Right(transform(value)),
    );
  }
  
  /// Transform to different failure type.
  Result<T> mapFailure(Failure Function(Failure failure) transform) {
    return fold(
      (failure) => Left(transform(failure)),
      (value) => Right(value),
    );
  }
  
  /// Returns true if this is a success (Right).
  bool get isSuccess => isRight();
  
  /// Returns true if this is a failure (Left).
  bool get isFailure => isLeft();
  
  /// Get failure if present, null otherwise.
  Failure? get failureOrNull => fold((f) => f, (_) => null);
  
  /// Get success value if present, null otherwise.
  T? get successOrNull => fold((_) => null, (v) => v);
}

/// Extension for chaining async results.
extension AsyncResultExtensions<T> on AsyncResult<T> {
  /// Chain another async operation on success.
  AsyncResult<U> flatMapAsync<U>(AsyncResult<U> Function(T value) transform) async {
    final result = await this;
    return result.fold(
      (failure) async => Left(failure),
      (value) => transform(value),
    );
  }
  
  /// Transform success value asynchronously.
  AsyncResult<U> mapAsync<U>(Future<U> Function(T value) transform) async {
    final result = await this;
    return result.fold(
      (failure) => Left(failure),
      (value) async => Right(await transform(value)),
    );
  }
}

/// Helper functions for creating Results.
class Results {
  Results._();
  
  /// Create a success result.
  static Result<T> success<T>(T value) => Right(value);
  
  /// Create a failure result.
  static Result<T> failure<T>(Failure failure) => Left(failure);
  
  /// Run a function and catch exceptions, converting to Result.
  static AsyncResult<T> guard<T>(Future<T> Function() fn) async {
    try {
      return Right(await fn());
    } catch (e, stackTrace) {
      return Left(StorageFailure(
        message: e.toString(),
        stackTrace: stackTrace,
      ));
    }
  }
}
