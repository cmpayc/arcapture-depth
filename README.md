# ARCapture

Utility allows to capture videos from ARKit scene and export to Photos app.

## Integration

#### CocoaPods (iOS 13+)

You can use [CocoaPods](http://cocoapods.org/) to install `ARCapture` by adding it to your `Podfile`:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'MyApp' do
    pod 'ARCapture', :git => 'https://gitlab.com/seriyvolk83/arcapture.git'
end
```

#### Manually (iOS 13+)

To use this library in your project manually you may:

1. for Projects, just drag needed *.swift files to the project tree
2. for Workspaces, to the same

## Usage

1. Add the following into `Info.plist`.
```
<key>NSCameraUsageDescription</key>
<string>Will allow to use AR features.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Export captured photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Export captured photos and videos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Will record audio for the video.</string>
```

2. Use this example to implement client code:

```swift

private var capture: ARCapture?
...

override func viewDidLoad() {
    super.viewDidLoad()

    // Create a new scene
    let scene = SCNScene()
    ...
    // TODO Setup ARSCNView with the scene
    // sceneView.scene = scene
    
    // Setup ARCapture
    capture = ARCapture(view: sceneView)

}

/// "Record" button action handler
@IBAction func recordAction(_ sender: UIButton) {
    capture?.start()
}

/// "Stop" button action handler
@IBAction func stopAction(_ sender: UIButton) {
    capture?.stop({ (status) in
        print("Video exported: \(status)")
    })
}
```
