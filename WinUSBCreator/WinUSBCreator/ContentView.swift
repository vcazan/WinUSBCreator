import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = CreatorViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            Group {
                switch viewModel.currentStep {
                case .selectISO:
                    ISOView(viewModel: viewModel)
                case .selectUSB:
                    USBView(viewModel: viewModel)
                case .create:
                    CreateView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Bottom buttons
            HStack {
                if viewModel.currentStep != .selectISO && !viewModel.creationState.isInProgress && viewModel.creationState != .completed {
                    Button("Go Back") {
                        viewModel.goBack()
                    }
                }
                
                Spacer()
                
                if viewModel.creationState == .completed {
                    Button("Done") {
                        viewModel.reset()
                    }
                    .keyboardShortcut(.defaultAction)
                } else if !viewModel.creationState.isInProgress {
                    Button(viewModel.currentStep == .create ? "Create Installer" : "Continue") {
                        if viewModel.currentStep == .create {
                            viewModel.showConfirmation = true
                        } else {
                            viewModel.goNext()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canProceed)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 400)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .confirmationDialog("Create Windows Installer?", isPresented: $viewModel.showConfirmation) {
            Button("Erase Drive and Create", role: .destructive) {
                viewModel.startCreation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All data on \"\(viewModel.selectedDrive?.name ?? "USB")\" will be permanently erased.")
        }
    }
}

// MARK: - ISO Selection
struct ISOView: View {
    @ObservedObject var viewModel: CreatorViewModel
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: "iso")!))
                .resizable()
                .frame(width: 64, height: 64)
            
            VStack(spacing: 6) {
                Text("Select Windows ISO")
                    .font(.title2.weight(.semibold))
                
                if let iso = viewModel.selectedISO {
                    Text("\(iso.name) (\(iso.formattedSize))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose a Windows 11 ISO file to create your installer")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Button(viewModel.selectedISO != nil ? "Choose Different…" : "Choose ISO…") {
                    viewModel.selectISO()
                }
                .controlSize(.large)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Text("Need an ISO?")
                Link("Download from Microsoft", destination: URL(string: "https://www.microsoft.com/software-download/windows11")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDragging ? Color.accentColor : Color.clear, lineWidth: 3)
                .background(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
                .padding(16)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "iso" else { return }
            DispatchQueue.main.async {
                viewModel.handleDroppedISO(url: url)
            }
        }
        return true
    }
}

// MARK: - USB Selection
struct USBView: View {
    @ObservedObject var viewModel: CreatorViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Select USB Drive")
                    .font(.title2.weight(.semibold))
                
                Text("Choose the drive where Windows will be installed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)
            
            // Drive list
            GroupBox {
                if viewModel.isScanning {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 120)
                } else if viewModel.availableDrives.isEmpty {
                    VStack(spacing: 8) {
                        Text("No USB drives found")
                            .foregroundStyle(.secondary)
                        Button("Refresh") {
                            viewModel.scanForDrives()
                        }
                        .controlSize(.small)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                } else {
                    List(viewModel.availableDrives, selection: $viewModel.selectedDrive) { drive in
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading) {
                                Text(drive.name)
                                Text(drive.formattedSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if viewModel.selectedDrive?.id == drive.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedDrive = drive
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 140)
                }
            }
            .padding(.horizontal, 32)
            
            HStack {
                Spacer()
                Button {
                    viewModel.scanForDrives()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(viewModel.isScanning)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            
            Spacer()
            
            Label("All data on the selected drive will be erased", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.bottom, 16)
        }
        .onAppear {
            if viewModel.availableDrives.isEmpty {
                viewModel.scanForDrives()
            }
        }
    }
}

// MARK: - Create View
struct CreateView: View {
    @ObservedObject var viewModel: CreatorViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if viewModel.creationState == .completed {
                completedView
            } else if case .failed(let error) = viewModel.creationState {
                failedView(error)
            } else if viewModel.creationState.isInProgress {
                progressView
            } else {
                readyView
            }
            
            Spacer()
        }
        .padding(32)
    }
    
    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.blue)
            
            VStack(spacing: 6) {
                Text("Ready to Create Installer")
                    .font(.title2.weight(.semibold))
                
                Text("Click Create Installer to begin")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Label(viewModel.selectedISO?.name ?? "—", systemImage: "doc.fill")
                Label(viewModel.selectedDrive?.displayName ?? "—", systemImage: "externaldrive.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.creationState.progress) {
                Text(statusText)
                    .font(.headline)
            } currentValueLabel: {
                if case .copying(_, let file, let bytes, let total) = viewModel.creationState {
                    VStack(spacing: 4) {
                        HStack {
                            Text(file)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(Int(viewModel.creationState.progress * 100))%")
                                .monospacedDigit()
                        }
                        
                        HStack {
                            // Always show bytes transferred
                            Text("\(formatBytes(bytes)) of \(formatBytes(total))")
                            Spacer()
                            // Show speed if available
                            if !viewModel.transferSpeed.isEmpty {
                                Text(viewModel.transferSpeed)
                            }
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .progressViewStyle(.linear)
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if !viewModel.estimatedTimeRemaining.isEmpty {
                Text(viewModel.estimatedTimeRemaining)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 360)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        let mb = Double(bytes) / (1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
    
    private var statusText: String {
        switch viewModel.creationState {
        case .mounting: return "Mounting ISO…"
        case .formatting: return "Formatting drive…"
        case .copying: return "Copying files…"
        case .splitting: return "Optimizing…"
        case .finalizing: return "Finishing up…"
        default: return "Working…"
        }
    }
    
    private var completedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            VStack(spacing: 6) {
                Text("USB Created Successfully")
                    .font(.title2.weight(.semibold))
                
                Text("Restart your Mac and hold Option to boot from USB")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func failedView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            VStack(spacing: 6) {
                Text("Creation Failed")
                    .font(.title2.weight(.semibold))
                
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again") {
                viewModel.creationState = .idle
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class CreatorViewModel: ObservableObject {
    @Published var currentStep: AppStep = .selectISO
    @Published var selectedISO: ISOInfo?
    @Published var selectedDrive: USBDrive?
    @Published var availableDrives: [USBDrive] = []
    @Published var isScanning = false
    @Published var creationState: CreationState = .idle
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showConfirmation = false
    @Published var estimatedTimeRemaining = ""
    @Published var transferSpeed = ""
    
    private var bytesHistory: [(bytes: Int64, time: Date)] = []
    private let diskUtility = DiskUtility()
    private let usbService = USBService()
    
    var canProceed: Bool {
        switch currentStep {
        case .selectISO: return selectedISO != nil
        case .selectUSB: return selectedDrive != nil
        case .create: return selectedISO != nil && selectedDrive != nil
        }
    }
    
    func goNext() {
        guard currentStep.rawValue < AppStep.allCases.count - 1 else { return }
        currentStep = AppStep(rawValue: currentStep.rawValue + 1) ?? .create
    }
    
    func goBack() {
        guard currentStep.rawValue > 0 else { return }
        currentStep = AppStep(rawValue: currentStep.rawValue - 1) ?? .selectISO
    }
    
    func reset() {
        currentStep = .selectISO
        selectedISO = nil
        selectedDrive = nil
        creationState = .idle
        estimatedTimeRemaining = ""
        transferSpeed = ""
    }
    
    func selectISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a Windows 11 ISO file"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            loadISO(from: url)
        }
    }
    
    func handleDroppedISO(url: URL) {
        loadISO(from: url)
    }
    
    private func loadISO(from url: URL) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int64 ?? 0
            selectedISO = ISOInfo(path: url, name: url.lastPathComponent, size: size)
        } catch {
            showError(message: "Could not read ISO: \(error.localizedDescription)")
        }
    }
    
    func scanForDrives() {
        isScanning = true
        Task {
            do {
                let drives = try await diskUtility.getRemovableDrives()
                self.availableDrives = drives
                self.isScanning = false
                if drives.count == 1 && selectedDrive == nil {
                    selectedDrive = drives.first
                }
            } catch {
                self.isScanning = false
                showError(message: "Failed to scan: \(error.localizedDescription)")
            }
        }
    }
    
    func startCreation() {
        guard let iso = selectedISO, let drive = selectedDrive else { return }
        
        bytesHistory = []
        estimatedTimeRemaining = ""
        transferSpeed = ""
        
        Task {
            do {
                try await usbService.createBootableUSB(iso: iso, drive: drive) { [weak self] state in
                    Task { @MainActor in
                        self?.creationState = state
                        self?.updateStats(for: state)
                    }
                }
            } catch {
                creationState = .failed(error: error.localizedDescription)
                estimatedTimeRemaining = ""
                transferSpeed = ""
            }
        }
    }
    
    private func updateStats(for state: CreationState) {
        if state == .completed {
            estimatedTimeRemaining = ""
            transferSpeed = ""
            return
        }
        
        guard case .copying(_, _, let bytes, let total) = state else {
            transferSpeed = ""
            estimatedTimeRemaining = ""
            return
        }
        
        let now = Date()
        bytesHistory.append((bytes, now))
        bytesHistory = bytesHistory.filter { now.timeIntervalSince($0.time) < 10 }
        
        guard bytesHistory.count >= 2, let first = bytesHistory.first else { return }
        
        let elapsed = now.timeIntervalSince(first.time)
        let delta = bytes - first.bytes
        
        guard elapsed > 0.3, delta > 0 else { return }
        
        let speed = Double(delta) / elapsed
        transferSpeed = formatSpeed(speed)
        
        let remaining = total - bytes
        if remaining > 0 {
            let seconds = Double(remaining) / speed
            estimatedTimeRemaining = formatTime(seconds)
        }
    }
    
    private func formatSpeed(_ bps: Double) -> String {
        if bps < 1024 * 1024 {
            return String(format: "%.0f KB/s", bps / 1024)
        }
        return String(format: "%.1f MB/s", bps / (1024 * 1024))
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds > 3600 { return "" }
        if seconds < 60 { return "Less than a minute" }
        return "About \(Int(ceil(seconds / 60))) min"
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

#Preview {
    ContentView()
}
