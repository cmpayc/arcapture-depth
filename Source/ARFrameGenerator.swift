//
//  ARFrameGenerator.swift
//  ARCapture framework
//
//  Created by Volkov Alexander on 6/6/21.
//  Modified by Sergei Kazakov on 21.08.24.
//

import Foundation
import ARKit

// public typealias ARCaptureFrame = (CVPixelBuffer, CVImageBuffer?, CGSize, Int)
public typealias ARCaptureFrame = (Bool, CVPixelBuffer, CGSize, Int)

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
    private var coreImageContext: CIContext
    
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
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.coreImageContext = CIContext(mtlDevice: metalDevice)
        } else {
            self.coreImageContext = CIContext(options: nil)
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
                    
                    let (capturedDepth, arPose, intrinsicsMatrix) = self.getARKitData(currentFrame: currentFrame, sceneDepth: sceneDepth, isPortrait: ARCapture.Orientation.isPortrait, isLandscapeRight: ARCapture.Orientation.isLandscapeRight)
                    
                    depthComplete(thisFrameNum, arPose, intrinsicsMatrix, capturedDepth)
                    self.isCapturingDepth = false
                }
            } else if (self.captureDepth == .yes) {
                queue2.async {
                    self.isCapturingDepth = true
                    let sceneDepth = currentFrame.sceneDepth
                    
                    let (capturedDepth, arPose, intrinsicsMatrix) = self.getARKitData(currentFrame: currentFrame, sceneDepth: sceneDepth, isPortrait: ARCapture.Orientation.isPortrait, isLandscapeRight: ARCapture.Orientation.isLandscapeRight)
                    
                    depthComplete(thisFrameNum, arPose, intrinsicsMatrix, capturedDepth)
                    self.isCapturingDepth = false
                }
            }
        }
        
        /// the image used for the video frame
        var frame: UIImage?
        //        var width = CVPixelBufferGetWidth(capturedImage)
        //        var height = CVPixelBufferGetHeight(capturedImage)
        //var width = captureType == .imageCapture ? view.bounds.width : view.currentViewport.width
        //var height = captureType == .imageCapture ? view.bounds.height : view.currentViewport.height
        //var width = view.bounds.width
        //var height = view.bounds.height
        var width = capturedImage.width
        var height = capturedImage.height
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
        
        /* We don't need to record an ARKit frame
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
        */
        processing = false
        frameNum += 1

        //return (capturedImage, frame?.getBuffer(angle: angle, originalSize: originalSize), originalSize, thisFrameNum)
        var pixelBuffer: CVPixelBuffer?
        if (ARCapture.Orientation.isPortrait) {
            pixelBuffer = capturedImage.rotate(side: .right, coreImageContext: self.coreImageContext)
        } else if (ARCapture.Orientation.isLandscapeRight) {
            pixelBuffer = capturedImage.rotate(side: .right, coreImageContext: self.coreImageContext)
            pixelBuffer = pixelBuffer!.rotate(side: .right, coreImageContext: self.coreImageContext)
        } else {
            pixelBuffer = capturedImage
        }
        return (true, pixelBuffer!, originalSize, thisFrameNum)
    }
    
    @available(iOS 14.0, *)
    private func getARKitData(currentFrame: ARFrame, sceneDepth: ARDepthData?, isPortrait: Bool, isLandscapeRight: Bool) -> ([Float], [Float], [Float]) {
        let capturedDepth: [Float]
        if (sceneDepth != nil) {
            capturedDepth = sceneDepth!.depthMap.toFlatArray(isPortrait: isPortrait, isLandscapeRight: isLandscapeRight) ?? [Float](repeating: 0.0, count: 49152)
        } else {
            capturedDepth = [Float](repeating: 0.0, count: 49152)
        }
        
        let trans = currentFrame.camera.transform
        let quat = simd_quaternion(trans)
        let camMat = currentFrame.camera.intrinsics
        
        let arPose: [Float] = [
            trans.columns.3.x, trans.columns.3.y, trans.columns.3.z,
            quat.vector.x, quat.vector.y, quat.vector.z, quat.vector.w
        ]
        let intrinsicsMatrix: [Float] = [
            camMat.columns.0.x, camMat.columns.0.y, camMat.columns.0.z,
            camMat.columns.1.x, camMat.columns.1.y, camMat.columns.1.z,
            camMat.columns.2.x, camMat.columns.2.y, camMat.columns.2.z,
        ]
        
        return (capturedDepth, arPose, intrinsicsMatrix)
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
    
    public func toFlatArray(isPortrait: Bool, isLandscapeRight: Bool) -> [Float] {
        var depthArray = [Float]()
        let pixelSize = self.pixelSize
        guard pixelSize.x > 0 && pixelSize.y > 0 else { return depthArray }
        guard CVPixelBufferLockBaseAddress(self, .readOnly) == noErr else { return depthArray }
        guard let data = data else { return depthArray }
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        var fromLeft: Int32 = 1
        var toLeft: Int32 = pixelSize.x + 1
        var fromTop: Int32 = 1
        var toTop: Int32 = pixelSize.y + 1
        var byTop = 1
        var byLeft = 1
        if (isPortrait) {
            fromLeft = pixelSize.y + 1
            toLeft = 1
            fromTop = 1
            toTop = pixelSize.x + 1
            byLeft = -1
        } else if (isLandscapeRight) {
            fromLeft = pixelSize.x + 1
            toLeft = 1
            fromTop = pixelSize.y + 1
            toTop = 1
            byTop = -1
            byLeft = -1
        }
        
        for top in stride(from: fromTop, to: toTop, by: byTop) {
            for left in stride(from: fromLeft, to: toLeft, by: byLeft) {
                let pix = isPortrait ? simd_float2(Float(top), Float(left)) : simd_float2(Float(left), Float(top))
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
    
    public func rotate(side: CGImagePropertyOrientation, coreImageContext: CIContext) -> CVPixelBuffer {
        var newPixelBuffer: CVPixelBuffer?
        let error = CVPixelBufferCreate(kCFAllocatorDefault,
                        CVPixelBufferGetHeight(self),
                        CVPixelBufferGetWidth(self),
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                        nil,
                        &newPixelBuffer)
        guard error == kCVReturnSuccess,
           let buffer = newPixelBuffer else {
           return self
        }
        let ciImage = CIImage(cvPixelBuffer: self).oriented(side)
        coreImageContext.render(ciImage, to: buffer)
        return buffer
    }
    
    public func resize(size: CGSize, coreImageContext: CIContext) -> CVPixelBuffer {
        var newPixelBuffer: CVPixelBuffer?
        let error = CVPixelBufferCreate(kCFAllocatorDefault,
                        Int(size.width),
                        Int(size.height),
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                        nil,
                        &newPixelBuffer)
        guard error == kCVReturnSuccess,
           let buffer = newPixelBuffer else {
           return self
        }
        let ciImage = CIImage(cvPixelBuffer: self)
        
        let scale = min(size.width, size.height) / min(ciImage.extent.size.width, ciImage.extent.size.height)
        let transformedImage = ciImage.transformed(by: .init(scaleX: scale, y: scale))

        let width = transformedImage.extent.width
        let height = transformedImage.extent.height
        let xOffset = ((width - size.width) / 2).rounded(.down)
        let yOffset = ((height - size.height) / 2).rounded(.down)
        let rect = CGRect(x: xOffset, y: yOffset, width: size.width, height: size.height)

        let resizedImage = transformedImage
          .clamped(to: rect)
          .cropped(to: rect)
        
        coreImageContext.render(resizedImage, to: buffer)
        return buffer
      }
}
