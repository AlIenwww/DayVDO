import Foundation
import XCTest
@testable import DayVDO

/// Opt-in repeatable CPU workloads; these do not measure animation FPS or energy.
@MainActor
final class OptimizationPerformanceTests: XCTestCase {
    func testCalendarBuildAndRepeatedStoreReads() async throws {
        guard ProcessInfo.processInfo.environment["DAYVDO_RUN_OPTIMIZATION_BENCHMARK"] == "1" else {
            throw XCTSkip("Enable DAYVDO_RUN_OPTIMIZATION_BENCHMARK for comparative workloads")
        }
        let day = LocalDay(year: 2026, month: 10, day: 19)
        for count in [100, 1000] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-CPU-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let project = TodoProject(title: "Workload")
            let items = (0..<count).map { index in
                TodoItem(title: "Task \(index)", startDate: day.adding(days: index % 42).date(),
                    dueDate: day.adding(days: index % 42 + index % 14).date(), projectID: project.id)
            }
            let schedules = items.enumerated().map { index, item in
                DaySchedule(startDay: item.startDay!, startMinute: 480 + index % 600,
                    durationMinutes: 45, content: .todo(item.id))
            }
            let encoder = JSONEncoder()
            let data: [String: Any] = ["version": 4,
                "items": try JSONSerialization.jsonObject(with: encoder.encode(items)),
                "projects": try JSONSerialization.jsonObject(with: encoder.encode([project])),
                "schedules": try JSONSerialization.jsonObject(with: encoder.encode(schedules))]
            let file = directory.appendingPathComponent("todos.json")
            try JSONSerialization.data(withJSONObject: data).write(to: file)
            let store = TodoStore(fileURL: file)
            let key = CalendarWindowSnapshot.Key(revision: 1, firstDay: day.adding(days: -21),
                lastDay: day.adding(days: 188), timeZoneIdentifier: "America/Los_Angeles", firstWeekday: 2,
                visibility: .init(showCompleted: true))
            var builds: [Double] = []
            var reads: [Double] = []
            var countCheck = 0
            for _ in 0..<7 {
                var start = ContinuousClock.now
                for _ in 0..<5 {
                    let snapshot = CalendarWindowSnapshot.build(key: key, items: items, tags: [])
                    XCTAssertEqual(snapshot.rangedItems.count, count)
                    countCheck += snapshot.itemsByDay.count
                }
                builds.append(milliseconds(start.duration(to: .now)) / 5)
                start = .now
                for iteration in 0..<200 {
                    countCheck += store.items(in: project).count
                    countCheck += store.schedules(on: day.adding(days: iteration % 42)).count
                    countCheck += store.scheduledMinutes(for: items[iteration % count].id)
                }
                reads.append(milliseconds(start.duration(to: .now)))
            }
            XCTAssertGreaterThan(countCheck, 0)
            let report: [String: Any] = ["items": count,
                "calendar_build_median_ms": builds.sorted()[3],
                "store_200_reads_median_ms": reads.sorted()[3]]
            let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("OPTIMIZATION_WORKLOAD \(String(decoding: json, as: UTF8.self))")
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
