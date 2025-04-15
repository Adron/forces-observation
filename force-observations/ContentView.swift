//
//  ContentView.swift
//  force-observations
//
//  Created by Adron Hall on 4/15/25.
//

import SwiftUI
import AVFoundation

class CameraManager: ObservableObject {
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var errorMessage: String?
    
    init() {
        print("CameraManager initialized")
        // Don't discover cameras in init, wait for explicit call
    }
    
    func discoverCameras() {
        print("Starting camera discovery...")
        
        do {
            // First check if we have permission
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            print("Camera authorization status: \(status.rawValue)")
            
            guard status == .authorized else {
                throw NSError(domain: "CameraManager", 
                            code: 1, 
                            userInfo: [NSLocalizedDescriptionKey: "Camera access not authorized. Current status: \(status.rawValue)"])
            }
            
            // Clear existing cameras
            availableCameras = []
            selectedCamera = nil
            
            // Try different device types available on macOS
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .external
            ]
            
            print("Creating discovery session with device types: \(deviceTypes)")
            
            // Create discovery session in a safe way
            let discoverySession = try AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )
            
            print("Discovery session created successfully")
            print("Found \(discoverySession.devices.count) devices")
            
            // Safely collect device information
            var devices: [AVCaptureDevice] = []
            for device in discoverySession.devices {
                print("Device: \(device.localizedName) (Type: \(device.deviceType), UniqueID: \(device.uniqueID))")
                devices.append(device)
            }
            
            // Update on main thread
            DispatchQueue.main.async {
                self.availableCameras = devices
                self.selectedCamera = devices.first
                self.errorMessage = nil
            }
            
        } catch {
            print("Error in discoverCameras: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.availableCameras = []
                self.selectedCamera = nil
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var permissionGranted = false
    @State private var showingError = false
    
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
            
            Picker("Select Camera", selection: $cameraManager.selectedCamera) {
                Text("No Camera").tag(nil as AVCaptureDevice?)
                ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                    Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                }
            }
            .pickerStyle(.menu)
            .padding()
            
            if let selectedCamera = cameraManager.selectedCamera {
                Text("Selected: \(selectedCamera.localizedName)")
                    .padding()
            } else {
                Text("No camera selected")
                    .padding()
            }
        }
        .padding()
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
            // Small delay to ensure UI is ready
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
                        // Small delay to ensure UI is ready
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
