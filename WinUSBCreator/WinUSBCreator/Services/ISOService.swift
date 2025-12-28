import Foundation

/// Handles ISO mounting and file operations
actor ISOService {
    
    /// Mount an ISO file and return the mount point
    func mountISO(at path: URL) async throws -> String {
        let filePath = path.path
        print("[ISOService] Mounting ISO at path: \(filePath)")
        
        // Use plist output for reliable parsing
        let result = try await runCommand("/usr/bin/hdiutil", arguments: [
            "attach",
            "-readonly",
            "-nobrowse",
            "-plist",
            filePath
        ])
        
        print("[ISOService] hdiutil output length: \(result.count) characters")
        print("[ISOService] hdiutil output preview: \(String(result.prefix(500)))")
        
        // Parse plist output
        guard let data = result.data(using: .utf8) else {
            print("[ISOService] ERROR: Could not convert result to data")
            throw USBCreatorError.mountFailed
        }
        
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            print("[ISOService] Parsed plist type: \(type(of: plist))")
            
            guard let dict = plist as? [String: Any] else {
                print("[ISOService] ERROR: plist is not a dictionary. Content: \(plist)")
                throw USBCreatorError.mountFailed
            }
            
            print("[ISOService] Plist keys: \(dict.keys)")
            
            guard let entities = dict["system-entities"] as? [[String: Any]] else {
                print("[ISOService] ERROR: No system-entities found. Dict: \(dict)")
                throw USBCreatorError.mountFailed
            }
            
            print("[ISOService] Found \(entities.count) system-entities")
            
            // Find the mount point from system-entities
            for (index, entity) in entities.enumerated() {
                print("[ISOService] Entity \(index): \(entity)")
                if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                    print("[ISOService] SUCCESS: Found mount point: \(mountPoint)")
                    return mountPoint
                }
            }
            
            print("[ISOService] ERROR: No mount-point found in any entity")
        } catch {
            print("[ISOService] ERROR: Plist parsing failed: \(error)")
            print("[ISOService] Raw output: \(result)")
            throw USBCreatorError.mountFailed
        }
        
        throw USBCreatorError.mountFailed
    }
    
    /// Unmount an ISO
    func unmountISO(mountPoint: String) async throws {
        _ = try? await runCommand("/usr/bin/hdiutil", arguments: [
            "unmount",
            mountPoint
        ])
    }
    
    /// Get all files in the mounted ISO with their sizes
    func getISOContents(mountPoint: String) async throws -> [(path: String, size: Int64)] {
        var files: [(path: String, size: Int64)] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: mountPoint),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }
        
        while let url = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if resourceValues.isRegularFile == true {
                    let relativePath = url.path.replacingOccurrences(of: mountPoint, with: "")
                    let size = Int64(resourceValues.fileSize ?? 0)
                    files.append((path: relativePath, size: size))
                }
            } catch {
                continue
            }
        }
        
        return files
    }
    
    /// Calculate total size of ISO contents
    func getTotalSize(mountPoint: String) async throws -> Int64 {
        let files = try await getISOContents(mountPoint: mountPoint)
        return files.reduce(0) { $0 + $1.size }
    }
    
    /// Check if install.wim exists and get its size
    func getInstallWimInfo(mountPoint: String) async throws -> (exists: Bool, size: Int64, path: String) {
        let possiblePaths = [
            "/sources/install.wim",
            "/Sources/install.wim",
            "/sources/install.esd",
            "/Sources/install.esd"
        ]
        
        for relativePath in possiblePaths {
            let fullPath = mountPoint + relativePath
            
            if FileManager.default.fileExists(atPath: fullPath) {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: fullPath)
                    let size = attrs[.size] as? Int64 ?? 0
                    return (exists: true, size: size, path: relativePath)
                } catch {
                    continue
                }
            }
        }
        
        return (exists: false, size: 0, path: "")
    }
    
    /// Run a shell command and return output
    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        print("[ISOService] Running: \(command) \(arguments.joined(separator: " "))")
        
        do {
            try process.run()
        } catch {
            print("[ISOService] ERROR: Failed to run process: \(error)")
            throw error
        }
        
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        print("[ISOService] Exit code: \(process.terminationStatus)")
        if !stderr.isEmpty {
            print("[ISOService] STDERR: \(stderr)")
        }
        
        // If command failed, include stderr in output for debugging
        if process.terminationStatus != 0 {
            print("[ISOService] Command failed with exit code \(process.terminationStatus)")
            return stderr.isEmpty ? stdout : stderr
        }
        
        return stdout
    }
}

