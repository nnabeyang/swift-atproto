import Foundation

/// A single-pass, pull-driven XRPC response body.
///
/// The underlying transport is asked for another byte chunk only when the
/// consumer advances the async iterator. Call ``cancel()`` when abandoning a
/// body before reaching its end.
public final class XRPCBody: AsyncSequence, @unchecked Sendable {
  /// A byte chunk produced by the transport.
  public typealias Element = ArraySlice<UInt8>

  /// The total body length reported by the transport.
  public enum Length: Hashable, Sendable {
    case unknown
    case known(Int64)
  }

  /// The total body length, if known before iteration begins.
  public let length: Length

  private let makeIteratorClosure: @Sendable () -> Iterator
  private let state: State

  /// Wraps a transport-provided async sequence of byte chunks.
  ///
  /// - Parameters:
  ///   - chunks: A pull-driven sequence supplied by the transport.
  ///   - length: The response length, if known.
  ///   - onCancel: Called at most once when iteration is cancelled or the
  ///     consumer explicitly cancels the body.
  public init<Chunks: AsyncSequence & Sendable>(
    _ chunks: Chunks,
    length: Length = .unknown,
    onCancel: @escaping @Sendable () -> Void = {}
  ) where Chunks.Element == Element {
    let state = State(onCancel: onCancel)
    self.length = length
    self.state = state
    self.makeIteratorClosure = {
      var iterator = chunks.makeAsyncIterator()
      return Iterator(
        next: { try await iterator.next() },
        state: state)
    }
  }

  /// Creates a body containing one in-memory byte chunk.
  public convenience init(_ data: Data) {
    let chunks = AsyncStream(Element.self) { continuation in
      continuation.yield(ArraySlice(data))
      continuation.finish()
    }
    self.init(
      chunks,
      length: .known(Int64(data.count)))
  }

  /// Creates the body's single iterator.
  ///
  /// A second call returns an iterator that throws
  /// ``XRPCBodyError/alreadyConsumed`` when advanced.
  public func makeAsyncIterator() -> Iterator {
    guard state.beginIteration() else {
      return Iterator(throwing: XRPCBodyError.alreadyConsumed)
    }
    return makeIteratorClosure()
  }

  /// Cancels the transport operation backing this body.
  public func cancel() {
    state.cancel()
  }

  /// Collects the body into memory, rejecting bodies larger than `limit`.
  public func collect(upTo limit: Int) async throws -> Data {
    precondition(limit >= 0, "The collection limit must not be negative")
    var result = Data()
    if case .known(let length) = length, length > Int64(limit) {
      cancel()
      throw XRPCBodyError.tooManyBytes(limit: limit)
    }
    do {
      for try await chunk in self {
        guard chunk.count <= limit - result.count else {
          cancel()
          throw XRPCBodyError.tooManyBytes(limit: limit)
        }
        result.append(contentsOf: chunk)
      }
      return result
    } catch {
      cancel()
      throw error
    }
  }

  /// The single-pass iterator used to pull chunks from the transport.
  public struct Iterator: AsyncIteratorProtocol {
    private let produceNext: () async throws -> Element?
    private let state: State

    fileprivate init(
      next: @escaping () async throws -> Element?,
      state: State
    ) {
      produceNext = next
      self.state = state
    }

    fileprivate init(throwing error: any Error) {
      let state = State(onCancel: {})
      state.complete()
      self.state = state
      produceNext = { throw error }
    }

    /// Returns the next response byte chunk, or `nil` after the body ends.
    ///
    /// Cancelling the calling task cancels the transport operation.
    public mutating func next() async throws -> Element? {
      let state = self.state
      return try await withTaskCancellationHandler {
        let element = try await produceNext()
        if element == nil {
          state.complete()
        }
        return element
      } onCancel: {
        state.cancel()
      }
    }
  }

  fileprivate final class State: @unchecked Sendable {
    private let lock = NSLock()
    private let onCancel: @Sendable () -> Void
    private var iterationStarted = false
    private var isComplete = false
    private var isCancelled = false

    init(onCancel: @escaping @Sendable () -> Void) {
      self.onCancel = onCancel
    }

    func beginIteration() -> Bool {
      lock.withLock {
        guard !iterationStarted else { return false }
        iterationStarted = true
        return true
      }
    }

    func complete() {
      lock.withLock { isComplete = true }
    }

    func cancel() {
      let shouldCancel = lock.withLock {
        guard !isComplete, !isCancelled else { return false }
        isCancelled = true
        return true
      }
      if shouldCancel {
        onCancel()
      }
    }
  }
}

/// Failures raised while consuming an ``XRPCBody``.
public enum XRPCBodyError: Error, Hashable, Sendable {
  /// The single-pass body has already produced an iterator.
  case alreadyConsumed
  /// Collecting the body would exceed the caller's memory limit.
  case tooManyBytes(limit: Int)
}
