import CoreAudio
import Foundation

/// A snapshot of one Core Audio device.
struct AudioDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let outputChannels: Int
    let nominalSampleRate: Double

    var isBuiltIn: Bool { transportType == kAudioDeviceTransportTypeBuiltIn }
    var isVirtual: Bool { transportType == kAudioDeviceTransportTypeVirtual }
    var hasOutput: Bool { outputChannels > 0 }

    /// Human-readable transport name such as "usb", "bltn" or "hdmi".
    var transportName: String {
        let bytes = withUnsafeBytes(of: transportType.bigEndian, Array.init)
        let text = String(bytes: bytes, encoding: .ascii) ?? "?"
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Which system-wide default device to read or change.
enum DefaultDeviceRole {
    /// The device apps play through ("Output" in System Settings > Sound).
    case output
    /// The device alerts and sound effects play through.
    case systemOutput

    var selector: AudioObjectPropertySelector {
        switch self {
        case .output: return kAudioHardwarePropertyDefaultOutputDevice
        case .systemOutput: return kAudioHardwarePropertyDefaultSystemOutputDevice
        }
    }
}

/// Thin, synchronous wrapper around the Core Audio HAL property API.
enum AudioSystem {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    // MARK: Devices

    static func allDevices() -> [AudioDevice] {
        var address = makeAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap(device(id:))
    }

    static func outputDevices() -> [AudioDevice] {
        allDevices().filter(\.hasOutput)
    }

    static func device(id: AudioDeviceID) -> AudioDevice? {
        guard id != kAudioObjectUnknown,
              let uid = string(id, kAudioDevicePropertyDeviceUID)
        else { return nil }
        let transport: UInt32 = value(id, makeAddress(kAudioDevicePropertyTransportType)) ?? 0
        let rate: Float64 = value(id, makeAddress(kAudioDevicePropertyNominalSampleRate)) ?? 0
        return AudioDevice(
            id: id,
            uid: uid,
            name: string(id, kAudioObjectPropertyName) ?? uid,
            transportType: transport,
            outputChannels: channelCount(id, scope: kAudioObjectPropertyScopeOutput),
            nominalSampleRate: rate
        )
    }

    /// Looks a device up by its persistent UID. Device IDs can change when a
    /// device is unplugged and re-enumerated; UIDs do not.
    static func device(uid: String) -> AudioDevice? {
        allDevices().first { $0.uid == uid }
    }

    // MARK: Defaults

    static func defaultDeviceID(_ role: DefaultDeviceRole) -> AudioDeviceID? {
        let id: AudioDeviceID? = value(systemObject, makeAddress(role.selector))
        guard let id, id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func defaultDevice(_ role: DefaultDeviceRole) -> AudioDevice? {
        defaultDeviceID(role).flatMap(device(id:))
    }

    @discardableResult
    static func setDefaultDevice(_ role: DefaultDeviceRole, to id: AudioDeviceID) -> OSStatus {
        setValue(systemObject, makeAddress(role.selector), id)
    }

    // MARK: Device state

    /// True when any process is currently doing I/O on the device.
    static func isRunningSomewhere(_ id: AudioDeviceID) -> Bool {
        let running: UInt32? = value(id, makeAddress(kAudioDevicePropertyDeviceIsRunningSomewhere))
        return (running ?? 0) != 0
    }

    /// The output mute state, or nil when the device has no settable master mute.
    static func outputMute(_ id: AudioDeviceID) -> Bool? {
        var address = makeAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue else {
            return nil
        }
        let muted: UInt32? = value(id, address)
        return muted.map { $0 != 0 }
    }

    @discardableResult
    static func setOutputMute(_ id: AudioDeviceID, _ muted: Bool) -> Bool {
        let address = makeAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return setValue(id, address, UInt32(muted ? 1 : 0)) == noErr
    }

    // MARK: Low-level helpers

    private static func makeAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func setValue<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ newValue: T) -> OSStatus {
        var address = address
        return withUnsafeBytes(of: newValue) { bytes in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(bytes.count), bytes.baseAddress!)
        }
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = makeAddress(selector)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr,
              let result
        else { return nil }
        return result.takeRetainedValue() as String
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = makeAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
