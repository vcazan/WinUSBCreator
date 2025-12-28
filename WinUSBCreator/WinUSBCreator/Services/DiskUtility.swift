import Foundation

/// Handles disk operations using macOS command-line utilities
actor DiskUtility {
    
    /// Get all removable USB drives
    func getRemovableDrives() async throws -> [USBDrive] {
        // Use diskutil to list all disks in plist format
        let output = try await runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", "external", "physical"])
        
        guard let data = output.data(using: .utf8) else {
            return []
        }
        
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any],
              let allDisks = dict["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }
        
        var drives: [USBDrive] = []
        
        for disk in allDisks {
            guard let deviceIdentifier = disk["DeviceIdentifier"] as? String else {
                continue
            }
            
            // Size can come as Int, Int64, or NSNumber - handle all cases
            let size: Int64
            if let s = disk["Size"] as? Int64 {
                size = s
            } else if let s = disk["Size"] as? Int {
                size = Int64(s)
            } else if let s = disk["Size"] as? NSNumber {
                size = s.int64Value
            } else {
                continue
            }
            
            // Get more info about this disk
            let devicePath = "/dev/\(deviceIdentifier)"
            let info = try? await getDiskInfo(deviceIdentifier: deviceIdentifier)
            
            // Use media name first (more descriptive), fallback to volume name
            var name = deviceIdentifier
            if let mediaName = info?.mediaName, !mediaName.isEmpty {
                name = mediaName
            } else if let volumeName = info?.volumeName, !volumeName.isEmpty {
                name = volumeName
            }
            
            let isRemovable = info?.isRemovable ?? true
            
            // Filter out small drives (< 4GB) and internal drives
            if size >= 4_000_000_000 && isRemovable {
                let drive = USBDrive(
                    id: deviceIdentifier,
                    name: name,
                    devicePath: devicePath,
                    size: size,
                    isRemovable: isRemovable
                )
                drives.append(drive)
            }
        }
        
        return drives
    }
    
    /// Get detailed disk info
    private func getDiskInfo(deviceIdentifier: String) async throws -> DiskInfo? {
        let output = try await runCommand("/usr/sbin/diskutil", arguments: ["info", "-plist", deviceIdentifier])
        
        guard let data = output.data(using: .utf8) else {
            return nil
        }
        
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any] else {
            return nil
        }
        
        // Get volume name - check if it's a non-empty string
        var volumeName: String? = nil
        if let vn = dict["VolumeName"] as? String, !vn.isEmpty {
            volumeName = vn
        }
        
        return DiskInfo(
            volumeName: volumeName,
            mediaName: dict["MediaName"] as? String,
            isRemovable: dict["Removable"] as? Bool ?? false,
            isEjectable: dict["Ejectable"] as? Bool ?? false,
            fileSystem: dict["FilesystemType"] as? String
        )
    }
    
    /// Format a disk as MS-DOS (FAT32) with MBR scheme
    /// This is needed for UEFI boot compatibility on older systems
    func formatDisk(devicePath: String, name: String = "WINUSB") async throws {
        print("[DiskUtility] Formatting \(devicePath) as FAT32 (MBR)")
        // Unmount the disk first
        _ = try? await runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", devicePath])
        
        // Format as MS-DOS FAT32 with MBR
        let result = try await runCommand("/usr/sbin/diskutil", arguments: [
            "eraseDisk",
            "MS-DOS",
            name,
            "MBR",
            devicePath
        ])
        
        print("[DiskUtility] Format result: \(result)")
        
        if result.contains("Error") || result.contains("failed") {
            print("[DiskUtility] ERROR: Format failed")
            throw USBCreatorError.formatFailed
        }
        print("[DiskUtility] Format successful")
    }
    
    /// Format a disk as exFAT with GPT scheme
    /// Used when ISO contains files > 4GB (FAT32 limit)
    /// All modern UEFI systems support exFAT boot
    func formatDiskExFAT(devicePath: String, name: String = "WINUSB") async throws {
        print("[DiskUtility] Formatting \(devicePath) as exFAT (GPT)")
        // Unmount the disk first
        _ = try? await runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", devicePath])
        
        // Format as exFAT with GPT (required for UEFI)
        let result = try await runCommand("/usr/sbin/diskutil", arguments: [
            "eraseDisk",
            "ExFAT",
            name,
            "GPT",
            devicePath
        ])
        
        print("[DiskUtility] Format result: \(result)")
        
        if result.contains("Error") || result.contains("failed") {
            print("[DiskUtility] ERROR: Format failed")
            throw USBCreatorError.formatFailed
        }
        print("[DiskUtility] Format successful")
    }
    
    /// Mount a disk and return the mount point
    func mountDisk(devicePath: String) async throws -> String {
        let identifier = devicePath.replacingOccurrences(of: "/dev/", with: "")
        print("[DiskUtility] Mounting \(identifier)")
        
        // Try to mount
        let mountResult = try await runCommand("/usr/sbin/diskutil", arguments: ["mount", identifier])
        print("[DiskUtility] Mount result: \(mountResult)")
        
        // Find the mount point
        let output = try await runCommand("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier])
        
        guard let data = output.data(using: .utf8) else {
            print("[DiskUtility] ERROR: Could not get disk info data")
            throw USBCreatorError.mountFailed
        }
        
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any],
              let mountPoint = dict["MountPoint"] as? String,
              !mountPoint.isEmpty else {
            print("[DiskUtility] ERROR: No MountPoint in disk info. Dict: \(plist)")
            throw USBCreatorError.mountFailed
        }
        
        return mountPoint
    }
    
    /// Unmount a disk
    func unmountDisk(devicePath: String) async throws {
        _ = try? await runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", devicePath])
    }
    
    /// Eject a disk
    func ejectDisk(devicePath: String) async throws {
        _ = try? await runCommand("/usr/sbin/diskutil", arguments: ["eject", devicePath])
    }
    
    /// Run a shell command and return output
    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Disk info structure
struct DiskInfo {
    let volumeName: String?
    let mediaName: String?
    let isRemovable: Bool
    let isEjectable: Bool
    let fileSystem: String?
}
