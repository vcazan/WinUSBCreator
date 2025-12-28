import Foundation

// MARK: - USB Drive Model
struct USBDrive: Identifiable, Hashable {
    let id: String
    let name: String
    let devicePath: String
    let size: Int64
    let isRemovable: Bool
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var displayName: String {
        "\(name) (\(formattedSize))"
    }
}

// MARK: - ISO Info Model
struct ISOInfo {
    let path: URL
    let name: String
    let size: Int64
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Creation State
enum CreationState: Equatable {
    case idle
    case formatting
    case mounting
    case copying(progress: Double, currentFile: String, bytesCopied: Int64, totalBytes: Int64)
    case splitting
    case finalizing
    case completed
    case failed(error: String)
    
    var description: String {
        switch self {
        case .idle:
            return "Ready to create"
        case .formatting:
            return "Formatting USB drive..."
        case .mounting:
            return "Mounting ISO..."
        case .copying(_, let file, _, _):
            return file
        case .splitting:
            return "Splitting large files..."
        case .finalizing:
            return "Finalizing..."
        case .completed:
            return "Completed successfully!"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    var progress: Double {
        switch self {
        case .idle: return 0
        case .formatting: return 0.05
        case .mounting: return 0.1
        case .copying(let progress, _, _, _): return 0.1 + (progress * 0.75)
        case .splitting: return 0.9
        case .finalizing: return 0.95
        case .completed: return 1.0
        case .failed: return 0
        }
    }
    
    var isInProgress: Bool {
        switch self {
        case .idle, .completed, .failed:
            return false
        default:
            return true
        }
    }
    
    var bytesCopied: Int64 {
        if case .copying(_, _, let bytes, _) = self {
            return bytes
        }
        return 0
    }
    
    var totalBytes: Int64 {
        if case .copying(_, _, _, let total) = self {
            return total
        }
        return 0
    }
}

// MARK: - App Step
enum AppStep: Int, CaseIterable {
    case selectISO = 0
    case selectUSB = 1
    case create = 2
    
    var title: String {
        switch self {
        case .selectISO: return "Select ISO"
        case .selectUSB: return "Select USB"
        case .create: return "Create"
        }
    }
    
    var icon: String {
        switch self {
        case .selectISO: return "doc.badge.gearshape"
        case .selectUSB: return "externaldrive.fill.badge.plus"
        case .create: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Error Types
enum USBCreatorError: LocalizedError {
    case noISOSelected
    case noUSBSelected
    case mountFailed
    case formatFailed
    case copyFailed(String)
    case insufficientSpace
    case invalidISO
    case permissionDenied
    case splitFailed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .noISOSelected:
            return "No Windows ISO file selected"
        case .noUSBSelected:
            return "No USB drive selected"
        case .mountFailed:
            return "Failed to mount the ISO file"
        case .formatFailed:
            return "Failed to format the USB drive"
        case .copyFailed(let detail):
            return "Failed to copy files: \(detail)"
        case .insufficientSpace:
            return "USB drive doesn't have enough space"
        case .invalidISO:
            return "The selected file is not a valid Windows ISO"
        case .permissionDenied:
            return "Permission denied. Please run with administrator privileges."
        case .splitFailed:
            return "Failed to split install.wim file"
        case .unknown(let message):
            return message
        }
    }
}

