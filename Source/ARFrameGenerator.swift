//
//  ARFrameGenerator.swift
//  ARCapture framework
//
//  Created by Volkov Alexander on 6/6/21.
//

import Foundation
import ARKit

public typealias ARCaptureFrame = (CVPixelBuffer, CVImageBuffer?, CGSize, Int)

public class ARFrameGenerator {
    
    public enum CaptureType: Int {
        case renderWithDeviceRotation, // applies `UIDevice.current.setValue(.portrait)`  (bad UX, good video)
             renderWithprojectionTransformToPortrait, // applies transform for the render (worst UX, mean video)
             imageCapture, // uses screenshots for the video                             (good UX, fine video)
             renderOriginal // uses correct frame transform                              (good UX, worst video)
    }
    
    public enum CaptureDepth: Int {
        case no,
             yes,
             smooth
    }
    
    let captureType: CaptureType
    let captureDepth: CaptureDepth

    var isCapturingDepth = false
    
    private var frameNum = 1
    private var processing = false
    private var canCaptureDepth = false
    
    init(captureType: CaptureType, captureDepth: CaptureDepth) {
        self.captureType = captureType
        self.captureDepth = captureDepth
        self.frameNum = 1
        self.processing = false
        if #available(iOS 14.0, *) {
            self.canCaptureDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
        if captureType == .renderWithDeviceRotation {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }
    
    public let queue = DispatchQueue(label: "ru.frgroup.volk.ARFrameGenerator", attributes: .concurrent)
    public let queue2 = DispatchQueue(label: "ru.frgroup.volk.ARFrameGenerator2", attributes: .concurrent)
    
    public func getFrame(from view: ARSCNView, renderer: SCNRenderer!, time: CFTimeInterval, depthComplete: ((Int, [Float], [Float], [Float])->())? = nil) -> ARCaptureFrame? {
        if (processing) {
            return nil
        }
        guard let currentFrame = view.session.currentFrame else {
            return nil
        }
        processing = true
        let thisFrameNum = frameNum
        let capturedImage = currentFrame.capturedImage
        
        if
            #available(iOS 14.0, *),
            let depthComplete = depthComplete,
            self.canCaptureDepth && (self.captureDepth == .yes || self.captureDepth == .smooth) && !isCapturingDepth
        {
            if (self.captureDepth == .smooth) {
                queue2.async {
                    self.isCapturingDepth = true
                    let sceneDepth = currentFrame.smoothedSceneDepth
                    let capturedDepth = sceneDepth?.depthMap.toFlatArray() ?? [Float](repeating: 0.0, count: 49152)
                    
                    let trans = currentFrame.camera.transform
                    let quat = simd_quaternion(trans)
                    let camMat = currentFrame.camera.intrinsics
                    
                    let quaternion: [Float] = [quat.vector.x, quat.vector.y, quat.vector.z, quat.vector.w]
                    let intrinsicsMatrix: [Float] = [
                        camMat.columns.0.x, camMat.columns.0.y, camMat.columns.0.z,
                        camMat.columns.1.x, camMat.columns.1.y, camMat.columns.1.z,
                        camMat.columns.2.x, camMat.columns.2.y, camMat.columns.2.z,
                    ]
                    
                    depthComplete(thisFrameNum, quaternion, intrinsicsMatrix, capturedDepth)
                    self.isCapturingDepth = false
                }
            } else if (self.captureDepth == .yes) {
                queue2.async {
                    self.isCapturingDepth = true
                    let sceneDepth = currentFrame.sceneDepth
                    let capturedDepth = sceneDepth?.depthMap.toFlatArray() ?? [Float](repeating: 0.0, count: 49152)
                    
                    let trans = currentFrame.camera.transform
                    let quat = simd_quaternion(trans)
                    let camMat = currentFrame.camera.intrinsics
                    
                    let quaternion: [Float] = [quat.vector.x, quat.vector.y, quat.vector.z, quat.vector.w]
                    let intrinsicsMatrix: [Float] = [
                        camMat.columns.0.x, camMat.columns.0.y, camMat.columns.0.z,
                        camMat.columns.1.x, camMat.columns.1.y, camMat.columns.1.z,
                        camMat.columns.2.x, camMat.columns.2.y, camMat.columns.2.z,
                    ]
                    
                    depthComplete(thisFrameNum, quaternion, intrinsicsMatrix, capturedDepth)
                    self.isCapturingDepth = false
                }
            }
        }
        
        /// the image used for the video frame
        var frame: UIImage?
        //        var width = CVPixelBufferGetWidth(capturedImage)
        //        var height = CVPixelBufferGetHeight(capturedImage)
        var width = captureType == .imageCapture ? view.bounds.width : view.currentViewport.width
        var height = captureType == .imageCapture ? view.bounds.height : view.currentViewport.height
        let originalSize = CGSize(width: width, height: height)
        
        // Calculate angle
        var angle: CGFloat?
        if captureType != .imageCapture {
            if ARCapture.Orientation.isLandscapeLeft {
                let t = width;
                width = height
                height = t
                angle = .pi / 2
            }
            else if ARCapture.Orientation.isLandscapeRight {
                let t = width;
                width = height
                height = t
                angle = -.pi / 2
            }
        }
        let size = CGSize(width: width, height: height)
        
        if captureType == .imageCapture {
            frame = UIImage.imageFromView(view: view)
        }
        else {
            let viewportSize = CGSize(width: view.currentViewport.size.height, height: view.currentViewport.size.width)
            
            if captureType == .renderWithprojectionTransformToPortrait && ARCapture.Orientation.isLandscape {
                // Match clipping
                renderer.pointOfView?.camera?.zNear = 0.001
                renderer.pointOfView?.camera?.zFar = 1000
        
                // Match projection
                let projection = SCNMatrix4(currentFrame.camera.projectionMatrix(for: .portrait, viewportSize: viewportSize, zNear: 0.001, zFar: 1000))
                renderer.pointOfView?.camera?.projectionTransform = projection
        
                // Match transform
                renderer.pointOfView?.simdTransform = currentFrame.camera.viewMatrix(for: .portrait).inverse
            }
            
            queue.sync {
                frame = renderer.snapshot(atTime: time, with: size, antialiasingMode: .none)
                //print("size: \(size) frame.size=\(frame?.size)")
            }
        }
        processing = false
        frameNum += 1

        return (capturedImage, frame?.getBuffer(angle: angle, originalSize: originalSize), originalSize, thisFrameNum)
    }
}

extension UIImage {
    
    /// Get buffer with pixels from image
    /// - Parameters:
    ///   - angle: the angle to apply
    ///   - originalSize: the original size
    public func getBuffer(angle: CGFloat?, originalSize: CGSize) -> CVPixelBuffer? {
        let size = self.size
        var buff: CVPixelBuffer?
        let res = CVPixelBufferCreate(kCFAllocatorDefault,
                                      Int(size.width),
                                      Int(size.height),
                                      kCVPixelFormatType_32ARGB,
                                      [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                                       kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary,
                                      &buff)
        guard res == kCVReturnSuccess else { return nil }
        
        CVPixelBufferLockBaseAddress(buff!, CVPixelBufferLockFlags(rawValue: 0))
        
        guard let c = CGContext(data: CVPixelBufferGetBaseAddress(buff!),
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buff!),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil}
        
        if let angle = angle {
            c.rotate(by: angle)
            c.translateBy(x: 0, y: 0)
        }
        else {
            c.translateBy(x: 0, y: size.height)
        }
        c.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(c)
        self.draw(in: CGRect(x: 0, y: 0, width: originalSize.width, height: originalSize.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(buff!, CVPixelBufferLockFlags(rawValue: 0))
        return buff
    }
}

extension CVPixelBuffer {
    // Requires CVPixelBufferLockBaseAddress(_:_:) first
    var data: UnsafeRawBufferPointer? {
        let size = CVPixelBufferGetDataSize(self)
        return .init(start: CVPixelBufferGetBaseAddress(self), count: size) }
    var pixelSize: simd_int2 { simd_int2(Int32(width), Int32(height)) }
    var width: Int { CVPixelBufferGetWidth(self) }
    var height: Int { CVPixelBufferGetHeight(self) }

    func sample(location: simd_float2) -> simd_float4? {
        let pixelSize = self.pixelSize
        guard pixelSize.x > 0 && pixelSize.y > 0 else { return nil }
        guard CVPixelBufferLockBaseAddress(self, .readOnly) == noErr else { return nil }
        guard let data = data else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        let pix = location * simd_float2(pixelSize)
        let clamped = clamp(simd_int2(pix), min: .zero, max: pixelSize &- simd_int2(1,1))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        let row = Int(clamped.y)
        let column = Int(clamped.x)
        let rowPtr = data.baseAddress! + row * bytesPerRow
        switch CVPixelBufferGetPixelFormatType(self) {
        case kCVPixelFormatType_DepthFloat32:
            // Bind the row to the right type
            let typed = rowPtr.assumingMemoryBound(to: Float.self)
            return .init(typed[column], 0, 0, 0)
        case kCVPixelFormatType_32BGRA:
            // Bind the row to the right type
            let typed = rowPtr.assumingMemoryBound(to: UInt8.self)
            return .init(Float(typed[column]) / Float(UInt8.max), 0, 0, 0)
        default:
            return nil
        }
    }
    
    func toFlatArray() -> [Float] {
        var depthArray = [Float]()
        let pixelSize = self.pixelSize
        guard pixelSize.x > 0 && pixelSize.y > 0 else { return depthArray }
        guard CVPixelBufferLockBaseAddress(self, .readOnly) == noErr else { return depthArray }
        guard let data = data else { return depthArray }
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        for y in stride(from: 1, to: pixelSize.y + 1, by: 1) {
            for x in stride(from: 1, to: pixelSize.x + 1, by: 1) {
                let pix = simd_float2(Float(x), Float(y))
                let clamped = clamp(simd_int2(pix), min: .zero, max: pixelSize &- simd_int2(1,1))
                let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
                let row = Int(clamped.y)
                let column = Int(clamped.x)
                let rowPtr = data.baseAddress! + row * bytesPerRow
                switch CVPixelBufferGetPixelFormatType(self) {
                case kCVPixelFormatType_DepthFloat32:
                    // Bind the row to the right type
                    let typed = rowPtr.assumingMemoryBound(to: Float.self)
                    depthArray.append(typed[column])
                case kCVPixelFormatType_32BGRA:
                    // Bind the row to the right type
                    let typed = rowPtr.assumingMemoryBound(to: UInt8.self)
                    depthArray.append(Float(typed[column]) / Float(UInt8.max))
                default:
                    depthArray.append(0)
                }
            }
        }
        
        return depthArray
    }
    
    func toArray() -> [[Float]] {
        var depthArray = [[Float]]()
        let pixelSize = self.pixelSize
        guard pixelSize.x > 0 && pixelSize.y > 0 else { return depthArray }
        guard CVPixelBufferLockBaseAddress(self, .readOnly) == noErr else { return depthArray }
        guard let data = data else { return depthArray }
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        for y in stride(from: 1, to: pixelSize.y + 1, by: 1) {
            var depthArrayLine = [Float]()
            for x in stride(from: 1, to: pixelSize.x + 1, by: 1) {
                let pix = simd_float2(Float(x), Float(y))
                let clamped = clamp(simd_int2(pix), min: .zero, max: pixelSize &- simd_int2(1,1))
                let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
                let row = Int(clamped.y)
                let column = Int(clamped.x)
                let rowPtr = data.baseAddress! + row * bytesPerRow
                switch CVPixelBufferGetPixelFormatType(self) {
                case kCVPixelFormatType_DepthFloat32:
                    // Bind the row to the right type
                    let typed = rowPtr.assumingMemoryBound(to: Float.self)
                    depthArrayLine.append(typed[column])
                case kCVPixelFormatType_32BGRA:
                    // Bind the row to the right type
                    let typed = rowPtr.assumingMemoryBound(to: UInt8.self)
                    depthArrayLine.append(Float(typed[column]) / Float(UInt8.max))
                default:
                    depthArrayLine.append(0)
                }
            }
            depthArray.append(depthArrayLine)
        }
        
        return depthArray
    }
}

