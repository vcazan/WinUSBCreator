import Foundation

/// Main service that orchestrates USB creation
class USBService {
    private let diskUtility = DiskUtility()
    private let isoService = ISOService()
    
    // FAT32 file size limit (4GB - 1 byte)
    private let fat32MaxFileSize: Int64 = 4_294_967_295
    
    /// Create a bootable Windows USB drive
    func createBootableUSB(
        iso: ISOInfo,
        drive: USBDrive,
        progressHandler: @escaping (CreationState) -> Void
    ) async throws {
        var isoMountPoint: String?
        
        do {
            // Step 1: Mount the ISO first to check file sizes
            print("[USBService] Step 1: Mounting ISO...")
            progressHandler(.mounting)
            isoMountPoint = try await isoService.mountISO(at: iso.path)
            
            guard let mountPoint = isoMountPoint else {
                print("[USBService] ERROR: Mount point is nil")
                throw USBCreatorError.mountFailed
            }
            print("[USBService] ISO mounted at: \(mountPoint)")
            
            // Step 2: Check if any file exceeds FAT32 limit
            print("[USBService] Step 2: Checking for large files...")
            let hasLargeFiles = try await checkForLargeFiles(mountPoint: mountPoint)
            print("[USBService] Has files > 4GB: \(hasLargeFiles)")
            
            // Step 3: Format the USB drive
            print("[USBService] Step 3: Formatting USB drive...")
            progressHandler(.formatting)
            let useGPT: Bool
            if hasLargeFiles {
                print("[USBService] Using exFAT format (GPT)")
                try await diskUtility.formatDiskExFAT(devicePath: drive.devicePath, name: "WINUSB")
                useGPT = true
            } else {
                print("[USBService] Using FAT32 format (MBR)")
                try await diskUtility.formatDisk(devicePath: drive.devicePath, name: "WINUSB")
                useGPT = false
            }
            print("[USBService] Format complete")
            
            // Small delay to let the system recognize the formatted drive
            print("[USBService] Waiting for drive to mount...")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Step 4: Get USB mount point
            print("[USBService] Step 4: Getting USB mount point...")
            let usbMountPoint = try await getUSBMountPoint(for: drive, useGPT: useGPT)
            print("[USBService] USB mounted at: \(usbMountPoint)")
            
            // Step 5: Copy all files (no splitting needed with exFAT)
            print("[USBService] Step 5: Copying files...")
            try await copyFiles(
                from: mountPoint,
                to: usbMountPoint,
                progressHandler: progressHandler
            )
            print("[USBService] Copy complete")
            
            // Step 6: Finalize
            print("[USBService] Step 6: Finalizing...")
            progressHandler(.finalizing)
            
            // Sync filesystem
            _ = try await runCommand("/bin/sync", arguments: [])
            
            // Unmount ISO
            if let mp = isoMountPoint {
                try? await isoService.unmountISO(mountPoint: mp)
            }
            
            print("[USBService] SUCCESS: Bootable USB created!")
            progressHandler(.completed)
            
        } catch {
            print("[USBService] ERROR: \(error)")
            // Cleanup on error
            if let mp = isoMountPoint {
                try? await isoService.unmountISO(mountPoint: mp)
            }
            throw error
        }
    }
    
    /// Check if any file in the ISO exceeds FAT32 limit
    private func checkForLargeFiles(mountPoint: String) async throws -> Bool {
        print("[USBService] Getting ISO contents from: \(mountPoint)")
        let files = try await isoService.getISOContents(mountPoint: mountPoint)
        print("[USBService] Found \(files.count) files in ISO")
        let largeFiles = files.filter { $0.size > fat32MaxFileSize }
        if !largeFiles.isEmpty {
            print("[USBService] Large files (>4GB): \(largeFiles.map { "\($0.path) (\($0.size) bytes)" })")
        }
        return !largeFiles.isEmpty
    }
    
    /// Get the mount point for a USB drive
    private func getUSBMountPoint(for drive: USBDrive, useGPT: Bool = false) async throws -> String {
        // For GPT (exFAT): s1 = EFI partition, s2 = data partition
        // For MBR (FAT32): s1 = data partition
        let partitionSuffix = useGPT ? "s2" : "s1"
        let partitionId = drive.id + partitionSuffix
        let partitionPath = "/dev/\(partitionId)"
        print("[USBService] Looking for partition: \(partitionPath)")
        
        // Try to mount and get mount point
        let mountPoint = try await diskUtility.mountDisk(devicePath: partitionPath)
        print("[USBService] Partition mounted at: \(mountPoint)")
        return mountPoint
    }
    
    /// Copy files from ISO to USB
    private func copyFiles(
        from source: String,
        to destination: String,
        progressHandler: @escaping (CreationState) -> Void
    ) async throws {
        let fileManager = FileManager.default
        
        // Get all files and total size
        let files = try await isoService.getISOContents(mountPoint: source)
        let totalSize = files.reduce(0) { $0 + $1.size }
        
        var copiedSize: Int64 = 0
        
        // Initial progress update
        progressHandler(.copying(progress: 0.01, currentFile: "Preparing...", bytesCopied: 0, totalBytes: totalSize))
        
        for (relativePath, size) in files {
            let fileName = (relativePath as NSString).lastPathComponent
            
            // Update progress before copying (shows current file)
            let progress = totalSize > 0 ? Double(copiedSize) / Double(totalSize) : 0
            progressHandler(.copying(progress: min(progress, 0.99), currentFile: fileName, bytesCopied: copiedSize, totalBytes: totalSize))
            
            let sourcePath = source + relativePath
            let destPath = destination + relativePath
            
            // Create directory structure
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? fileManager.createDirectory(
                atPath: destDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Remove existing file if present
            try? fileManager.removeItem(atPath: destPath)
            
            // For large files (>50MB), use streaming copy with progress
            if size > 50_000_000 {
                try await copyLargeFile(
                    from: sourcePath,
                    to: destPath,
                    fileSize: size,
                    alreadyCopied: copiedSize,
                    totalSize: totalSize,
                    fileName: fileName,
                    progressHandler: progressHandler
                )
            } else {
                // Small files - regular copy
                do {
                    try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                } catch {
                    throw USBCreatorError.copyFailed(error.localizedDescription)
                }
            }
            
            copiedSize += size
        }
        
        progressHandler(.copying(progress: 0.99, currentFile: "Finishing...", bytesCopied: totalSize, totalBytes: totalSize))
    }
    
    /// Copy a large file with progress updates
    private func copyLargeFile(
        from sourcePath: String,
        to destPath: String,
        fileSize: Int64,
        alreadyCopied: Int64,
        totalSize: Int64,
        fileName: String,
        progressHandler: @escaping (CreationState) -> Void
    ) async throws {
        guard let inputStream = InputStream(fileAtPath: sourcePath) else {
            throw USBCreatorError.copyFailed("Cannot read \(fileName)")
        }
        
        guard let outputStream = OutputStream(toFileAtPath: destPath, append: false) else {
            throw USBCreatorError.copyFailed("Cannot write \(fileName)")
        }
        
        inputStream.open()
        outputStream.open()
        
        defer {
            inputStream.close()
            outputStream.close()
        }
        
        let bufferSize = 1024 * 1024 // 1MB buffer
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var fileWritten: Int64 = 0
        var lastUpdate = Date()
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
            
            if bytesRead < 0 {
                throw USBCreatorError.copyFailed("Read error: \(fileName)")
            }
            
            if bytesRead == 0 {
                break
            }
            
            var bytesWritten = 0
            while bytesWritten < bytesRead {
                let written = buffer.withUnsafeBufferPointer { bufferPointer in
                    outputStream.write(bufferPointer.baseAddress! + bytesWritten, maxLength: bytesRead - bytesWritten)
                }
                if written < 0 {
                    throw USBCreatorError.copyFailed("Write error: \(fileName)")
                }
                bytesWritten += written
            }
            
            fileWritten += Int64(bytesRead)
            
            // Update progress every 100ms
            let now = Date()
            if now.timeIntervalSince(lastUpdate) >= 0.1 {
                lastUpdate = now
                let currentBytes = alreadyCopied + fileWritten
                let overallProgress = Double(currentBytes) / Double(max(totalSize, 1))
                progressHandler(.copying(
                    progress: min(overallProgress, 0.99),
                    currentFile: fileName,
                    bytesCopied: currentBytes,
                    totalBytes: totalSize
                ))
                
                // Yield to allow UI updates
                await Task.yield()
            }
        }
    }
    
    /// Run a shell command
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
