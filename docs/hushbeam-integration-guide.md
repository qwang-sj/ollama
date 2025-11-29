# HushBeam Integration Guide

This document describes how to integrate hushbeam-ollama with the HushBeam macOS application.

## Overview

HushBeam-Ollama provides two modes of operation:

1. **CLI Binary (`hushbeam-ollama serve`)** - Headless server mode, no UI, no menu bar icon
2. **App Bundle (`HushBeam-Ollama.app`)** - Full macOS app with menu bar icon and UI

**For HushBeam integration, use the CLI binary in headless mode.**

## Headless Server Mode

### Starting the Server

```bash
# Default: listens on 127.0.0.1:11434
hushbeam-ollama serve

# Custom port (random port for HushBeam)
OLLAMA_HOST=127.0.0.1:0 hushbeam-ollama serve

# With custom models directory
HUSHBEAM_OLLAMA_MODELS=~/Library/Application\ Support/app.reckr.hushbeam.macos/Models \
    hushbeam-ollama serve
```

### Stopping the Server

Send SIGTERM or SIGINT:
```bash
kill -TERM <pid>
# or
kill -INT <pid>
```

## Swift Integration Example

```swift
import Foundation

class OllamaServerManager {
    private var process: Process?
    private var serverPort: Int?

    // Path to hushbeam-ollama binary
    private let binaryPath: String
    private let modelsPath: String

    init() {
        // Binary bundled with HushBeam
        self.binaryPath = Bundle.main.path(forResource: "hushbeam-ollama", ofType: nil)
            ?? "/usr/local/bin/hushbeam-ollama"

        // Models stored in HushBeam's Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsPath = appSupport.appendingPathComponent("app.reckr.hushbeam.macos/Models").path
    }

    func start() throws -> Int {
        guard process == nil else { return serverPort ?? 11434 }

        // Create models directory if needed
        try? FileManager.default.createDirectory(atPath: modelsPath, withIntermediateDirectories: true)

        // Find available port
        let port = findAvailablePort()

        process = Process()
        process?.executableURL = URL(fileURLWithPath: binaryPath)
        process?.arguments = ["serve"]
        process?.environment = ProcessInfo.processInfo.environment.merging([
            "OLLAMA_HOST": "127.0.0.1:\(port)",
            "HUSHBEAM_OLLAMA_MODELS": modelsPath,
            "OLLAMA_KEEP_ALIVE": "5m"
        ]) { _, new in new }

        // Pipe stdout/stderr for logging
        let pipe = Pipe()
        process?.standardOutput = pipe
        process?.standardError = pipe

        // Handle output asynchronously
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("[hushbeam-ollama] \(output)")
            }
        }

        try process?.run()
        serverPort = port

        // Wait for server to be ready
        waitForServer(port: port)

        return port
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
        process = nil
        serverPort = nil
    }

    func restart() throws -> Int {
        stop()
        return try start()
    }

    private func findAvailablePort() -> Int {
        // Find random available port
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // Let OS assign port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socket, $0, &len)
            }
        }

        return Int(UInt16(bigEndian: addr.sin_port))
    }

    private func waitForServer(port: Int, timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let url = URL(string: "http://127.0.0.1:\(port)/api/tags"),
               let _ = try? Data(contentsOf: url) {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}
```

## API Endpoints

Once the server is running, use the standard Ollama API:

```
GET  http://127.0.0.1:<port>/api/tags       - List models
POST http://127.0.0.1:<port>/api/pull       - Pull a model
POST http://127.0.0.1:<port>/api/generate   - Generate text
POST http://127.0.0.1:<port>/api/chat       - Chat completion
POST http://127.0.0.1:<port>/api/embeddings - Get embeddings
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_HOST` | Server address:port | `127.0.0.1:11434` |
| `HUSHBEAM_OLLAMA_MODELS` | Models directory | `~/Library/Application Support/app.reckr.hushbeam.macos/Models` |
| `OLLAMA_MODELS` | Fallback models dir | (same as above) |
| `OLLAMA_KEEP_ALIVE` | Model keep-alive time | `5m` |
| `OLLAMA_DEBUG` | Enable debug logging | `false` |

## Data Paths

All HushBeam-Ollama data is stored in:
```
~/Library/Application Support/app.reckr.hushbeam.macos/
├── Models/              # Downloaded models
├── logs/
│   ├── server.log       # Server logs
│   └── app.log          # App logs (if using .app)
├── db.sqlite            # Settings database
├── config.json          # Configuration
├── hushbeam-ollama.pid  # PID file
├── id_ed25519           # Auth keypair
└── id_ed25519.pub
```

## Building the Binary

```bash
# Build CLI only (for embedding in HushBeam)
./scripts/build_darwin.sh build

# Output: dist/darwin/hushbeam-ollama (universal binary)
```

## Process Lifecycle

1. **HushBeam starts** → Spawn `hushbeam-ollama serve` as child process
2. **HushBeam quits** → Send SIGTERM to hushbeam-ollama
3. **HushBeam restarts** → New hushbeam-ollama process is spawned

The server handles SIGTERM/SIGINT gracefully, finishing any active requests before shutdown.

## Notes

- The CLI binary is completely headless - no menu bar icon, no dock icon, no UI
- Use the CLI binary (not the .app bundle) for HushBeam integration
- The server writes its PID to `hushbeam-ollama.pid` for process management
- Models are large (2-8GB+); ensure adequate disk space
