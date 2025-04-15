//
//  ContentView.swift
//  force-observations
//
//  Created by Adron Hall on 4/15/25.
//

import SwiftUI
import AVFoundation
import OSLog

enum CameraError: LocalizedError {
    case notAuthorized
    case noCamerasAvailable
    case cameraInUse
    case configurationFailed
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
    
    private let logger = Logger(subsystem: "dpm.force-observations", category: "CameraManager")
    
    init() {
        logger.debug("CameraManager initialized")
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
            
            logger.debug("Discovery session created successfully")
            logger.debug("Found \(discoverySession.devices.count) devices")
            
            if discoverySession.devices.isEmpty {
                handleError(.noCamerasAvailable)
                return
            }
            
            var devices: [AVCaptureDevice] = []
            for device in discoverySession.devices {
                logger.debug("Device: \(device.localizedName) (UniqueID: \(device.uniqueID))")
                
                // Check if camera is available
                if device.isConnected && !device.isSuspended {
                    devices.append(device)
                } else {
                    logger.warning("Camera \(device.localizedName) is not available (connected: \(device.isConnected), suspended: \(device.isSuspended))")
                }
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

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var permissionGranted = false
    
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
                        Button(action: { /* Show cameras action */ }) {
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
}

#Preview {
    ContentView()
}
