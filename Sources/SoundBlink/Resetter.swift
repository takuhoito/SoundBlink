import CoreAudio
import Foundation
import os

/// What started a reset.
enum ResetTrigger: String {
    case manual
    case scheduled
    case wake
}

enum ResetFailure: Equatable {
    case noOutputDevice
    case noIntermediateDevice
    case couldNotSwitch(to: String, status: OSStatus)
    case deviceDisappeared(String)
    case couldNotSwitchBack(to: String)
}

enum ResetOutcome: Equatable {
    /// The output was bounced through `via` and is back on `device`.
    /// `stoppedAfter` is how long the device took to stop I/O, or nil if it
    /// kept running until the timeout (another app may hold it open directly).
    case reset(device: String, via: String, stoppedAfter: TimeInterval?)
    /// The built-in output is already the default, so there is nothing to reset.
    case skippedBuiltIn
    /// Audio is playing and the trigger was automatic.
    case skippedPlaying(device: String)
    /// The device is excluded from automatic resets and the trigger was automatic.
    case skippedExcluded(device: String)
    case failed(ResetFailure)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension ResetOutcome: CustomStringConvertible {
    var description: String {
        switch self {
        case let .reset(device, via, stoppedAfter):
            if let stoppedAfter {
                return "Reset \(device) via \(via) (output stopped after \(Int(stoppedAfter * 1000)) ms)."
            }
            return "Reset \(device) via \(via), but it kept running; another app may be using it directly."
        case .skippedBuiltIn: return "Skipped: the built-in output is already the default."
        case let .skippedPlaying(device): return "Skipped: audio is playing on \(device)."
        case let .skippedExcluded(device): return "Skipped: automatic reset is turned off for \(device)."
        case let .failed(failure):
            switch failure {
            case .noOutputDevice: return "Failed: there is no default output device."
            case .noIntermediateDevice: return "Failed: there is no other output device to switch through."
            case let .couldNotSwitch(name, status): return "Failed: could not switch to \(name) (OSStatus \(status))."
            case let .deviceDisappeared(name): return "Failed: \(name) disappeared while switching."
            case let .couldNotSwitchBack(name): return "Failed: could not switch back to \(name)."
            }
        }
    }
}

struct ResetResult {
    let trigger: ResetTrigger
    let outcome: ResetOutcome
    let date: Date
}

struct ResetOptions {
    /// Skip scheduled and wake-triggered resets while the output is running.
    var skipWhilePlaying: Bool
    /// Devices that scheduled and wake-triggered resets leave alone.
    /// Manual resets always run.
    var excludedDeviceUIDs: Set<String>
    /// Extra time to stay on the intermediate device once the original device has stopped.
    var hold: TimeInterval
    /// Maximum time to wait for the original device to stop before switching back anyway.
    var timeout: TimeInterval
}

/// Briefly moves the default output to another device and back, which makes
/// Core Audio tear down and restart I/O on the original device. This clears the
/// crackling/distortion some USB audio devices develop over time.
///
/// Instead of a fixed delay, it switches back as soon as the original device
/// has actually stopped I/O (typically 20-30 ms after the switch), plus a short
/// hold, so the audible gap stays as short as possible.
final class Resetter {
    static let shared = Resetter()

    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).resetter")
    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "reset")

    /// Runs a reset on a background queue and calls `completion` on the main queue.
    func reset(trigger: ResetTrigger, options: ResetOptions, completion: @escaping (ResetResult) -> Void) {
        queue.async {
            let result = self.performReset(trigger: trigger, options: options)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Runs a reset synchronously on the calling thread. Blocks for up to
    /// `options.timeout + options.hold` plus a fraction of a second.
    func performReset(trigger: ResetTrigger, options: ResetOptions) -> ResetResult {
        let outcome = bounce(trigger: trigger, options: options)
        if outcome.isFailure {
            logger.error("[\(trigger.rawValue, privacy: .public)] \(outcome.description, privacy: .public)")
        } else {
            logger.notice("[\(trigger.rawValue, privacy: .public)] \(outcome.description, privacy: .public)")
        }
        return ResetResult(trigger: trigger, outcome: outcome, date: Date())
    }

    private func bounce(trigger: ResetTrigger, options: ResetOptions) -> ResetOutcome {
        guard let output = AudioSystem.defaultDevice(.output) else {
            return .failed(.noOutputDevice)
        }
        if output.isBuiltIn {
            return .skippedBuiltIn
        }
        if trigger != .manual, options.excludedDeviceUIDs.contains(output.uid) {
            return .skippedExcluded(device: output.name)
        }
        if trigger != .manual, options.skipWhilePlaying, AudioSystem.isRunningSomewhere(output.id) {
            return .skippedPlaying(device: output.name)
        }
        guard let via = Self.intermediateDevice(excluding: output) else {
            return .failed(.noIntermediateDevice)
        }

        // Only move the sound-effects device if it was following the main output.
        let systemOutputFollows = AudioSystem.defaultDeviceID(.systemOutput) == output.id

        // Mute the intermediate device so nothing leaks out of it during the switch.
        let wasMuted = AudioSystem.outputMute(via.id)
        if wasMuted == false {
            AudioSystem.setOutputMute(via.id, true)
        }
        defer {
            if wasMuted == false {
                AudioSystem.setOutputMute(via.id, false)
            }
        }

        let status = AudioSystem.setDefaultDevice(.output, to: via.id)
        guard status == noErr else {
            return .failed(.couldNotSwitch(to: via.name, status: status))
        }
        if systemOutputFollows {
            AudioSystem.setDefaultDevice(.systemOutput, to: via.id)
        }

        let stoppedAfter = waitUntilStopped(output.id, timeout: options.timeout)
        Thread.sleep(forTimeInterval: options.hold)

        // Switch back by UID: the device ID can change if the device re-enumerated meanwhile.
        for attempt in 1...2 {
            guard let target = AudioSystem.device(uid: output.uid) else {
                return .failed(.deviceDisappeared(output.name))
            }
            AudioSystem.setDefaultDevice(.output, to: target.id)
            if systemOutputFollows {
                AudioSystem.setDefaultDevice(.systemOutput, to: target.id)
            }
            Thread.sleep(forTimeInterval: 0.15)
            if AudioSystem.defaultDeviceID(.output) == target.id {
                return .reset(device: output.name, via: via.name, stoppedAfter: stoppedAfter)
            }
            logger.warning("Switch back to \(output.name, privacy: .public) did not stick (attempt \(attempt)).")
            Thread.sleep(forTimeInterval: 0.3)
        }
        return .failed(.couldNotSwitchBack(to: output.name))
    }

    /// Polls until no process is doing I/O on the device. Returns the elapsed
    /// time, or nil if the device was still running when `timeout` passed.
    private func waitUntilStopped(_ id: AudioDeviceID, timeout: TimeInterval) -> TimeInterval? {
        let start = Date()
        while true {
            let elapsed = Date().timeIntervalSince(start)
            if !AudioSystem.isRunningSomewhere(id) { return elapsed }
            if elapsed >= timeout { return nil }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    /// Picks the device to bounce through: the built-in output if there is one,
    /// otherwise a physical device that can be muted, otherwise anything else.
    static func intermediateDevice(excluding output: AudioDevice) -> AudioDevice? {
        func rank(_ device: AudioDevice) -> Int {
            if device.isBuiltIn { return 0 }
            if !device.isVirtual, AudioSystem.outputMute(device.id) != nil { return 1 }
            if !device.isVirtual { return 2 }
            return 3
        }
        return AudioSystem.outputDevices()
            .filter { $0.uid != output.uid }
            .min { rank($0) < rank($1) }
    }
}
