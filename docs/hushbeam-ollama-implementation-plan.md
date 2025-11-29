# HushBeam-Ollama Implementation Plan

## Overview

This document describes the minimal customization required to transform the Ollama fork into `hushbeam-ollama` - a bundled LLM server component for the HushBeam macOS application.

**Goals:**
- Process name: `hushbeam-ollama` (visible in Activity Monitor)
- Controlled by HushBeam parent app (start/stop/quit)
- Custom data paths under `~/Library/Application Support/app.reckr.hushbeam.macos/`
- Stay close to upstream Ollama for easy updates

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    HushBeam.app                              │
│  (Menu Bar Application - SwiftUI)                           │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  hushbeam-ollama (child process)                     │    │
│  │  - HTTP API on 127.0.0.1:<random-port>              │    │
│  │  - Models in ~/Library/.../app.reckr.hushbeam.macos │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: Process Name Changes

### 1.1 CLI Command Name
**File:** `cmd/cmd.go`
**Line:** 1691

```go
// Before
rootCmd := &cobra.Command{
    Use:           "ollama",
    Short:         "Large language model runner",

// After
rootCmd := &cobra.Command{
    Use:           "hushbeam-ollama",
    Short:         "HushBeam LLM server",
```

### 1.2 Go Module Path (Optional)
**File:** `go.mod`

Keep as `github.com/ollama/ollama` for now to minimize changes. Can update later if needed.

### 1.3 Build Output Names
**File:** `scripts/build_darwin.sh`

Update binary output paths from `ollama` to `hushbeam-ollama`.

## Phase 2: Path Customization

### 2.1 Models Directory
**File:** `envconfig/config.go`
**Lines:** 85-98

```go
// Before
func Models() string {
    if s := Var("OLLAMA_MODELS"); s != "" {
        return s
    }
    home, err := os.UserHomeDir()
    if err != nil {
        panic(err)
    }
    return filepath.Join(home, ".ollama", "models")
}

// After - Add HUSHBEAM prefix to env var, change default path
func Models() string {
    // Check HushBeam-specific env var first
    if s := Var("HUSHBEAM_OLLAMA_MODELS"); s != "" {
        return s
    }
    // Fall back to standard OLLAMA_MODELS for compatibility
    if s := Var("OLLAMA_MODELS"); s != "" {
        return s
    }
    home, err := os.UserHomeDir()
    if err != nil {
        panic(err)
    }
    return filepath.Join(home, "Library", "Application Support", "app.reckr.hushbeam.macos", "Models")
}
```

### 2.2 Server Paths (macOS)
**File:** `app/server/server_unix.go`
**Lines:** 18-21

```go
// Before
var (
    pidFile       = filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "Ollama", "ollama.pid")
    serverLogPath = filepath.Join(os.Getenv("HOME"), ".ollama", "logs", "server.log")
)

// After
var (
    pidFile       = filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "app.reckr.hushbeam.macos", "hushbeam-ollama.pid")
    serverLogPath = filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "app.reckr.hushbeam.macos", "logs", "server.log")
)
```

### 2.3 Store Paths
**File:** `app/store/store.go`
**Lines:** 190, 202

```go
// Before (line ~190)
return filepath.Join(os.Getenv("HOME"), ".ollama", "db.sqlite")

// After
return filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "app.reckr.hushbeam.macos", "db.sqlite")

// Before (line ~202)
return filepath.Join(os.Getenv("HOME"), ".ollama", "config.json")

// After
return filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "app.reckr.hushbeam.macos", "config.json")
```

### 2.4 App Paths
**File:** `app/cmd/app/app_darwin.go`
**Lines:** 40-41

```go
// Before
var (
    isApp           = updater.BundlePath != ""
    appLogPath      = filepath.Join(os.Getenv("HOME"), ".ollama", "logs", "app.log")
    launchAgentPath = filepath.Join(os.Getenv("HOME"), "Library", "LaunchAgents", "com.ollama.ollama.plist")
)

// After
var (
    isApp           = updater.BundlePath != ""
    appLogPath      = filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "app.reckr.hushbeam.macos", "logs", "app.log")
    launchAgentPath = filepath.Join(os.Getenv("HOME"), "Library", "LaunchAgents", "app.reckr.hushbeam.macos.ollama.plist")
)
```

### 2.5 Keypair Path
**File:** `cmd/cmd.go`
**Lines:** 1585-1593

```go
// Before
privKeyPath := filepath.Join(home, ".ollama", "id_ed25519")
pubKeyPath := filepath.Join(home, ".ollama", "id_ed25519.pub")

// After
privKeyPath := filepath.Join(home, "Library", "Application Support", "app.reckr.hushbeam.macos", "id_ed25519")
pubKeyPath := filepath.Join(home, "Library", "Application Support", "app.reckr.hushbeam.macos", "id_ed25519.pub")
```

## Phase 3: macOS App Bundle

### 3.1 Rename App Bundle
```bash
mv app/darwin/Ollama.app app/darwin/HushBeam-Ollama.app
```

### 3.2 Update Info.plist
**File:** `app/darwin/HushBeam-Ollama.app/Contents/Info.plist`

```xml
<!-- Before -->
<key>CFBundleDisplayName</key>
<string>Ollama</string>
<key>CFBundleExecutable</key>
<string>Ollama</string>
<key>CFBundleIdentifier</key>
<string>com.electron.ollama</string>
<key>CFBundleName</key>
<string>Ollama</string>

<!-- After -->
<key>CFBundleDisplayName</key>
<string>HushBeam-Ollama</string>
<key>CFBundleExecutable</key>
<string>HushBeam-Ollama</string>
<key>CFBundleIdentifier</key>
<string>app.reckr.hushbeam.ollama</string>
<key>CFBundleName</key>
<string>HushBeam-Ollama</string>
```

Also update URL scheme:
```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>hushbeam-ollama</string>
</array>
```

### 3.3 Update LaunchAgent Plist
**File:** `app/darwin/HushBeam-Ollama.app/Contents/Library/LaunchAgents/app.reckr.hushbeam.ollama.plist`

```xml
<key>Label</key>
<string>app.reckr.hushbeam.ollama</string>
```

## Phase 4: Build Script Updates

### 4.1 Build Script
**File:** `scripts/build_darwin.sh`

Key changes:
- Change `VOL_NAME` default from "Ollama" to "HushBeam-Ollama"
- Update binary output names
- Update app bundle paths
- Update code signing identifiers

## Phase 5: Process Control for HushBeam Integration

### 5.1 How HushBeam Will Control hushbeam-ollama

The hushbeam-ollama process should be started by HushBeam as a child process:

```swift
// In HushBeam Swift code
let ollamaPath = Bundle.main.path(forResource: "hushbeam-ollama", ofType: nil)
let process = Process()
process.executableURL = URL(fileURLWithPath: ollamaPath!)
process.arguments = ["serve"]
process.environment = [
    "HUSHBEAM_OLLAMA_HOST": "127.0.0.1:0",  // Random port
    "HUSHBEAM_OLLAMA_MODELS": modelPath
]

// Start
try process.run()

// Get the port from server output or a known location

// Stop
process.terminate()  // Sends SIGTERM
```

### 5.2 Port Discovery

Option A: Use a fixed port (not recommended for bundled apps)
Option B: Pass port via environment variable
Option C: Write port to a known file location after startup
Option D: Parse stdout for port announcement (current Ollama behavior)

**Recommendation:** Use a pipe or file-based port announcement:
- hushbeam-ollama writes port to `~/Library/Application Support/app.reckr.hushbeam.macos/server.port`
- HushBeam reads this file after process starts

## File Change Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `cmd/cmd.go:1691` | Modify | CLI command name |
| `cmd/cmd.go:1585-1593` | Modify | Keypair paths |
| `envconfig/config.go:85-98` | Modify | Models directory |
| `app/server/server_unix.go:18-21` | Modify | PID and log paths |
| `app/store/store.go:190,202` | Modify | DB and config paths |
| `app/cmd/app/app_darwin.go:40-41` | Modify | App log and LaunchAgent paths |
| `app/darwin/Ollama.app/` | Rename | Rename to HushBeam-Ollama.app |
| `app/darwin/.../Info.plist` | Modify | Bundle identifiers |
| `app/darwin/.../com.ollama.ollama.plist` | Rename+Modify | LaunchAgent |
| `scripts/build_darwin.sh` | Modify | Build output names |

## Testing Checklist

- [ ] Binary builds successfully
- [ ] Process name shows as `hushbeam-ollama` in Activity Monitor
- [ ] Models are stored in correct directory
- [ ] Logs are written to correct location
- [ ] Server starts and responds on HTTP API
- [ ] Process terminates cleanly on SIGTERM
- [ ] No conflicts with system-installed Ollama

## Future Considerations

1. **Environment Variable Prefix**: Consider prefixing all env vars with `HUSHBEAM_` for clarity
2. **Upstream Sync**: Keep changes minimal to ease upstream merges
3. **Shared Libraries**: May need to bundle Metal/GPU libraries
4. **Code Signing**: Will need proper Apple Developer certificates for distribution

## References

- HushBeam v0.1 Decision Document
- HushBeam MVP Plan
- Ollama Architecture Documentation
