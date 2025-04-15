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
    @Published var selectedCameras: Set<AVCaptureDevice> = []
    @Published var errorMessage: String?
    
    init() {
        print("CameraManager initialized")
    }
    
    func discoverCameras() {
        print("Starting camera discovery...")
        
        do {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            print("Camera authorization status: \(status.rawValue)")
            
            guard status == .authorized else {
                throw NSError(domain: "CameraManager", 
                            code: 1, 
                            userInfo: [NSLocalizedDescriptionKey: "Camera access not authorized. Current status: \(status.rawValue)"])
            }
            
            availableCameras = []
            selectedCameras = []
            
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .external
            ]
            
            print("Creating discovery session with device types: \(deviceTypes)")
            let discoverySession = try AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )
            
            print("Discovery session created successfully")
            print("Found \(discoverySession.devices.count) devices")
            
            var devices: [AVCaptureDevice] = []
            for device in discoverySession.devices {
                print("Device: \(device.localizedName) (Type: \(device.deviceType), UniqueID: \(device.uniqueID))")
                devices.append(device)
            }
            
            DispatchQueue.main.async {
                self.availableCameras = devices
                // Select the first camera by default
                if let firstCamera = devices.first {
                    self.selectedCameras.insert(firstCamera)
                }
                self.errorMessage = nil
            }
            
        } catch {
            print("Error in discoverCameras: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.availableCameras = []
                self.selectedCameras = []
            }
        }
    }
    
    func toggleCameraSelection(_ camera: AVCaptureDevice) {
        if selectedCameras.contains(camera) {
            selectedCameras.remove(camera)
        } else {
            selectedCameras.insert(camera)
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
                .frame(maxHeight: 300)
            }
            
            if !cameraManager.selectedCameras.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Cameras:")
                        .font(.headline)
                    
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
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
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
