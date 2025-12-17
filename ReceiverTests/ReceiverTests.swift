import XCTest
@testable import Receiver

class ReceiverTests: XCTestCase {

    func test_OneListener() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var called = 0

        receiver.listen { wave in
            XCTAssertTrue(wave == 1)
            called = called + 1
        }

        transmitter.broadcast(1)
        XCTAssertTrue(called == 1)
    }

    func test_MultipleListeners() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var called = 0

        for _ in 1...5 {
            receiver.listen { wave in
                XCTAssertTrue(wave == 1)
                called = called + 1
            }
        }

        transmitter.broadcast(1)
        XCTAssertTrue(called == 5)

        transmitter.broadcast(1)
        XCTAssertTrue(called == 10)
    }
    
    func test_MultipleColdListeners() {
        let (transmitter, receiver) = Receiver<Int>.make(with: .cold)
        var called = 0

        receiver.skipRepeats().listen { wave in
            called = called + 1
        }

        transmitter.broadcast(1)
        XCTAssertTrue(called == 1)

        receiver.skipRepeats().listen { wave in
            called = called + 1
        }
        
        transmitter.broadcast(1)
        XCTAssertTrue(called == 2)
    }

    func test_Multithread() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var called = 0
        let expect = expectation(description: "fun")
        let group = DispatchGroup()

        let oneQueue = DispatchQueue(label: "oneQueue")
        let twoQueues = DispatchQueue(label: "twoQueues")
        let threeQueues = DispatchQueue(label: "threeQueues")
        let fourQueues = DispatchQueue(label: "fourQueues")

        receiver.listen { wave in
            called = called + 1
        }

        receiver.listen { wave in
            called = called + 1
        }

        for _ in 1...5 {
            group.enter()
            oneQueue.async {
                transmitter.broadcast(1)
                group.leave()
            }
            group.enter()
            twoQueues.async {
                transmitter.broadcast(2)
                group.leave()
            }
            group.enter()
            threeQueues.async {
                transmitter.broadcast(3)
                group.leave()
            }
            group.enter()
            fourQueues.async {
                transmitter.broadcast(4)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            XCTAssert(called == 40)
            expect.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func test_NestedListener() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var outerCalled = 0
        var innerCalled = 0

        receiver.listen { _ in
            outerCalled = outerCalled + 1
            receiver.listen { _ in
                innerCalled = innerCalled + 1
            }
        }

        // First broadcast registers inner listener but only outer fires.
        transmitter.broadcast(1)
        XCTAssertTrue(outerCalled == 1)
        XCTAssertTrue(innerCalled == 0)

        // Subsequent broadcasts should trigger both.
        transmitter.broadcast(2)
        XCTAssertTrue(outerCalled == 2)
        XCTAssertTrue(innerCalled == 1)
        
        // Subsequent broadcasts should trigger both.
        transmitter.broadcast(3)
        XCTAssertTrue(outerCalled == 3)
        XCTAssertTrue(innerCalled == 3)
    }

    func test_NestedListener_DifferentReceivers() {
        let (outerTransmitter, outerReceiver) = Receiver<Int>.make()
        let (innerTransmitter, innerReceiver) = Receiver<Int>.make()
        var outerCalled = 0
        var innerCalled = 0

        outerReceiver.listen { _ in
            outerCalled = outerCalled + 1
            innerReceiver.listen { _ in
                innerCalled = innerCalled + 1
            }
        }

        // First outer broadcast registers an inner listener but does not fire it.
        outerTransmitter.broadcast(1)
        XCTAssertTrue(outerCalled == 1)
        XCTAssertTrue(innerCalled == 0)

        // Inner transmitter now fires the registered inner listener.
        innerTransmitter.broadcast(10)
        XCTAssertTrue(innerCalled == 1)

        // Another outer broadcast registers a second inner listener.
        outerTransmitter.broadcast(2)
        XCTAssertTrue(outerCalled == 2)

        // Inner broadcast should now notify both inner listeners.
        innerTransmitter.broadcast(20)
        XCTAssertTrue(innerCalled == 3)
    }

    func test_Warm_0() {
        runWarmBattery(expectedValues: [1, 2], upTo: 0)
    }

    func test_Warm_2_Queue1() {
        runWarmBattery(expectedValues: [1, 2], upTo: 1)
    }

    func test_Warm_2_Queue2() {
        runWarmBattery(expectedValues: [1, 2], upTo: 2)
    }

    func test_Warm_2_Queue3() {
        runWarmBattery(expectedValues: [1, 2], upTo: 3)
    }

    func test_Warm_5_Queue3() {
        runWarmBattery(expectedValues: [1, 2, 3, 4, 5], upTo: 3)
    }

    func runWarmBattery(expectedValues: [Int], upTo limit: Int) {
        let (transmitter, receiver) = Receiver<Int>.make(with: .warm(upTo: limit))
        var called = 0

        expectedValues.forEach(transmitter.broadcast)

        receiver.listen { wave in
            let index = max((expectedValues.count - limit), 0) + called
            XCTAssertTrue(expectedValues[index] == wave)
            called = called + 1
        }

        XCTAssertTrue(called == min(expectedValues.count, limit))
    }

    func test_Cold() {
        let (transmitter, receiver) = Receiver<Int>.make(with: .cold)
        var called = 0

        let expectedValues = [1, 2, 3, 4, 5]
        expectedValues.forEach(transmitter.broadcast)

        receiver.listen { wave in
            XCTAssertTrue(expectedValues[called] == wave)
            called = called + 1
        }

        XCTAssertTrue(called == 5)
    }

    func test_Warm_dropsOverflowBuffer() {
        let (transmitter, receiver) = Receiver<Int>.make(with: .warm(upTo: 2))
        [1, 2, 3, 4].forEach(transmitter.broadcast)

        var received: [Int] = []
        receiver.listen { received.append($0) }
        XCTAssertEqual(received, [3, 4])

        transmitter.broadcast(5)
        XCTAssertEqual(received, [3, 4, 5])

        var replay: [Int] = []
        receiver.listen { replay.append($0) }
        XCTAssertEqual(replay, [4, 5])
    }

    func test_Cold_multipleListenersReplayAllValues() {
        let (transmitter, receiver) = Receiver<Int>.make(with: .cold)
        [1, 2, 3].forEach(transmitter.broadcast)

        var first: [Int] = []
        receiver.listen { first.append($0) }
        XCTAssertEqual(first, [1, 2, 3])

        var second: [Int] = []
        receiver.listen { second.append($0) }
        XCTAssertEqual(second, [1, 2, 3])

        transmitter.broadcast(4)
        XCTAssertEqual(first, [1, 2, 3, 4])
        XCTAssertEqual(second, [1, 2, 3, 4])
    }

    func test_NoValueIsSent_IfBroadCastBeforeListenning_forHot() {
        let (transmitter, receiver) = Receiver<Int>.make()

        transmitter.broadcast(1)

        let inverted = expectation(description: "no value received")
        inverted.isInverted = true
        receiver.listen { _ in
            inverted.fulfill()
        }

        waitForExpectations(timeout: 0.1, handler: nil)
    }
    
    func test_weakness() {
        
        var outterTransmitter: Receiver<Int>.Transmitter?
        weak var outterReceiver: Receiver<Int>?
        
        autoreleasepool {
            let (transmitter, receiver) = Receiver<Int>.make()
            outterTransmitter = transmitter
            outterReceiver = receiver
        }
        
        XCTAssertNotNil(outterTransmitter)
        XCTAssertNotNil(outterReceiver)
    }

    func test_disposable() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var called = 0

        let disposable = receiver.listen { wave in
            called = called + 1
        }

        disposable.dispose()
        transmitter.broadcast(1)
        XCTAssertTrue(called == 0)
    }

    func test_disposable_MultipleListeners() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var value = 0

        let disposable1 = receiver.listen { wave in
            value = 1
        }

        disposable1.dispose()
        transmitter.broadcast(1)
        XCTAssertTrue(value == 0)

        receiver.listen { wave in
            value = 2
        }

        transmitter.broadcast(1)
        XCTAssertTrue(value == 2)
    }
    
    func test_disposeBag() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var called = 0
        
        var disposeBag: DisposeBag? = DisposeBag()
        
        receiver.listen { wave in
            called = called + 1
        }.disposed(by: disposeBag!)
        
        transmitter.broadcast(1)
        XCTAssertTrue(called == 1)
        
        disposeBag = nil
        transmitter.broadcast(2)
        XCTAssertTrue(called == 1)
    }
    
    func test_disposeBag_multipleListeners() {
        let (transmitter, receiver) = Receiver<Int>.make()
        var called = 0
        
        var disposeBag: DisposeBag? = DisposeBag()
        
        receiver.listen { wave in
            called = called + 1
            }.disposed(by: disposeBag!)
        
        receiver.listen { wave in
            called = called + 1
            }.disposed(by: disposeBag!)
        
        receiver.listen { wave in
            called = called + 1
            }.disposed(by: disposeBag!)
        
        receiver.listen { wave in
            called = called + 1
            }.disposed(by: disposeBag!)
        
        transmitter.broadcast(1)
        XCTAssertTrue(called == 4)
        
        disposeBag = nil // this forces the DisposeBag to be deinit()
        transmitter.broadcast(2)
        XCTAssertTrue(called == 4)
    }
}
