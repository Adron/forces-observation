//
//  ContentView.swift
//  force-observations
//
//  Created by Adron Hall on 4/15/25.
//

import SwiftUI
import AVFoundation
import OSLog

enum CameraType {
    case physical
    case virtual
    case screenCapture
    case streaming
    case unknown
    
    var description: String {
        switch self {
        case .physical: return "Physical Camera"
        case .virtual: return "Virtual Camera"
        case .screenCapture: return "Screen Capture"
        case .streaming: return "Streaming Camera"
        case .unknown: return "Unknown Type"
        }
    }
}

enum CameraError: LocalizedError {
    case notAuthorized
    case noCamerasAvailable
    case cameraInUse
    case configurationFailed
    case virtualCameraUnsupported
    case cameraUnavailable
    case streamingError
    case screenCaptureError
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access is not authorized. Please check your privacy settings."
        case .noCamerasAvailable:
            return "No cameras are available. Please check your connections."
        case .cameraInUse:
            return "Camera is currently in use by another application."
        case .configurationFailed:
            return "Failed to configure camera. Please try again."
        case .virtualCameraUnsupported:
            return "This virtual camera is not fully supported. Some features may not work correctly."
        case .cameraUnavailable:
            return "Camera is currently unavailable. Please check the connection and try again."
        case .streamingError:
            return "Error with streaming camera. Please check your streaming software."
        case .screenCaptureError:
            return "Error with screen capture. Please check your screen recording settings."
        case .unknown(let message):
            return message
        }
    }
}

class CameraManager: ObservableObject {
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameras: Set<AVCaptureDevice> = []
    @Published var errorMessage: String?
    @Published var isDiscoveringCameras = false
    @Published var cameraTypes: [String: CameraType] = [:]
    @Published var cameraWarnings: [String: String] = [:]
    
    private let logger = Logger(subsystem: "dpm.force-observations", category: "CameraManager")
    
    // Expanded list of virtual camera identifiers
    private let virtualCameraIdentifiers = [
        "obs-virtual-camera",
        "obs",
        "virtual",
        "screen",
        "desktop",
        "stream",
        "capture",
        "webcam",
        "camera",
        "cam",
        "virtualcam",
        "virtual-cam",
        "virtualcamera",
        "virtual-camera",
        "screen-capture",
        "screen-cam",
        "screen-camera",
        "stream-cam",
        "stream-camera",
        "streaming-cam",
        "streaming-camera"
    ]
    
    // Streaming software identifiers
    private let streamingIdentifiers = [
        "obs",
        "streamlabs",
        "xsplit",
        "wirecast",
        "vMix",
        "restream",
        "streamyard"
    ]
    
    // Screen capture identifiers
    private let screenCaptureIdentifiers = [
        "screen",
        "desktop",
        "display",
        "monitor",
        "capture",
        "recording"
    ]
    
    init() {
        logger.debug("CameraManager initialized")
    }
    
    deinit {
        cleanupAllCameras()
    }
    
    func detectCameraType(_ device: AVCaptureDevice) -> CameraType {
        let deviceName = device.localizedName.lowercased()
        let uniqueID = device.uniqueID.lowercased()
        
        // Check for screen capture
        for identifier in screenCaptureIdentifiers {
            if deviceName.contains(identifier) || uniqueID.contains(identifier) {
                return .screenCapture
            }
        }
        
        // Check for streaming cameras
        for identifier in streamingIdentifiers {
            if deviceName.contains(identifier) || uniqueID.contains(identifier) {
                return .streaming
            }
        }
        
        // Check for virtual cameras
        for identifier in virtualCameraIdentifiers {
            if deviceName.contains(identifier) || uniqueID.contains(identifier) {
                return .virtual
            }
        }
        
        // Check for physical camera indicators
        if deviceName.contains("built-in") || deviceName.contains("face") || deviceName.contains("back") {
            return .physical
        }
        
        return .unknown
    }
    
    func checkCameraHealth(_ device: AVCaptureDevice) -> (isHealthy: Bool, message: String?) {
        // Check basic availability
        guard device.isConnected else {
            return (isHealthy: false, message: "Camera is not connected")
        }
        
        // Check if camera is suspended
        guard !device.isSuspended else {
            return (isHealthy: false, message: "Camera is suspended")
        }
        
        // Check if camera is in use
        do {
            try device.lockForConfiguration()
            device.unlockForConfiguration()
        } catch {
            return (isHealthy: false, message: "Camera is in use by another application")
        }
        
        // Check for virtual camera specific issues
        let type = detectCameraType(device)
        if type == .virtual || type == .streaming || type == .screenCapture {
            // Additional checks for virtual cameras
            if !device.hasMediaType(.video) {
                return (isHealthy: false, message: "Virtual camera does not support video")
            }
            
            // Check for minimum resolution support
            let formats = device.formats
            if formats.isEmpty {
                return (isHealthy: false, message: "Virtual camera has no supported formats")
            }
        }
        
        return (isHealthy: true, message: nil)
    }
    
    private func getCameraWarning(_ device: AVCaptureDevice) -> String? {
        let type = detectCameraType(device)
        
        switch type {
        case .virtual:
            return "⚠️ Virtual Camera: Some features may be limited"
        case .streaming:
            return "⚠️ Streaming Camera: Ensure streaming software is running"
        case .screenCapture:
            return "⚠️ Screen Capture: Performance may be affected"
        case .unknown:
            return "⚠️ Unknown Camera Type: Use with caution"
        default:
            return nil
        }
    }
    
    func discoverCameras() {
        guard !isDiscoveringCameras else {
            logger.debug("Camera discovery already in progress")
            return
        }
        
        isDiscoveringCameras = true
        logger.debug("Starting camera discovery...")
        
        do {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            logger.debug("Camera authorization status: \(status.rawValue)")
            
            switch status {
            case .notDetermined:
                logger.debug("Requesting camera authorization...")
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self = self else { return }
                    if granted {
                        self.discoverAvailableCameras()
                    } else {
                        self.handleError(.notAuthorized)
                    }
                }
            case .authorized:
                discoverAvailableCameras()
            case .denied, .restricted:
                handleError(.notAuthorized)
            @unknown default:
                handleError(.unknown("Unknown authorization status"))
            }
        } catch {
            handleError(.unknown(error.localizedDescription))
        }
    }
    
    private func discoverAvailableCameras() {
        do {
            // Configure discovery session with more specific device types
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .external
            ]
            
            logger.debug("Creating discovery session with device types: \(deviceTypes)")
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )
            
            // Add a small delay to allow system to initialize
            Thread.sleep(forTimeInterval: 0.1)
            
            logger.debug("Discovery session created successfully")
            logger.debug("Found \(discoverySession.devices.count) devices")
            
            if discoverySession.devices.isEmpty {
                handleError(.noCamerasAvailable)
                return
            }
            
            var devices: [AVCaptureDevice] = []
            for device in discoverySession.devices {
                // Check camera health with explicit type annotation
                let healthCheck: (isHealthy: Bool, message: String?) = checkCameraHealth(device)
                if !healthCheck.isHealthy {
                    logger.warning("Camera \(device.localizedName) health check failed: \(healthCheck.message ?? "Unknown reason")")
                    continue
                }
                
                // Detect camera type
                let type = detectCameraType(device)
                cameraTypes[device.uniqueID] = type
                
                // Get and store warning message
                if let warning = getCameraWarning(device) {
                    cameraWarnings[device.uniqueID] = warning
                    logger.warning("\(warning) - \(device.localizedName)")
                }
                
                devices.append(device)
            }
            
            if devices.isEmpty {
                handleError(.noCamerasAvailable)
                return
            }
            
            DispatchQueue.main.async {
                self.availableCameras = devices
                if let firstCamera = devices.first {
                    self.selectedCameras.insert(firstCamera)
                }
                self.errorMessage = nil
                self.isDiscoveringCameras = false
            }
            
        } catch {
            handleError(.unknown(error.localizedDescription))
        }
    }
    
    private func handleError(_ error: CameraError) {
        logger.error("Camera error: \(error.localizedDescription ?? "")")
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.availableCameras = []
            self.selectedCameras = []
            self.isDiscoveringCameras = false
        }
    }
    
    func toggleCameraSelection(_ camera: AVCaptureDevice) {
        do {
            // Try to lock the camera for configuration
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            
            if selectedCameras.contains(camera) {
                selectedCameras.remove(camera)
                logger.debug("Deselected camera: \(camera.localizedName)")
            } else {
                selectedCameras.insert(camera)
                logger.debug("Selected camera: \(camera.localizedName)")
            }
        } catch {
            logger.error("Failed to configure camera \(camera.localizedName): \(error.localizedDescription)")
            handleError(.configurationFailed)
        }
    }
    
    private func addLogMessage(_ message: String) {
        logger.info("\(message)")
        // This will be displayed in the camera window's log area
    }
    
    func cleanupAllCameras() {
        // Stop all camera sessions
        for camera in selectedCameras {
            do {
                try camera.lockForConfiguration()
                camera.unlockForConfiguration()
            } catch {
                logger.error("Error unlocking camera during cleanup: \(error.localizedDescription)")
            }
        }
        
        // Don't clear selections if we're still showing windows
        if selectedCameras.isEmpty {
            availableCameras.removeAll()
        }
    }
}

struct CameraRow: View {
    let camera: AVCaptureDevice
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "video.fill")
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(camera.localizedName)
                    .font(.headline)
                Text(camera.uniqueID)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

struct CameraWindowView: View {
    let camera: AVCaptureDevice
    @StateObject private var cameraManager = CameraManager()
    @State private var session: AVCaptureSession?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var logMessages: [String] = []
    @State private var hasError = false
    @State private var cameraType: CameraType = .unknown
    @State private var showWarning = false
    @State private var warningMessage: String = ""
    @State private var retryCount = 0
    @State private var maxRetries = 3
    private let logger = Logger(subsystem: "dpm.force-observations", category: "CameraWindowView")
    
    var body: some View {
        VStack {
            // Camera Preview
            if hasError {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let previewLayer = previewLayer {
                CameraPreviewView(previewLayer: previewLayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Initializing camera...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Warning Banner
            if showWarning {
                Text(warningMessage)
                    .foregroundColor(.yellow)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            // Log Area
            VStack(alignment: .leading, spacing: 4) {
                ForEach(logMessages, id: \.self) { message in
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .frame(height: 100)
            .padding(8)
            .background(Color.black)
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            checkCameraType()
            setupCamera()
        }
        .onDisappear {
            cleanupCamera()
        }
    }
    
    private func checkCameraType() {
        // Remove the health check logging to resolve type ambiguity
        cameraType = cameraManager.detectCameraType(camera)
        if let warning = cameraManager.cameraWarnings[camera.uniqueID] {
            warningMessage = warning
            showWarning = true
        }
        
        addLogMessage("Camera Type: \(cameraType.description)")
        if showWarning {
            addLogMessage(warningMessage)
        }
    }
    
    private func setupCamera() {
        // Check if camera is still available
        guard camera.isConnected else {
            handleError("Camera is no longer connected")
            return
        }
        
        // Create a new session
        let newSession = AVCaptureSession()
        session = newSession
        
        // Configure session with safety checks
        do {
            // Try to lock the camera for configuration
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            
            // Create input with safety check
            let input = try AVCaptureDeviceInput(device: camera)
            
            // Check if we can add the input
            guard newSession.canAddInput(input) else {
                handleError("Cannot add camera input to session")
                return
            }
            
            // Add input with safety check
            newSession.addInput(input)
            
            // Configure session with safety checks
            if newSession.canSetSessionPreset(.high) {
                newSession.sessionPreset = .high
            } else if newSession.canSetSessionPreset(.medium) {
                newSession.sessionPreset = .medium
            } else {
                newSession.sessionPreset = .low
            }
            
            // Create preview layer with safety check
            let previewLayer = AVCaptureVideoPreviewLayer(session: newSession)
            self.previewLayer = previewLayer
            
            // Start the session on a background thread with safety checks
            DispatchQueue.global(qos: .userInitiated).async {
                self.safeStartSession(newSession)
            }
            
            addLogMessage("Camera initialized: \(camera.localizedName)")
            
        } catch {
            handleError("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    private func safeStartSession(_ session: AVCaptureSession) {
        // Add safety delay
        Thread.sleep(forTimeInterval: 0.2)
        
        // Use a safety wrapper to catch any potential crashes
        if !session.isRunning {
            do {
                try withExtendedLifetime(session) {
                    session.startRunning()
                }
            } catch {
                if retryCount < maxRetries {
                    retryCount += 1
                    addLogMessage("Retry attempt \(retryCount) of \(maxRetries)")
                    Thread.sleep(forTimeInterval: 0.5)
                    safeStartSession(session)
                } else {
                    handleVirtualCameraError(error)
                }
            }
        }
    }
    
    private func handleVirtualCameraError(_ error: Error) {
        switch cameraType {
        case .virtual:
            handleError("Virtual camera failed to start after \(maxRetries) attempts. Please check your virtual camera software.")
        case .streaming:
            handleError("Streaming camera failed to start. Please ensure your streaming software is running.")
        case .screenCapture:
            handleError("Screen capture failed to start. Please check your screen recording settings.")
        default:
            handleError("Failed to start camera session: \(error.localizedDescription)")
        }
    }
    
    private func cleanupCamera() {
        // Stop the session safely
        if let session = session {
            DispatchQueue.global(qos: .userInitiated).async {
                if session.isRunning {
                    do {
                        try withExtendedLifetime(session) {
                            session.stopRunning()
                        }
                    } catch {
                        print("Error stopping session: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Clear references
        session = nil
        previewLayer = nil
        
        // Unlock camera configuration
        do {
            try camera.lockForConfiguration()
            camera.unlockForConfiguration()
        } catch {
            print("Error unlocking camera during cleanup: \(error.localizedDescription)")
        }
    }
    
    private func handleError(_ message: String) {
        hasError = true
        addLogMessage("ERROR: \(message)")
        cleanupCamera()
    }
    
    private func addLogMessage(_ message: String) {
        DispatchQueue.main.async {
            logMessages.append(message)
            if logMessages.count > 5 {
                logMessages.removeFirst()
            }
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = previewLayer
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var permissionGranted = false
    @State private var cameraWindows: [NSWindow] = []
    private let logger = Logger(subsystem: "dpm.force-observations", category: "ContentView")
    
    var body: some View {
        VStack {
            if !permissionGranted {
                VStack(spacing: 16) {
                    Text("Camera permission not granted")
                        .foregroundColor(.red)
                    
                    Button(action: openSystemSettings) {
                        Text("Set Permissions")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
            }
            
            if let error = cameraManager.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            if cameraManager.availableCameras.isEmpty {
                Text("No cameras available")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                HStack(alignment: .top, spacing: 20) {
                    // Left column - Camera list
                    VStack {
                        Text("Available Cameras")
                            .font(.headline)
                            .padding(.bottom, 8)
                        
                        List {
                            ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                                CameraRow(
                                    camera: camera,
                                    isSelected: cameraManager.selectedCameras.contains(camera),
                                    onToggle: { cameraManager.toggleCameraSelection(camera) }
                                )
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                    .frame(minWidth: 200, maxWidth: .infinity, maxHeight: 400)
                    
                    // Center column - Selected cameras
                    VStack(alignment: .leading) {
                        Text("Selected Cameras")
                            .font(.headline)
                            .padding(.bottom, 8)
                        
                        if !cameraManager.selectedCameras.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(cameraManager.selectedCameras), id: \.uniqueID) { camera in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(camera.localizedName)
                                                .font(.subheadline)
                                            Text("ID: \(camera.uniqueID)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(width: 250)
                            .frame(maxHeight: 400)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Text("No cameras selected")
                                .foregroundColor(.gray)
                                .frame(width: 250, height: 100)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .frame(width: 250)
                    
                    // Right column - Buttons
                    VStack(spacing: 12) {
                        Button(action: showCameraWindows) {
                            HStack {
                                Image(systemName: "video.fill")
                                Text("Show Cameras")
                            }
                            .frame(width: 150)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { /* Enable forces vision action */ }) {
                            HStack {
                                Image(systemName: "eye.fill")
                                Text("Enable Forces Vision")
                            }
                            .frame(width: 150)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { /* Show activity log action */ }) {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("Show Activity Log")
                            }
                            .frame(width: 150)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(width: 150)
                    .padding(.top, 8)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 400)
        .onAppear {
            print("ContentView appeared")
            checkCameraPermission()
        }
        .onDisappear {
            cleanupAllWindows()
        }
    }
    
    private func checkCameraPermission() {
        print("Checking camera permission...")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("Current authorization status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            print("Camera access authorized")
            permissionGranted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.cameraManager.discoverCameras()
            }
        case .notDetermined:
            print("Requesting camera access...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("Camera access request result: \(granted)")
                DispatchQueue.main.async {
                    self.permissionGranted = granted
                    if granted {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.cameraManager.discoverCameras()
                        }
                    }
                }
            }
        case .denied:
            print("Camera access denied")
            permissionGranted = false
        case .restricted:
            print("Camera access restricted")
            permissionGranted = false
        @unknown default:
            print("Unknown authorization status")
            permissionGranted = false
        }
    }
    
    private func openSystemSettings() {
        print("Opening system settings...")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func cleanupAllWindows() {
        // Safely close all camera windows
        for window in cameraWindows {
            if window.isVisible {
                // Remove delegate before closing to prevent callbacks
                window.delegate = nil
                window.close()
            }
        }
        
        // Clear window list
        cameraWindows.removeAll()
        
        // Clean up camera manager
        cameraManager.cleanupAllCameras()
    }
    
    private func showCameraWindows() {
        // Create new windows for each selected camera
        for camera in cameraManager.selectedCameras {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "\(camera.localizedName) - Camera Feed"
            window.contentView = NSHostingView(rootView: CameraWindowView(camera: camera))
            
            // Set up window delegate to handle window closing
            let delegate = WindowDelegate { [cameraWindows] in
                DispatchQueue.main.async {
                    // Check if all windows are closed
                    let allWindowsClosed = cameraWindows.allSatisfy { !$0.isVisible }
                    if allWindowsClosed {
                        self.cameraWindows.removeAll()
                    }
                }
            }
            window.delegate = delegate
            
            window.makeKeyAndOrderFront(nil)
            cameraWindows.append(window)
        }
    }
}

// Add WindowDelegate class
class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

#Preview {
    ContentView()
}
