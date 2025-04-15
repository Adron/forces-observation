# Force Observations

A macOS application for monitoring and analyzing multiple camera feeds simultaneously, with built-in logging capabilities for future computer vision integration.

## Features

- Multi-camera support
- Real-time camera feed display
- Camera selection interface
- Event logging system
- Individual camera windows
- Error handling and recovery

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later
- Swift 5.0 or later
- Camera access permissions

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/force-observations.git
cd force-observations
```

2. Open the project in Xcode:
```bash
open force-observations.xcodeproj
```

3. Build and run the project:
   - Press ⌘R or click the Run button in Xcode
   - Alternatively, select Product > Run from the menu

## Usage

1. Launch the application
2. Grant camera permissions when prompted
3. Select one or more cameras from the available list
4. Click "Show Cameras" to open individual camera windows
5. Each camera window will display:
   - Live camera feed
   - Event log area (5 lines)
   - Error messages (if any)

## Camera Permissions

The application requires camera access to function. If permissions are denied:

1. Open System Settings
2. Navigate to Privacy & Security > Camera
3. Find "Force Observations" in the list
4. Enable camera access

## Troubleshooting

### Common Issues

1. **Camera Not Showing Up**
   - Ensure the camera is properly connected
   - Check if the camera is being used by another application
   - Verify camera permissions

2. **Application Crashes**
   - Check the error log in the camera window
   - Ensure all selected cameras are available
   - Try restarting the application

3. **Black Screen**
   - Verify camera permissions
   - Check if the camera is properly connected
   - Look for error messages in the log area

## Development

### Project Structure

- `ContentView.swift`: Main application view and camera management
- Camera windows are created dynamically for each selected camera

### Adding Features

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request 