//
//  ARFrameGenerator.swift
//  ARCapture framework
//
//  Created by Volkov Alexander on 6/6/21.
//

import Foundation
import ARKit

public typealias ARCaptureFrame = (CVPixelBuffer, CVImageBuffer?, CGSize)

public class ARFrameGenerator {
    
    public enum CaptureType: Int {
        case renderWithDeviceRotation, // applies `UIDevice.current.setValue(.portrait)`  (bad UX, good video)
             renderWithprojectionTransformToPortrait, // applies transform for the render (worst UX, mean video)
             imageCapture, // uses screenshots for the video                             (good UX, fine video)
             renderOriginal // uses correct frame transform                              (good UX, worst video)
    }
    
    let captureType: CaptureType
    
    init(captureType: CaptureType) {
        self.captureType = captureType
        if captureType == .renderWithDeviceRotation {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }
    
    public let queue = DispatchQueue(label: "ru.frgroup.volk.ARFrameGenerator", attributes: .concurrent)
    
    public func getFrame(from view: ARSCNView, renderer: SCNRenderer!, time: CFTimeInterval) -> ARCaptureFrame? {
        guard let currentFrame = view.session.currentFrame else { return nil }
        let capturedImage = currentFrame.capturedImage
        
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
        return (capturedImage, frame?.getBuffer(angle: angle, originalSize: originalSize), originalSize)
    }
}

extension UIImage {
    
    // dodo change
    public func getBuffer(angle: CGFloat?, originalSize: CGSize) -> CVPixelBuffer? {
        let size = self.size
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let res = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard res == kCVReturnSuccess else { return nil }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer!), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        if let angle = angle {
            context?.rotate(by: angle)
            context?.translateBy(x: 0, y: 0)
            context?.scaleBy(x: 1.0, y: -1.0)
        }
        else {
            context?.translateBy(x: 0, y: size.height)
            context?.scaleBy(x: 1.0, y: -1.0)
        }
        
        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(x: 0, y: 0, width: originalSize.width, height: originalSize.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer
    }
}
