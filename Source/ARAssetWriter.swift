//
//  ARAssetCreator.swift
//  ARCapture framework
//
//  Created by Volkov Alexander on 6/6/21.
//

import Foundation
import AVFoundation

// Assert creator
class ARAssetCreator: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    /// the queue used to write auduo
    private let audioQueue = DispatchQueue(label: "ru.frgroup.volk.ARAssetCreator")
    
    /// the last occured error
    var lastError: Error?
    
    ///
    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!
    private var session: AVCaptureSession!
    
    private var buffer: AVAssetWriterInputPixelBufferAdaptor!
    private var needRecordAudio: Bool = false
    private var startTime: CMTime?
    
    init(outputURL: URL, size: CGSize, captureType: ARFrameGenerator.CaptureType, optimizeForNetworkUs: Bool, audioEnabled: Bool, queue: DispatchQueue, mixWithOthers: Bool) throws {
        super.init()
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)
        if audioEnabled {
            if mixWithOthers {
                let audioOptions: AVAudioSession.CategoryOptions = [.mixWithOthers , .allowBluetooth, .defaultToSpeaker, .interruptSpokenAudioAndMixWithOthers]
                try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.spokenAudio, options: audioOptions)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            //            let audioSession = AVAudioSession.sharedInstance()
            //            try audioSession.setCategory(
            //                AVAudioSession.Category.playAndRecord,
            //                mode: AVAudioSession.Mode.spokenAudio,
            //                options: mixWithOthers ? [.allowBluetooth, .defaultToSpeaker] : [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            //            try audioSession.setActive(true)
            AVAudioSession.sharedInstance().requestRecordPermission({ [weak self] status in
                guard status else { return }
                self?.tryAddAudioInput(with: queue)
            })
        }
        var effectiveSize = size
        if size.height < size.width && captureType == .renderWithDeviceRotation {
            effectiveSize = CGSize(width: size.height, height: size.width)
        }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264 as AnyObject,
            AVVideoWidthKey: Int(effectiveSize.width) as AnyObject,
            AVVideoHeightKey: Int(effectiveSize.height) as AnyObject
        ])
        videoInput.expectsMediaDataInRealTime = true
        buffer = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        
        
        //        print("ARCapture.Orientation.isPortrait: \(ARCapture.Orientation.isPortrait)")
        //        print("ARCapture.Orientation.isLandscape: \(ARCapture.Orientation.isLandscape)")
        //        print("ARCapture.Orientation.isLandscapeLeft: \(ARCapture.Orientation.isLandscapeLeft)")
        //        print("ARCapture.Orientation.isFlat: \(ARCapture.Orientation.isFlat)")
        
        
        print("VideoInput size: \(size)")
        // Apply transformation
        var transform: CGAffineTransform = .identity
//        if captureType == .renderWithDeviceRotation {
//            if ARCapture.Orientation.isLandscapeLeft {
//                transform = transform.rotated(by: .pi / 2)
//            }
//            else if ARCapture.Orientation.isLandscapeRight {
//                transform = transform.rotated(by: -.pi / 2)
//            }
//        }
        videoInput.transform = transform
        
        if assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else if let error = assetWriter.error {
            throw error
        }
        assetWriter.shouldOptimizeForNetworkUse = optimizeForNetworkUs
    }
    
    /// Try add audio into the video
    /// - Parameter queue: the queue used to call the audio delegate
    func tryAddAudioInput(with queue: DispatchQueue) {
        guard let device: AVCaptureDevice = AVCaptureDevice.default(for: .audio) else { return }
        
        session = AVCaptureSession()
        session.sessionPreset = .high
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = false
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("ERROR [tryAddAudioInput]: \(error)")
        }
        
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        // Connect input and output
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: output.recommendedAudioSettingsForAssetWriter(writingTo: .m4v) as? [String: Any])
        audioInput.expectsMediaDataInRealTime = true
        
        audioQueue.async { [weak self] in
            self?.session?.startRunning()
        }
        
        if assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        }
    }
    
    /// Append buffer
    /// - Parameters:
    ///   - buffer: the buffer
    ///   - time: the effective time
    func append(buffer: CVImageBuffer, with time: CMTime) {
        if assetWriter.status == .unknown {
            guard startTime == nil else { return }
            startTime = time
            if assetWriter.startWriting() {
                assetWriter.startSession(atSourceTime: time)
                needRecordAudio = true
            } else {
                lastError = assetWriter.error
                print("ERROR: \(String(describing: assetWriter.error))")
                needRecordAudio = false
            }
        } else if assetWriter.status == .failed {
            lastError = assetWriter.error
            print("ERROR: \(String(describing: assetWriter.error))")
            needRecordAudio = false
            return
        }
        
        if videoInput.isReadyForMoreMediaData {
            self.buffer.append(buffer, withPresentationTime: time)
            needRecordAudio = true
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let input = audioInput else { return }
        audioQueue.async { [weak self] in
            if let needRecordAudio = self?.needRecordAudio, needRecordAudio,
                let session = self?.session, session.isRunning,
                input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
    }
    
    /// Pause audio recording
    func pause() {
        needRecordAudio = false
    }
    
    /// Stop writing video
    /// - Parameter completed: the completion callback
    func stop(completed: @escaping () -> ()) {
        if let session = session, session.isRunning {
            session.stopRunning()
        }
        needRecordAudio = false
        if assetWriter.status == .writing {
            assetWriter.finishWriting(completionHandler: completed)
        }
    }
    
    
    /// Cancel writing video
    func cancel() {
        if let session = session, session.isRunning {
            session.stopRunning()
        }
        needRecordAudio = false
        assetWriter.cancelWriting()
    }
}
