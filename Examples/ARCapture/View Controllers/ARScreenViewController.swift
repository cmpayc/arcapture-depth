//
//  ARScreenViewController.swift
//  ARCapture Example
//
//  Created by Volkov Alexander on 5/24/21.
//

import UIKit
import ARKit

enum MainState {
    case
         localization, // when .normal state was never experienced and/or there are no planes detected
         ready // no anchor, or user tapped (achor added); allows to show something or record screen if there is an anchor
    
    /// true - if world traking is on, false - else (if it's not needed)
    func isTracking() -> Bool {
        return true
    }
    
}

// Class reflects screen state
class ScreenState {
    
    var trackingState: ARCamera.TrackingState = .notAvailable
    
    private var currentState: MainState = .localization
    
    var state: MainState {
        return currentState
    }
    
    func set(state: MainState) {
        currentState = state
    }
    
    func isTrackingChanged() -> Bool {
        return true
    }
    
}

typealias SceneViewController = ARScreenViewController

/// Scene
class ARScreenViewController: UIViewController, ARSessionDelegate {
    
    /// outlets
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordButtons: [UIButton]!
    
    /// the screen state
    var screenState = ScreenState()
    
    // added objects
    
    /// the shortcuts
    internal var session: ARSession { return sceneView.session }
    internal var scene: SCNScene { return sceneView.scene }
    
    internal var planeAnchorHandler: PlaneAnchorHandler?
    
    internal weak var coachingOverlay: UIView?
    internal var timerPlaneDetection: Timer?
    
    private var savedWorldMap: ARWorldMap?
    private var initialAppear = true
    
    private var capture: ARCapture?
    
    // MARK: - Setup
    
    /// Setup UI
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        planeAnchorHandler = PlaneAnchorHandler(sceneView: sceneView)
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        if #available(iOS 13.0, *) {
            setupCoachingOverlay()
        }
        
        capture = ARCapture(view: sceneView)
        for b in recordButtons {
            b.isHidden = true
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if initialAppear {
            prepareScene()
            
            updateUI()
            initialAppear = false
        }
        
        #if targetEnvironment(simulator)
            DispatchQueue.main.async {
                // dodo
//                self.showAlert("", "You need to run the app on a real device")
            }
        #endif
        // dodo lock rotations if needed
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tryStartPlaneDetectionTimer()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // dodo TODO
        // invalidate timers
        timerPlaneDetection?.invalidate()
        if parent == nil {
            // set delegates to nil
            do {
                planeAnchorHandler?.planeNodes.removeAll()
                planeAnchorHandler?.planes.removeAll()
                planeAnchorHandler?.showSinglePlane = nil
                planeAnchorHandler = nil
            }
            
            // remove unnecessary nodes
            for node in scene.rootNode.childNodes {
                node.removeFromParentNode()
            }
            session.delegate = nil
            sceneView?.delegate = nil
            sceneView?.removeFromSuperview()
            sceneView = nil
            
            coachingOverlay?.removeFromSuperview()
            if #available(iOS 13.0, *) {
                (coachingOverlay as? ARCoachingOverlayView)?.delegate = nil
                (coachingOverlay as? ARCoachingOverlayView)?.session = nil
            }
            coachingOverlay = nil
//            debugCheckDeallocation() dodo
        }
    }
    
    // MARK: - Initialization
    
    /// Prepare scene
    private func prepareScene() {
        SCNTransaction.animationDuration = 0.3
        
        // Setup Image Based Lighting (IBL) map
        sceneView.scene.lightingEnvironment.intensity = 2.0
        sceneView.autoenablesDefaultLighting = true
        
        resetTracking()
        session.delegate = self
    }
    
    // MARK: - Deinitialization
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // dodo unlock rotations if needed
        pauseScene()
    }
    
    /// Main method to update 2D interface.
    internal func updateUI() {
        if screenState.state.isTracking() {
            switch screenState.trackingState {
            case .notAvailable:
                // dodo remove content from the scene
                for b in recordButtons {
                    b.isHidden = true
                }
                break
            case .limited(let reason):
                let errorMessage = reason.toMessage()
                print(".limited: reason=\(errorMessage)")
            case .normal:
                // If ARKit state is `.normal` and we was in `.localization` state, then mark as `.ready`
                if self.screenState.state == .localization {
                    showHintDetectingPlane()
                }
                self.screenState.set(state: .ready)
                
                if let b = recordButtons.filter({$0.isSelected}).first {
                    b.isHidden = false
                }
                else {
                    for b in recordButtons {
                        b.isHidden = false
                    }
                }
                // dodo show buttons and sync normal state
                break
            }
        }
        
//        switch screenState.state {
        /// dodo show/hide buttons
//        }
    }
    
    internal func showHintDetectingPlane() {
        // dodo tryShowHint(text: "Understanding the Environment, Setting up the plane.")
    }
    
    internal func removeHintDetectingPlane() {
        // dodo tryHideHint(text: "Understanding the Environment, Setting up the plane.")
    }
    
    // MARK: - Scene
    
    private func configureSession(map: ARWorldMap?) {
        let isTracking = screenState.state.isTracking()
        print("configureSession: isTracking=\(isTracking) \(map != nil ? map!.description: "nil")")
        
        if isTracking {
            if ARWorldTrackingConfiguration.isSupported {
                let configuration = ARWorldTrackingConfiguration()
                configuration.isLightEstimationEnabled = true
                configuration.environmentTexturing = .automatic
                configuration.planeDetection = [.horizontal, .vertical]
                configuration.initialWorldMap = map
                if #available(iOS 13.0, *) {
                    if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                        configuration.frameSemantics.insert(.personSegmentationWithDepth)
                    }
                }
                sceneView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            }
        }
        else { // dodo used for Welcome screens to reduce battery usage
//            if #available(iOS 13.0, *) {
//                let configuration = ARPositionalTrackingConfiguration()
//                configuration.planeDetection = [.horizontal, .vertical]
//                configuration.initialWorldMap = map
//                sceneView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
//            } else {
            let configuration = ARWorldTrackingConfiguration()
            configuration.isLightEstimationEnabled = false
            configuration.environmentTexturing = .none
            configuration.planeDetection = [.horizontal, .vertical]
            sceneView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
//            }
//            recorder?.rest()
        }
    }
    
    private func pauseScene() {
        print("pauseScene")
        // Pause the view's session
        session.pause()
    }
    
    // MARK: - ARSessionDelegate
    
    // Every frame update handlers
    func session(_ session: ARSession, didUpdate: ARFrame) {
        if let camera = session.currentFrame?.camera {
            // dodo angleHandler?.updateCamera(camera)
        }
//        if let intensity = frame.lightEstimate?.ambientIntensity {
//            applyLight(intensity: intensity)
//        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        print("ERROR: didFailWithError: \(error)")
        if let error = error as? ARError, error.code == .cameraUnauthorized {
            // dodo showAlert("Camera access required", "Please grant camera access permissions in Setting app. It's required for this app.")
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("sessionWasInterrupted")
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        let id = UIApplication.shared.beginBackgroundTask {
            // nothing to do for the cancel
        }
        session.getCurrentWorldMap { (map, error) in
            if let error = error {
                print("ERROR: \(error)")
            }
            if let map = map {
                self.saveMap(map)
            }
            if id != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(id)
            }
        }
    }
    
    /// Reset tracking after interruption
    ///
    /// - Parameter session: the session
    func sessionInterruptionEnded(_ session: ARSession) {
        print("sessionInterruptionEnded")
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        resetTracking()
    }
    
    private func saveMap(_ map: ARWorldMap) {
        print("saveMap")
        self.savedWorldMap = map
    }
    
    // MARK: - State changes
    
    /// Handle tracking state changes
    ///
    /// - Parameters:
    ///   - session: the sesssion
    ///   - camera: the camera
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        screenState.trackingState = camera.trackingState
        DispatchQueue.main.async {
            self.updateUI()
        }
        switch camera.trackingState {
        case .limited(let reason):
            print("state limited{reason: \(reason)}")
        case .normal:
            print("state: normal")
        case .notAvailable:
            print("state: norAvailable")
        }
    }
    
    /// Reset tracking
    internal func resetTracking() {
        print("resetTracking")
        // dodo remove objects
        
        planeAnchorHandler?.removeAll()
        
        // Configure session
        configureSession(map: savedWorldMap)
    }
    
    // MARK: -
    
    /// Get point in the world related to screen point `point` (which is in (0,0)-(1,1), so that (0.5,0.5) is the center of the screen)
    /// - Parameter point: the screen point
    func getWorldPoint(from2DPoint point: CGPoint) -> ARHitTestResult? {
        let results = self.sceneView.hitTest(point, types: [.existingPlaneUsingGeometry])
        if let closest = results.first {
            return closest
        }
        return nil
    }
    
    // MARK: -
    
    private func tryStartPlaneDetectionTimer() {
        if planeAnchorHandler?.planes.isEmpty == true {
            startPlaneDetectionTimer()
        }
    }
    
    private func startPlaneDetectionTimer() {
        timerPlaneDetection?.invalidate()
        timerPlaneDetection = Timer.scheduledTimer(withTimeInterval: 30, repeats: false, block: { [weak self] (_) in
            let message = NSLocalizedString("Taking too much time detecting plane, would you like to continue?", comment: "Taking too much time detecting plane, would you like to continue?")
            print(message)
            // dodo
//            self?.confirmDialog = ConfirmDialog(title: "", text: message) { [weak self] in
//                self?.startPlaneDetectionTimer()
//            }
//            self?.confirmDialog?.cancelled = {
//                self?.closeAction(self!)
//            }
        })
    }
    
    /// "Record/stop" button action handler
    ///
    /// - parameter sender: the button
    @IBAction func recordAction(_ sender: UIButton) {
        if sender.isSelected {
            for b in recordButtons {
                b.isSelected = false
                b.isHidden = false
            }
        }
        else {
            for b in recordButtons {
                b.isHidden = true
            }
            sender.isSelected = true
            sender.isHidden = false
        }
        if sender.isSelected {
            capture?.start(captureType: ARFrameGenerator.CaptureType(rawValue: sender.tag)!)
        }
        else {
            capture?.stop({ (status) in
                print("Video exported: \(status)")
            })
        }
    }
}

extension ARCamera.TrackingState.Reason {
    func toMessage() -> String {
        var errorMessage = ""
        switch self {
        case .initializing:
            break
        case .excessiveMotion:
            errorMessage = "Move slowly"
        case .insufficientFeatures:
            errorMessage = "Continue to move around."
        case .relocalizing:
            errorMessage = "Relocalizing. Continue to move around."
        @unknown default:
            break
        }
        return errorMessage
    }
}

extension SceneViewController: ARCoachingOverlayViewDelegate {
    
    @available(iOS 13.0, *)
    func setupCoachingOverlay() {
        let coachingOverlay = ARCoachingOverlayView()
        // Set up coaching view
        coachingOverlay.session = sceneView.session
        coachingOverlay.delegate = self
        
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        sceneView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coachingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            coachingOverlay.widthAnchor.constraint(equalTo: view.widthAnchor),
            coachingOverlay.heightAnchor.constraint(equalTo: view.heightAnchor)
        ])
        
        setActivatesAutomatically()
        
        // Most of the virtual objects in this sample require a horizontal surface,
        // therefore coach the user to find a horizontal plane.
        setGoal()
        self.coachingOverlay = coachingOverlay
    }
    
    /// - Tag: CoachingActivatesAutomatically
    @available(iOS 13.0, *)
    func setActivatesAutomatically() {
        (coachingOverlay as? ARCoachingOverlayView)?.activatesAutomatically = true
    }
    
    /// - Tag: CoachingGoal
    @available(iOS 13.0, *)
    func setGoal() {
        (coachingOverlay as? ARCoachingOverlayView)?.goal = .anyPlane
    }
}


extension SceneViewController: ARSCNViewDelegate {
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        print("render:didAdd:node:anchor:\(node), \(anchor)")
        // Add plane
        do {
            if let _ = anchor as? ARPlaneAnchor {
                DispatchQueue.main.async { [weak self] in
                    self?.removeHintDetectingPlane()
                    self?.timerPlaneDetection?.invalidate()
                    self?.timerPlaneDetection = nil
                }
            }
            planeAnchorHandler?.processAdded(node: node, for: anchor)
        }
        // dodo logic to show hints
//        if screenState.state == .ready && !(planeAnchorHandler?.planes.isEmpty ?? true) {
//            // show hint to tap
//            if !planeAnchorHandler!.planes.filter({$0.alignment ==  .vertical}).isEmpty {
//                DispatchQueue.main.async { [weak self] in
//                    if self?.objectCenterHandler.anchor == nil {
//                        self?.tryShowHint(text: "Tap on the object and place the anchor.")
//                    }
//                }
//            }
//        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        planeAnchorHandler?.processRemoved(node: node, for: anchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        planeAnchorHandler?.processUpdated(node: node, for: anchor)
    }
}
