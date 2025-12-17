import XCTest
@testable import Receiver

class ReceiverTests_Operators: XCTestCase {
    
    func test_map() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.map(String.init)
        var called = 0

        newReceiver.listen { wave in
            XCTAssertTrue(wave == "1")
            called = called + 1
        }
        
        transmitter.broadcast(1)
        XCTAssertTrue(called == 1)
    }

    func test_filter() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.filter { $0 % 2 == 0 }
        var called = 0

        newReceiver.listen { wave in
            XCTAssertTrue(wave == 2)
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(2)
        transmitter.broadcast(3)

        XCTAssertTrue(called == 1)
    }

    func test_skipRepeats() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.skipRepeats()
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(1)
        transmitter.broadcast(2)
        transmitter.broadcast(1)
        transmitter.broadcast(2)
        transmitter.broadcast(2)
        transmitter.broadcast(3)

        XCTAssertTrue(called == 5)
    }

    func test_withPrevious_nil() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.withPrevious()
        var called = 0
        var expected: (Int?, Int) = (0, 0)

        newReceiver.listen { wave in
            expected = wave
            called = called + 1
        }

        transmitter.broadcast(1)
        XCTAssertTrue(expected.0 == nil)
        XCTAssertTrue(expected.1 == 1)

        transmitter.broadcast(2)
        XCTAssertTrue(expected.0 == 1)
        XCTAssertTrue(expected.1 == 2)

        XCTAssertTrue(called == 2)
    }

    func test_skip() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.skip(count: 3)
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(1)
        transmitter.broadcast(1)
        XCTAssertTrue(called == 0)

        transmitter.broadcast(1)
        XCTAssertTrue(called == 1)

        transmitter.broadcast(1)
        XCTAssertTrue(called == 2)
    }

    func test_skip_zero() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.skip(count: 0)
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        XCTAssertTrue(called == 1)
    }

    func test_take() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.take(count: 2)
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(1)
        transmitter.broadcast(1)
        transmitter.broadcast(1)

        XCTAssertTrue(called == 2)
    }

    func test_take_zero() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.take(count: 0)
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(1)
        transmitter.broadcast(1)
        transmitter.broadcast(1)

        XCTAssertTrue(called == 0)
    }

    func test_skipNil() {
        let (transmitter, receiver) = Receiver<Int?>.make()
        let newReceiver = receiver.skipNil()
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(nil)
        transmitter.broadcast(1)

        XCTAssertTrue(called == 2)
    }

    func test_uniqueValues() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.uniqueValues()
        var called = 0

        newReceiver.listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        transmitter.broadcast(2)
        transmitter.broadcast(1)
        transmitter.broadcast(3)
        transmitter.broadcast(1)
        transmitter.broadcast(3)
        transmitter.broadcast(2)

        XCTAssertTrue(called == 3)
    }

    func test_uniqueValues_coldReplaysOnlyUniqueValues() {
        let (transmitter, receiver) = Receiver<Int>.make(with: .cold)
        [1, 2, 1, 3, 3].forEach(transmitter.broadcast)

        let uniqueReceiver = receiver.uniqueValues()
        var received: [Int] = []

        uniqueReceiver.listen { received.append($0) }
        XCTAssertEqual(received, [1, 2, 3])

        transmitter.broadcast(4)
        XCTAssertEqual(received, [1, 2, 3, 4])
    }

    func test_hotOnly_skipsBufferedValuesFromColdSource() {
        let (transmitter, receiver) = Receiver<Int>.make(with: .cold)
        let hotOnly = receiver.hotOnly()

        transmitter.broadcast(1)
        transmitter.broadcast(2)

        var received: [Int] = []
        hotOnly.listen { received.append($0) }

        transmitter.broadcast(3)
        transmitter.broadcast(4)

        XCTAssertEqual(received, [3, 4])
    }

    func test_skip_negativeCount_behavesAsIdentity() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.skip(count: -3)
        var called = 0

        newReceiver.listen { _ in
            called = called + 1
        }

        transmitter.broadcast(1)
        XCTAssertEqual(called, 1)
    }

    func test_take_negativeCount_forwardsNoValues() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let newReceiver = receiver.take(count: -1)
        var called = 0

        newReceiver.listen { _ in
            called = called + 1
        }

        transmitter.broadcast(1)
        XCTAssertEqual(called, 0)
    }

    func test_skipNil_withColdSourceReplaysNonNilValues() {
        let (transmitter, receiver) = Receiver<Int?>.make(with: .cold)
        transmitter.broadcast(1)
        transmitter.broadcast(nil)
        transmitter.broadcast(2)

        let nonNilReceiver = receiver.skipNil()
        var received: [Int] = []

        nonNilReceiver.listen { received.append($0) }
        XCTAssertEqual(received, [1, 2])
    }

    func test_withPrevious_multipleValues() {
        let (transmitter, receiver) = Receiver<Int>.make()
        let previousReceiver = receiver.withPrevious()
        var received: [(Int?, Int)] = []

        previousReceiver.listen { received.append($0) }

        transmitter.broadcast(10)
        transmitter.broadcast(20)
        transmitter.broadcast(30)

        XCTAssertEqual(received.map { $0.0 }, [nil, 10, 20])
        XCTAssertEqual(received.map { $0.1 }, [10, 20, 30])
    }
}
