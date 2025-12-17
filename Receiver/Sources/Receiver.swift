import Foundation

/// Enum that represents the Receiver's strategies
public enum Strategy {
    case cold
    case warm(upTo: Int)
    case hot
}


/// The read only implementation of the Observer pattern.
/// Consumers use the `listen` method and provide a suitable handler that will
/// be called every time a new value (`Wave`) is forward.
/// A Receiver is always created as a pair with its
/// write only counter part: Transmitter.
///
/// By default it has `hot` semantics (as a strategy):
///
/// hot: Before receiving any new values, a handler needs to be provided:
///
/// ```
///    let (transmitter, receiver) = Receiver<Int>.make()
///
///     /// `1` is discarded, since there is no listener
///     transmitter.broadcast(1)
///
///     receiver.listen { value in
///     /// `2` is forwarded, since there is a listener
///     }
///
///     transmitter.broadcast(2)
/// ```
///
/// warm: Will forward previous values (up to the provided value) to the
///       handler once it is provided:
///
/// ```
///     let (transmitter, receiver) = Receiver<Int>.make(with: .warm(upTo: 1))
///
///     /// `1` is discarded, since the limit is `1` (`.warm(upTo: 1)`)
///     transmitter.broadcast(1)
///     /// `2` is stored, until there is an observer
///     transmitter.broadcast(2)
///
///     receiver.listen { value in
///     /// `2` is forwarded, since a listener was added
///     /// `3` is forwarded, since a listener exists
///     }
///
///     transmitter.broadcast(3)
/// ```
///
/// cold: Will forward all the previous values, once the handler is provided:
///
/// ```
///     let (transmitter, receiver) = Receiver<Int>.make(with: .cold)
///
///     /// `1` is stored, until there is an observer
///     transmitter.broadcast(1)
///     /// `2` is stored, until there is an observer
///     transmitter.broadcast(2)
///
///     receiver.listen { value in
///     /// `1` is forwarded, since a listener was added
///     /// `2` is forwarded, since a listener was added
///     /// `3` is forwarded, since a listener exists
///     }
///
///     transmitter.broadcast(3)
/// ```
///
/// For more examples, please check the `ReceiverTests/ReceiverTests.swift` file.
///
/// Note: Providing `.warm(upTo: Int.max)` will have the same meaning as `.cold`.
public class Receiver<Wave> {

    public typealias Handler = (Wave) -> Void

    private let values = Atomic<[Wave]>([])
    public let strategy: Strategy
    private let handlers = Atomic<[UInt64:Handler]>([:])
    private var nextKey: UInt64 = 0
    private let deliveryQueue = DispatchQueue(label: "receiver.delivery.queue")
    private let deliveryQueueKey = DispatchSpecificKey<Void>()

    private init(strategy: Strategy) {
        self.strategy = strategy
        deliveryQueue.setSpecific(key: deliveryQueueKey, value: ())
    }

    /// Returns a snapshot of the current handlers so user code is never
    /// executed while the lock is held.
    private func currentHandlers() -> [Handler] {
        var snapshot: [Handler] = []
        handlers.apply { _handlers in
            snapshot = Array(_handlers.values)
        }
        return snapshot
    }

    /// Executes the provided work serially to ensure handler invocation is
    /// thread-safe without reentrancy deadlocks.
    private func deliver(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: deliveryQueueKey) != nil {
            work()
        } else {
            deliveryQueue.sync(execute: work)
        }
    }

    /// Replays the last `elements` buffered values either to a single handler
    /// or to all current handlers.
    private func replay(elements: Int, handler: Handler? = nil) {
        var replayValues: [Wave] = []
        values.apply { _values in
            let lowerLimit = max(_values.count - elements, 0)
            if lowerLimit < _values.count {
                replayValues = Array(_values[lowerLimit ..< _values.count])
            }
        }

        guard replayValues.isEmpty == false else { return }

        if let handler = handler {
            deliver {
                replayValues.forEach(handler)
            }
        } else {
            let handlers = currentHandlers()
            deliver {
                replayValues.forEach { value in
                    handlers.forEach { $0(value) }
                }
            }
        }
    }

    /// Sends the latest value to all registered handlers.
    private func fanOut(_ value: Wave) {
        let handlers = currentHandlers()
        deliver {
            handlers.forEach { $0(value) }
        }
    }

    fileprivate func append(value: Wave) {
        switch strategy {
        case .hot:
            // No buffering needed; just deliver to active listeners.
            fanOut(value)

        case let .warm(upTo: limit):
            values.apply { currentValues in
                currentValues.append(value)
                // Keep only the latest `limit` items; limit may be Int.max.
                if limit < currentValues.count {
                    let overflow = currentValues.count - limit
                    if overflow > 0 {
                        currentValues.removeFirst(overflow)
                    }
                }
            }
            fanOut(value)

        case .cold:
            values.apply { currentValues in
                currentValues.append(value)
            }
            fanOut(value)
        }
    }

    /// Adds a listener to the receiver.
    ///
    /// - parameters:
    ///   - handle: An anonymous function that gets called every time a
    ///             a new value is sent.
    /// - returns: A reference to a disposable
    @discardableResult public func listen(to handle: @escaping (Wave) -> Void) -> Disposable {
        var _key: UInt64!
        handlers.apply { _handlers in
            _key = nextKey
            _handlers[_key] = handle
            nextKey = nextKey &+ 1
        }

        switch strategy {
        case .cold:
            replay(elements: Int.max, handler: handle)
        case let .warm(upTo: limit):
            replay(elements: limit, handler: handle)
        case .hot:
            replay(elements: 0, handler: handle)
        }

        return Disposable {[weak self] in
            self?.handlers.apply { _handlers in
                _handlers[_key] = nil
            }
        }
    }

    /// Factory method to create the pair `transmitter` and `receiver`.
    ///
    /// - parameters:
    ///   - strategy: The strategy that modifies the Receiver's behaviour
    ///               By default it's `hot`.
    public static func make(with strategy: Strategy = .hot)
        -> (Receiver.Transmitter, Receiver) {
            let receiver = Receiver(strategy: strategy)
            let transmitter = Receiver<Wave>.Transmitter(receiver)

            return (transmitter, receiver)
    }
}

extension Receiver {
    /// The write only implementation of the Observer pattern.
    /// Used to broadcast values (`Wave`) that will be observed by the `receiver`
    /// and forward to all its listeners.
    ///
    /// Note: Keep in mind that the `transmitter` will hold strongly
    ///       to its `receiver`.
    public struct Transmitter {
        private let receiver: Receiver

        internal init(_ receiver: Receiver) {
            self.receiver = receiver
        }

        /// Used to forward values to the associated `receiver`.
        ///
        /// - parameters:
        ///   - wave: The value to be forward
        public func broadcast(_ wave: Wave) {
            receiver.append(value: wave)
        }
    }
}
