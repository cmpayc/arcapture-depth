//
//  ARCapture.swift
//  ARCapture framework
//
//  Created by Volkov Alexander on 6/6/21.
//  Modified by Sergei Kazakov on 21.08.24.
//

import Foundation
import ARKit
import Photos

// dodo
//AVAudioSession.sharedInstance().setActive(false, options: [])

/// The delegate protocol
public protocol ARCaptureDelegate: class {
    
    /// captured frame handler
    func frame(frame: ARCaptureFrame)
}

/// Utility that allows to capture ARKit scene as a video or a photo.
open class ARCapture {
    
    public enum Status: Int {
        case ready
        /// The current recorder is recording.
        case recording
        /// The current recorder is paused.
        case paused
        
        func isCapturing() -> Bool {
            return self == .recording
        }
    }
    
    public enum AudioPermissions {
        case unknown, enabled, disabled
    }
    
    private let queue = DispatchQueue(label: "ru.frgroup.volk.ARCapture")
    
    /// the delegate
    weak public var delegate: ARCaptureDelegate?
    
    let view: ARSCNView

    private var renderer: SCNRenderer!
    private var displayTimer: CADisplayLink!
    
    var status: Status = .ready
    private var audioPermissions: AudioPermissions = .unknown
    private var recordAudio: Bool = false
    private var isPrepare: Bool = false
    private var prepareCallback: ((Bool)->())? = nil
    
    private var assetCreator: ARAssetCreator?
    private var depthAssetCreator: FileHandle?
    private var frameGenerator: ARFrameGenerator?
    private var needToPause: Bool = false
    private var lastPauseTime: CMTime?
    private var summaryDelay: CMTime?
    private var videoUrl: URL?
    private var depthUrl: URL?
    
    public init?(view: ARSCNView) {
        self.view = view
        initCapture()
    }
    
    private func initCapture() {
        guard let metal = MTLCreateSystemDefaultDevice() else {
            print("[ARCapture] ERROR: Metal is not supported")
            return
        }
        renderer = SCNRenderer(device: metal, options: nil)
        renderer.scene = view.scene
        
        displayTimer = CADisplayLink(target: self, selector: #selector(processFrame))
        //displayTimer.preferredFramesPerSecond = 60
        displayTimer.preferredFramesPerSecond = 30
        displayTimer.add(to: .main, forMode: .common)
        
        
        status = .ready
        displayTimer.isPaused = true
        
    }
    
    // MARK: - API
    
    public func prepare(_ complete: @escaping ((Bool)->())) {
        isPrepare = true
        prepareCallback = complete
        start()
    }
    
    /// Start recording
    /// - Parameter captureType: the capture type. Different values make sence for landscape orientation of the device. In most cases either rendering is incorrect (due to iOS issue) or UX is not good (due to hacks). Find quality is with `.imageCapture`. For portrait orientation use `.renderOriginal`.
    public func start(
        captureType: ARFrameGenerator.CaptureType? = nil,
        captureDepth: ARFrameGenerator.CaptureDepth? = nil
    ) {
        let type: ARFrameGenerator.CaptureType = captureType ?? (ARCapture.Orientation.isPortrait ? .renderOriginal : .imageCapture)
        let depth: ARFrameGenerator.CaptureDepth = captureDepth ?? ARFrameGenerator.CaptureDepth.no
        frameGenerator = ARFrameGenerator(captureType: type, captureDepth: depth)
//        if let currentFrame = view.session.currentFrame {
            
//            // Match clipping
//            renderer.pointOfView?.camera?.zNear = 0.001
//            renderer.pointOfView?.camera?.zFar = 1000
//
//            // Match projection
//            let viewportSize = CGSize(width: view.currentViewport.size.height, height: view.currentViewport.size.width)
//            let orientation: UIInterfaceOrientation = ARCapture.Orientation.isLandscapeLeft ? .landscapeLeft : (ARCapture.Orientation.isLandscapeRight ? .landscapeRight : .portrait)
//            let projection = SCNMatrix4(currentFrame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 1000))
//            renderer.pointOfView?.camera?.projectionTransform = projection
//
//            // Match transform
//            renderer.pointOfView?.simdTransform = currentFrame.camera.viewMatrix(for: orientation).inverse
            
//            // Match clipping
//            renderer.pointOfView?.camera?.zNear = 0.001
//            renderer.pointOfView?.camera?.zFar = 1000
//
//            // Match projection
//            let projection = SCNMatrix4(currentFrame.camera.projectionMatrix(for: .landscapeLeft, viewportSize: view.currentViewport.size, zNear: 0.001, zFar: 1000))
//            renderer.pointOfView?.camera?.projectionTransform = projection
//
//            // Match transform
//            renderer.pointOfView?.simdTransform = currentFrame.camera.viewMatrix(for: .landscapeLeft).inverse
//        }
        
        if (recordAudio) {
            tryEnableAudio { [weak self] in
                self?.status = .recording
                self?.displayTimer.isPaused = false
            }
        } else {
            self.status = .recording
            self.displayTimer.isPaused = false
        }
    }
    
    /// Stop and add video to library if `complete` is provided.
    /// - Parameter complete: the callback used to notify when video is added to Photos. If nil, then video will not be created.
    public func stop(_ complete: ((Bool, URL?)->())? = nil) {
        self.status = .ready
        queue.sync { [weak self] in
            self?.lastPauseTime = nil
            self?.assetCreator?.stop { [weak self] in
                if let url = self?.videoUrl {
                    if let complete = complete {
                        if let depthUrl = self?.depthUrl {
                            self?.addVideoToLibrary(from: url, depthUrl: depthUrl, completed: complete)
                        } else {
                            self?.addVideoToLibrary(from: url, depthUrl: nil, completed: complete)
                        }
                    } else {
                        try? FileManager.default.removeItem(at: url)
                        if let depthUrl = self?.depthUrl {
                            try? FileManager.default.removeItem(at: depthUrl)
                        }
                        complete?(false, nil)
                        if let prepareCallback = self?.prepareCallback, self?.isPrepare == true {
                            prepareCallback(false)
                        }
                    }
                } else {
                    complete?(false, nil)
                    if let prepareCallback = self?.prepareCallback, self?.isPrepare == true {
                        prepareCallback(false)
                    }
                }
                self?.isPrepare = false
                self?.prepareCallback = nil
                self?.displayTimer.isPaused = true
                self?.assetCreator = nil
                self?.depthAssetCreator = nil
                self?.frameGenerator = nil
            }
        }
    }
    
    public func stopPrepare() {
        self.status = .ready
        self.lastPauseTime = nil
        self.assetCreator?.stop { [weak self] in
            if let url = self?.videoUrl {
                try? FileManager.default.removeItem(at: url)
                if let depthUrl = self?.depthUrl {
                    try? FileManager.default.removeItem(at: depthUrl)
                }
                if let prepareCallback = self?.prepareCallback, self?.isPrepare == true {
                    prepareCallback(true)
                }
            } else {
                if let prepareCallback = self?.prepareCallback, self?.isPrepare == true {
                    prepareCallback(false)
                }
            }
            self?.isPrepare = false
            self?.prepareCallback = nil
            self?.displayTimer.isPaused = true
            self?.assetCreator = nil
            self?.frameGenerator = nil
        }
    }
    
    /// Start/stop external frame processor (implementing delegate protocol)
    /// - Parameter start: true - start, false - stop
    public func frameProcessor(start: Bool, captureType: ARFrameGenerator.CaptureType? = nil, captureDepth: ARFrameGenerator.CaptureDepth? = nil) {
        if start {
            let type: ARFrameGenerator.CaptureType = captureType ?? (ARCapture.Orientation.isPortrait ? .renderOriginal : .imageCapture)
            let depth: ARFrameGenerator.CaptureDepth = captureDepth ?? ARFrameGenerator.CaptureDepth.no
            frameGenerator = ARFrameGenerator(captureType: type, captureDepth: depth)
            self.status = .recording
            self.displayTimer.isPaused = false
        }
        else {
            self.status = .ready
            self.displayTimer.isPaused = true
            frameGenerator = nil
        }
    }
    
    /// Capture image
    public func image(captureType: ARFrameGenerator.CaptureType? = nil, captureDepth: ARFrameGenerator.CaptureDepth? = nil) -> UIImage? {
        let type: ARFrameGenerator.CaptureType = captureType ?? (ARCapture.Orientation.isPortrait ? .renderOriginal : .imageCapture)
        let depth: ARFrameGenerator.CaptureDepth = captureDepth ?? ARFrameGenerator.CaptureDepth.no
        let frameGenerator = ARFrameGenerator(captureType: type, captureDepth: depth)
        //guard let frame = frameGenerator.getFrame(from: view, renderer: renderer, time: CACurrentMediaTime()), let buffer = frame.1 else { return nil }
        guard let frame = frameGenerator.getFrame(from: view, renderer: renderer, time: CACurrentMediaTime()) else { return nil }
        let buffer = frame.1
        return UIImage(ciImage: CIImage(cvPixelBuffer: buffer))
    }
    
    
    /// Add video to library from temporary file URL
    /// - Parameters:
    ///   - url: the local file URL
    ///   - completed: the callback
    public func addVideoToLibrary(from url: URL, depthUrl: URL?, completed: @escaping (Bool, URL?)->()) {
        DispatchQueue.global(qos: .background).async {
            let status = PHPhotoLibrary.authorizationStatus()
            if status == .notDetermined {
                PHPhotoLibrary.requestAuthorization() { [weak self] status in
                    self?.addVideoToLibrary(from: url, depthUrl: depthUrl, completed: completed)
                }
            } else if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { saved, error in
                    if let error = error {
                        print("ERROR: \(error)")
                    }
                    do {
                        try FileManager.default.removeItem(at: url)
                    }
                    catch {
                        print("ERROR: \(error)")
                    }
                    completed(error == nil, depthUrl ?? nil)
                }
            } else {
                completed(false, nil)
            }
        }
    }
    
    /// Pause recording
    public func pause() {
        guard status == .recording else { return }
        needToPause = true
    }
    
    /// Enable/disable audio capture for the video
    /// - Parameter enable: true - will include audio in the video, false - disable
    public func recordAudio(enable: Bool) {
        self.recordAudio = enable
        if enable && status != .ready {
            tryEnableAudio { }
        }
    }
    
    private func saveDepthData(frameNum: Int, quaternion: [Float], intrinsicsMatrix: [Float], frameDepth: [Float]) {
        if let depthAssetCreator = depthAssetCreator {
            let quaternionData = Data(bytes: quaternion, count: quaternion.count * MemoryLayout<Float>.stride)
            let intrinsicsMatrixData = Data(bytes: intrinsicsMatrix, count: intrinsicsMatrix.count * MemoryLayout<Float>.stride)
            let depthData = Data(bytes: frameDepth, count: frameDepth.count * MemoryLayout<Float>.stride)
            var frame: Int32 = Int32(frameNum)
            
            
            var frameNumData = Data(bytes: &frame, count: MemoryLayout.size(ofValue: frame))
            depthAssetCreator.write(frameNumData)
            depthAssetCreator.write(quaternionData)
            depthAssetCreator.write(intrinsicsMatrixData)
            depthAssetCreator.write(depthData)
        } else {
            let date = Date()
            depthUrl = URL.tmpDepthUrl(date: date)
            if let depthUrl = depthUrl {
                do {
                    let success = FileManager.default.createFile(atPath: depthUrl.path, contents: nil, attributes:nil)
                    if (success) {
                        depthAssetCreator = try FileHandle(forWritingTo: depthUrl)
                    }
                }
                catch {
                    print("ERROR: \(error)")
                }
            }
        }
    }
    
    /// Process frame
    @objc private func processFrame() {
        guard status.isCapturing() else { return }
        let mediaTime = CACurrentMediaTime()
        //guard let frame = frameGenerator?.getFrame(from: view, renderer: renderer, time: mediaTime, depthComplete: saveDepthData), let buffer = frame.1 else { return }
        guard let frame = frameGenerator?.getFrame(from: view, renderer: renderer, time: mediaTime, depthComplete: saveDepthData) else { return }
        let buffer = frame.1
        queue.sync { [weak self] in
            guard self != nil else { return }
            var time: CMTime { return CMTime(seconds: mediaTime, preferredTimescale: 1000000) }
            //print("processFrame: time: \(time) frame.size: \(frame.2)")
            self?.delegate?.frame(frame: frame)
        
            //frame writing
            if (status == .recording && !self!.needToPause) {
                if let assetCreator = self?.assetCreator {
                    
                    assetCreator.append(buffer: buffer, with: getFrameTime(time: time))
                    
                    if let error = assetCreator.lastError {
                        print("ERROR: \(error)")
                        self?.status = .ready
                        if let error = errSecDecode as? Error {
                            print("ERROR: \(error)")
                        }
                        print(self!.videoUrl!)
                    }
                    
                    if (isPrepare) {
                        let frameCount = frame.3
                        if (frameCount > 3) {
                            self?.stopPrepare()
                        }
                    }
                } else {
                    let date = Date()
                    let url = URL.tmpVideoUrl(date: date)
                    self?.videoUrl = url
                    
                    let size = frame.2
                    do {
                        self?.assetCreator = try ARAssetCreator(
                            outputURL: url,
                            size: size, captureType: self!.frameGenerator!.captureType,
                            optimizeForNetworkUs: false,
                            audioEnabled: self!.recordAudio,
                            forceSize: false,
                            queue: self!.queue,
                            mixWithOthers: false)
                    }
                    catch {
                        print("ERROR: \(error)")
                    }
                }
            } else if status == .recording && self!.needToPause {
                assetCreator?.pause()
                self?.lastPauseTime = time
                self?.needToPause = false
                self?.status = .paused
            }
        }
    }
    
    private func tweakDelay(time: CMTime) {
        if let pauseTime = self.lastPauseTime {
            self.lastPauseTime = nil
            let lastDelay = CMTimeSubtract(time, pauseTime)
            if let sum = summaryDelay {
                summaryDelay = CMTimeAdd(sum, lastDelay)
            }
            else {
                summaryDelay = lastDelay
            }
        }
    }
    
    private func getFrameTime(time: CMTime) -> CMTime {
        tweakDelay(time: time)
        if let sum = summaryDelay {
            return CMTimeSubtract(time, sum)
        }
        return time
    }
    
    // MARK: -  Private

    /// Try enable audio recording
    /// - Parameter callback: the callback invoken when done
    private func tryEnableAudio(callback: @escaping ()->()) {
        switch audioPermissions {
        case .enabled, .disabled: callback()
        case .unknown:
            AVAudioSession.sharedInstance().requestRecordPermission({ [weak self] status in
                self?.audioPermissions = status ? .enabled : .disabled
                callback()
            })
        }
    }
}

extension URL {
    
    /// Temporary video path
    static func tmpVideoUrl(date: Date) -> URL {
        let parentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return URL(fileURLWithPath: "\(parentPath)/\(Date.isoFormatter.string(from: date)).mp4", isDirectory: false)
    }
    
    /// Temporary depth path
    static func tmpDepthUrl(date: Date) -> URL {
        let parentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return URL(fileURLWithPath: "\(parentPath)/\(Date.isoFormatter.string(from: date)).bin", isDirectory: false)
    }
}

extension Date {
    
    static var isoFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .full
        return f
    }
}

extension ARCapture {
    
    /// Helpful structure to define orientation
    struct Orientation {
        
        /// true - if landscape orientation, false - else
        static var isLandscape: Bool {
            orientation?.isLandscape ?? window?.windowScene?.interfaceOrientation.isLandscape ?? false
        }
        
        /// true - if landscape left orientation, false - else
        static var isLandscapeLeft: Bool {
            if let o = orientation {
                return o == .landscapeLeft
            }
            else {
                return isLandscape
            }
        }
        
        /// true - if landscape right orientation, false - else
        static var isLandscapeRight: Bool {
            if let o = orientation {
                return o == .landscapeRight
            }
            else {
                return isLandscape
            }
        }
        
        /// true - if portrait orientation, false - else
        static var isPortrait: Bool {
            orientation?.isPortrait ?? (window?.windowScene?.interfaceOrientation.isPortrait ?? false)
        }
        
        /// true - if flat orientation, false - else
        static var isFlat: Bool {
            orientation?.isFlat ?? false
        }
        
        /// valid orientation or nil
        static var orientation: UIDeviceOrientation? {
            UIDevice.current.orientation.isValidInterfaceOrientation ? UIDevice.current.orientation : nil
        }
        
        /// Current window (for both SwiftUI and storyboard based app)
        static var window: UIWindow? {
            guard let scene = UIApplication.shared.connectedScenes.first,
                  let windowSceneDelegate = scene.delegate as? UIWindowSceneDelegate,
                  let window = windowSceneDelegate.window else {
                return UIApplication.shared.windows.first
            }
            return window
        }
    }
}

/// Extends UIImage with a shortcut method.
extension UIImage {
    
    /// Get image from given view (screenshot)
    ///
    /// - Parameter view: the view
    /// - Returns: UIImage
    class func imageFromView(view: UIView) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(view.frame.size, false, 0)
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        
        let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}
