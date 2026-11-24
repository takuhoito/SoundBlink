import AppKit

/// Command-line entry points, e.g. for Shortcuts, Raycast or bug reports:
///
///     /Applications/SoundBlink.app/Contents/MacOS/SoundBlink --reset
enum CommandLineInterface {
    static func printUsage() {
        print("""
        Usage: \(AppInfo.name) [option]

        Without options, \(AppInfo.name) runs as a menu bar app.

        Options:
          --reset     Bounce the default output through another device once and exit.
          --list      Print audio output devices (useful for bug reports) and exit.
          --version   Print the version and exit.
          --help      Show this help and exit.
        """)
    }

    static func listDevices() {
        let output = AudioSystem.defaultDeviceID(.output)
        let systemOutput = AudioSystem.defaultDeviceID(.systemOutput)

        print("\(AppInfo.name) \(AppInfo.version) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Default output:        \(output.flatMap(AudioSystem.device(id:))?.name ?? "none")")
        print("Default system output: \(systemOutput.flatMap(AudioSystem.device(id:))?.name ?? "none")")
        print("")
        print("Output devices (* = default output):")
        for device in AudioSystem.outputDevices() {
            let marker = device.id == output ? "*" : " "
            let mute = AudioSystem.outputMute(device.id).map { $0 ? "on" : "off" } ?? "n/a"
            let running = AudioSystem.isRunningSomewhere(device.id) ? "yes" : "no"
            print("""
              \(marker) \(device.name)
                  uid: \(device.uid)
                  transport: \(device.transportName), sample rate: \(Int(device.nominalSampleRate)) Hz, \
            channels: \(device.outputChannels), mute: \(mute), running: \(running)
            """)
        }
    }

    static func reset() -> Int32 {
        let result = Resetter.shared.performReset(trigger: .manual, options: Settings.shared.resetOptions)
        print(result.outcome.description)
        return result.outcome.isFailure ? 1 : 0
    }
}

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    CommandLineInterface.printUsage()
    exit(0)
}
if arguments.contains("--version") {
    print("\(AppInfo.name) \(AppInfo.version)")
    exit(0)
}
if arguments.contains("--list") {
    CommandLineInterface.listDevices()
    exit(0)
}
if arguments.contains("--reset") {
    exit(CommandLineInterface.reset())
}

// Only one menu bar instance at a time (e.g. login item + manual launch).
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
