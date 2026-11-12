import AppKit

let launch = LaunchOptions.parse(CommandLine.arguments)

if launch.printIdle {
    let idle = IdleSensor.secondsSinceLastInput()
    print(String(format: "%.3f", idle))
    exit(0)
}

if let bundleID = Bundle.main.bundleIdentifier {
    let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if duplicates {
        fputs("休息提醒已经在运行。\n", stderr)
        exit(0)
    }
}

let app = NSApplication.shared
let appController = AppController(launch: launch)
app.delegate = appController
app.setActivationPolicy(.accessory)
app.run()
