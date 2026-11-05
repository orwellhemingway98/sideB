import XCTest
@testable import SideB

@MainActor
final class RefreshSchedulerTests: XCTestCase {
    private final class Token {}

    private var refreshes = 0
    private var scheduled: [(interval: TimeInterval, tick: @MainActor () -> Void)] = []

    private func makeScheduler(refresh: (@MainActor () async -> Void)? = nil) -> RefreshScheduler {
        RefreshScheduler(
            refresh: refresh ?? { [unowned self] in self.refreshes += 1 },
            every: { [unowned self] interval, tick in
                self.scheduled.append((interval, tick))
                return Token()
            })
    }

    func testStartRefreshesNowAndSchedulesHourly() async {
        let scheduler = makeScheduler()
        scheduler.start()
        await scheduler.refreshNow()  // joins the refresh start() began
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(scheduled.map(\.interval), [3600])
        scheduled[0].tick()
        await scheduler.refreshNow()
        XCTAssertEqual(refreshes, 2, "the hourly tick refreshes again")
    }

    func testOverlappingRefreshesRunOnce() async {
        var entered = 0
        var release: CheckedContinuation<Void, Never>?
        let scheduler = makeScheduler(refresh: {
            entered += 1
            await withCheckedContinuation { release = $0 }
        })
        async let first: Void = scheduler.refreshNow()
        async let second: Void = scheduler.refreshNow()
        while release == nil { await Task.yield() }
        XCTAssertTrue(scheduler.isRefreshing)
        for _ in 0..<10 { await Task.yield() }
        release?.resume()
        _ = await (first, second)
        XCTAssertEqual(entered, 1, "the second request joins the first")
        XCTAssertFalse(scheduler.isRefreshing)
    }

    func testRefreshAfterOneFinishesRunsAgain() async {
        let scheduler = makeScheduler()
        await scheduler.refreshNow()
        await scheduler.refreshNow()
        XCTAssertEqual(refreshes, 2)
    }
}
