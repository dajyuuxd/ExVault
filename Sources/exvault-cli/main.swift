// CLI entry point for macOS server testing.

import Foundation
import Dispatch
import ExVaultCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// 1. Argument parsing
var dataDirStr = "./data"
var webDirStr = "./Web"
var portNum: UInt16 = 8080

let args = CommandLine.arguments
var idx = 1
while idx < args.count {
    let arg = args[idx]
    if arg == "--data" && idx + 1 < args.count {
        dataDirStr = args[idx + 1]
        idx += 2
    } else if arg == "--web" && idx + 1 < args.count {
        webDirStr = args[idx + 1]
        idx += 2
    } else if arg == "--port" && idx + 1 < args.count {
        if let p = UInt16(args[idx + 1]) {
            portNum = p
        }
        idx += 2
    } else {
        idx += 1
    }
}

let cwd = FileManager.default.currentDirectoryPath
let dataUrl = URL(fileURLWithPath: dataDirStr, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
let webUrl = URL(fileURLWithPath: webDirStr, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL

try? FileManager.default.createDirectory(at: dataUrl, withIntermediateDirectories: true, attributes: nil)

// 2. Configure logging to stdout
Log.sink = { line in
    print(line)
    fflush(stdout)
}

// 3. Create server and start
do {
    let config = VaultConfig(
        dataDir: dataUrl,
        webRoot: webUrl,
        port: portNum
    )
    let server = try VaultServer(config: config)
    try server.start()

    // 4. Output exact ready block required by scripts and docs
    print("EXVAULT_URL=http://127.0.0.1:\(server.boundPort)")
    print("EXVAULT_USER=\(server.credentials.username)")
    print("EXVAULT_PASS=\(server.credentials.password)")
    print("EXVAULT_READY=1")
    fflush(stdout)

    // 5. Catch SIGINT and SIGTERM to stop cleanly
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        server.stop()
        exit(0)
    }
    sigint.resume()

    let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigterm.setEventHandler {
        server.stop()
        exit(0)
    }
    sigterm.resume()

    dispatchMain()
} catch {
    fputs("Fatal error starting exvault-cli: \(error)\n", stderr)
    exit(1)
}
