import XCTest
import SwiftUI
@testable import TrainStationManager

/// Regression harness for RailKit's shared movement engine. Every bespoke level now rides `RailSim`, so a
/// change here can move all of them at once — these deterministic scenarios pin the invariants that matter:
/// trains stop where they're told, never overlap (lane-follow and body-ahead), reverse, overrun and finish.
final class RailSimTests: XCTestCase {

    // MARK: helpers

    private func train(_ len: Int = 3) -> Train { Train(length: len, tint: .blue, name: "") }
    /// A straight horizontal road of length `len` on line `y`.
    private func straight(_ len: CGFloat, y: CGFloat = 0) -> RoutePath {
        RoutePath([CGPoint(x: 0, y: y), CGPoint(x: len, y: y)])
    }
    private func vehicle(_ len: Int = 3, on path: RoutePath, lane: Int = 0, at d: CGFloat = 0) -> RailVehicle {
        let v = RailVehicle(spec: train(len), path: path, lane: lane)
        v.dist = d
        return v
    }
    private func run(_ sim: RailSim<RailVehicle>, ticks: Int, dt: Double = 0.03) {
        for _ in 0..<ticks { sim.step(dt) }
    }
    private func kin(cap: CGFloat = 100, accel: CGFloat = 200, decel: CGFloat = 300, gap: CGFloat = 20) -> RailKinematics {
        RailKinematics(speedCap: cap, accel: accel, decel: decel, followGap: gap)
    }

    // MARK: tests

    /// An unobstructed vehicle runs the length of its road and finishes at the end.
    func testAdvancesAndFinishesAtPathEnd() {
        let sim = RailSim<RailVehicle>(kin: kin())
        let v = vehicle(on: straight(500))
        sim.vehicles.append(v)
        run(sim, ticks: 600)
        XCTAssertTrue(v.finished, "an unobstructed vehicle should reach the end of its road")
        XCTAssertLessThanOrEqual(v.dist, 500.001, "it must never run past the end of its road")
    }

    /// The level's `ceiling` hook is honoured: a vehicle eases to a stand exactly at the hold and no further.
    func testCeilingHoldsShort() {
        let sim = RailSim<RailVehicle>(kin: kin())
        let v = vehicle(on: straight(1000))
        sim.vehicles.append(v)
        sim.ceiling = { _, _ in 300 }
        run(sim, ticks: 400)
        XCTAssertEqual(v.dist, 300, accuracy: 0.5, "it should hold at the ceiling")
        XCTAssertFalse(v.finished, "held short of the end, it hasn't finished")
        XCTAssertEqual(v.v, 0, accuracy: 0.5, "and it should have come to a stand")
    }

    /// Lane-follow: a follower on the same lane never runs its nose into the tail of the train ahead.
    func testLaneFollowNeverOverlaps() {
        let sim = RailSim<RailVehicle>(kin: kin(gap: 20))
        let path = straight(1000)
        let leader = vehicle(on: path, lane: 0, at: 200)
        let follower = vehicle(on: path, lane: 0, at: 0)
        sim.vehicles.append(leader); sim.vehicles.append(follower)
        sim.ceiling = { v, _ in v === leader ? 300 : .infinity }   // pin the leader so the follower queues
        run(sim, ticks: 400)
        XCTAssertLessThanOrEqual(follower.dist, leader.dist - leader.carLen,
                                 "the follower's nose must stay behind the leader's tail")
        XCTAssertGreaterThan(follower.dist, 80, "but it should have closed up behind the leader")
    }

    /// Body-ahead: with the position-based follow mode, a vehicle holds clear of the body of the one ahead
    /// rather than queuing by lane — the Birmingham/Crewe throat rule.
    func testBodyAheadNeverOverlaps() {
        let sim = RailSim<RailVehicle>(kin: kin(gap: 20))
        sim.followMode = .bodyAhead(reach: 200, clear: 40)
        let path = straight(1000)
        let leader = vehicle(on: path, lane: 1, at: 300)     // different lanes: only body-ahead can hold them
        let follower = vehicle(on: path, lane: 2, at: 0)
        sim.vehicles.append(leader); sim.vehicles.append(follower)
        sim.ceiling = { v, _ in v === leader ? 300 : .infinity }
        run(sim, ticks: 400)
        XCTAssertLessThan(follower.dist, leader.dist - leader.carLen,
                          "body-ahead must keep the follower clear of the leader's body across lanes")
    }

    /// Reverse: the `reverseSpeed` hook backs a vehicle out — its arc-length decreases and it finishes at 0.
    func testReverseBacksOutAndFinishes() {
        let sim = RailSim<RailVehicle>(kin: kin())
        let v = vehicle(2, on: straight(500), at: 300)
        sim.vehicles.append(v)
        sim.reverseSpeed = { _ in 100 }
        var finishCalled = false
        sim.onFinish = { _ in finishCalled = true }
        let start = v.dist
        sim.step(0.03)
        XCTAssertLessThan(v.dist, start, "a reversing vehicle's distance must decrease")
        run(sim, ticks: 300)
        XCTAssertTrue(v.finished, "it should finish once it has backed all the way out")
        XCTAssertTrue(finishCalled, "onFinish should fire for a reversing vehicle")
    }

    /// Overrun: a long train runs its whole body past the visible end before finishing, and `onFinish` fires.
    func testOverrunAndFinishHook() {
        let sim = RailSim<RailVehicle>(kin: kin())
        let v = vehicle(4, on: straight(300))            // carLen = 200
        sim.vehicles.append(v)
        sim.overrun = { CGFloat($0.spec.length) * Track.carUnit }   // 200 past the end
        var finished = false
        sim.onFinish = { _ in finished = true }
        run(sim, ticks: 500)
        XCTAssertTrue(finished, "it should run to path.total + overrun and finish")
    }

    /// The `speedLimit` hook caps the running speed (the amber-caution case).
    func testSpeedLimitCapsSpeed() {
        let sim = RailSim<RailVehicle>(kin: kin(cap: 100))
        let v = vehicle(on: straight(2000))
        sim.vehicles.append(v)
        sim.speedLimit = { _ in 30 }
        run(sim, ticks: 60)
        XCTAssertLessThanOrEqual(v.v, 30.5, "the vehicle must not exceed the caution speed limit")
        XCTAssertGreaterThan(v.dist, 0, "but it should still be moving")
    }

    /// Per-vehicle kinematics: a level that mixes stock gets each vehicle's own top speed.
    func testPerVehicleKinematics() {
        let sim = RailSim<RailVehicle>(kin: kin(cap: 50))
        let slow = vehicle(on: straight(4000), lane: 0)
        let fast = vehicle(on: straight(4000), lane: 1)
        sim.vehicles.append(slow); sim.vehicles.append(fast)
        sim.kinematics = { v in
            RailKinematics(speedCap: v === fast ? 200 : 50, accel: 400, decel: 400)
        }
        run(sim, ticks: 30)
        XCTAssertGreaterThan(fast.dist, slow.dist * 2, "the fast vehicle should outrun the slow one")
    }
}
