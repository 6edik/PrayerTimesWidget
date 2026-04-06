import Foundation
import QuartzCore
import CoreLocation
import Combine

@MainActor
final class QiblaNeedleAnimator: ObservableObject {
    @Published private(set) var displayedHeading: CLLocationDirection = 0

    private var targetHeading: CLLocationDirection = 0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    func start() {
        ensureDisplayLink()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    func setTargetHeading(_ heading: CLLocationDirection) {
        targetHeading = normalized(heading)
        ensureDisplayLink()
    }

    func reset(to heading: CLLocationDirection = 0) {
        let value = normalized(heading)
        targetHeading = value
        displayedHeading = value
        stop()
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func step(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }

        guard let lastTimestamp else {
            lastTimestamp = link.timestamp
            return
        }

        let dt = max(1.0 / 120.0, min(link.timestamp - lastTimestamp, 1.0 / 20.0))
        let delta = shortestAngleDelta(from: displayedHeading, to: targetHeading)

        let snapThreshold: CLLocationDirection = 0.25
        let deadZone: CLLocationDirection = 0.15
        let maxSpeed: CLLocationDirection = 220

        if abs(delta) <= snapThreshold {
            displayedHeading = targetHeading
            stop()
            return
        }

        if abs(delta) < deadZone {
            return
        }

        let maxStep = maxSpeed * dt
        let step = min(abs(delta), maxStep) * (delta >= 0 ? 1 : -1)

        displayedHeading = normalized(displayedHeading + step)
    }

    private func normalized(_ value: CLLocationDirection) -> CLLocationDirection {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    private func shortestAngleDelta(
        from oldValue: CLLocationDirection,
        to newValue: CLLocationDirection
    ) -> CLLocationDirection {
        var delta = newValue - oldValue
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}
