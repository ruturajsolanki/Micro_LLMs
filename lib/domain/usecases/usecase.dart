import '../../core/utils/result.dart';

/// Base class for use cases.
/// 
/// Use cases encapsulate a single piece of business logic. They:
/// 1. Take typed parameters
/// 2. Return a Result (success or failure)
/// 3. Are independent of UI and data layer details
/// 
/// Generic Parameters:
/// - [Type]: The success return type
/// - [Params]: The parameter type (use [NoParams] for parameterless use cases)
abstract class UseCase<Type, Params> {
  /// Execute the use case with the given parameters.
  AsyncResult<Type> call(Params params);
}

/// Use case that returns a stream instead of a single value.
/// 
/// Used for:
/// - Streaming LLM responses
/// - Real-time data updates
/// - Progress tracking
abstract class StreamUseCase<Type, Params> {
  /// Execute the use case and return a stream of results.
  Stream<Type> call(Params params);
}

/// Marker class for use cases that don't require parameters.
class NoParams {
  const NoParams();
}
