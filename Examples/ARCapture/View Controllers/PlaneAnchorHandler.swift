//
//  PlaneAnchorHandler.swift
//  Capture
//
//  Created by Volkov Alexander on 9/27/20.
//  Copyright © 2020 Topcoder. All rights reserved.
//

import ARKit
import UIKit

class PlaneAnchorHandler: AnchorHandler {

    private weak var sceneView: ARSCNView?
    
    /// the detected planes
    var planes = [ARPlaneAnchor]()
    
    internal var planeNodes = [SCNNode]()
    
    /// if not nil, then shows a single (given) plane only
    var showSinglePlane: ARPlaneAnchor?
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
    }
    
    /// Process added node for anchor
    /// - Parameters:
    ///   - node: the node
    ///   - anchor: the anchor
    func processAdded(node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        planes.append(planeAnchor)
        
        // Create a custom object to visualize the plane geometry and extent.
        guard let sceneView = sceneView else { return }
        let plane = Grid(anchor: planeAnchor, in: sceneView)
        
        // Add the visualization to the ARKit-managed node so that it tracks
        // changes in the plane anchor as plane estimation continues.
        node.addChildNode(plane)
        planeNodes.append(node)
        if showSinglePlane != nil {
            node.isHidden = true
        }
    }
    
    /// Process updated node
    /// - Parameters:
    ///   - node: the node
    ///   - anchor: the anchor
    func processUpdated(node: SCNNode, for anchor: ARAnchor) {
        // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
        guard let plane = node.childNodes.first as? Grid
            else { return }
        
        // Update extent visualization to the anchor's new bounding rectangle.
        if let geometry = plane.grid.geometry as? SCNPlane {
            geometry.width = CGFloat(planeAnchor.extent.x)
            geometry.height = CGFloat(planeAnchor.extent.z)
            plane.grid.simdPosition = planeAnchor.center
            plane.applyGridSize()
        }
    }
    
    /// Process removed node
    /// - Parameters:
    ///   - node: the node
    ///   - anchor: the anchor
    func processRemoved(node: SCNNode, for anchor: ARAnchor) {
        guard let anchor = anchor as? ARPlaneAnchor else { return }
        if let i = planeNodes.firstIndex(of: node) {
            planeNodes.remove(at: i)
        }
        if let i = planes.firstIndex(of: anchor) {
            planes.remove(at: i)
        }
    }
    
    /// Remove all planes
    func removeAll() {
        planes.removeAll()
    }
    
    // MARK: - Plane visibility methods
    
    /// Show only one given plane
    /// - Parameter plane: the plane anchor
    func showSinglePlane(_ plane: ARPlaneAnchor) {
        showSinglePlane = plane
        if let i = planes.firstIndex(of: plane), i < planeNodes.count {
            for node in planeNodes {
                node.isHidden = true
            }
            planeNodes[i].isHidden = false
        }
    }
    
    /// Show all planes
    func showAllPlanes() {
        showSinglePlane = nil
        for node in planeNodes {
            node.isHidden = false
        }
    }
}

/// The node to show grid over the detected plane
class Grid: SCNNode {
    
    let grid: SCNNode
    let color: UIColor = .white
    
    init(anchor: ARPlaneAnchor, in sceneView: ARSCNView) {
        
        let extentPlane: SCNPlane = SCNPlane(width: CGFloat(anchor.extent.x), height: CGFloat(anchor.extent.z))
        grid = SCNNode(geometry: extentPlane)
        grid.simdPosition = anchor.center
        grid.eulerAngles.x = -.pi / 2
        
        super.init()
        self.setupGrid()
        addChildNode(grid)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    /// Setup grid
    private func setupGrid() {
        grid.opacity = 1
        guard let material = grid.geometry?.firstMaterial else { fatalError() }
        material.diffuse.contents = UIImage(named: "grid")!
        applyGridSize()
    }
    
    /// Apply new size
    func applyGridSize() {
        if let geometry = grid.geometry as? SCNPlane {
            let scaleX = (Float(geometry.width)  / 0.06).rounded()
            let scaleY = (Float(geometry.height) / 0.06).rounded()
            guard let material = grid.geometry?.firstMaterial else { return }
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(scaleX, scaleY, 0)
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
        }
    }
}
