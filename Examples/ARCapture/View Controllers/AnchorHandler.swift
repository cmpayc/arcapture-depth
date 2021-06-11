//
//  AnchorHandler.swift
//  Capture
//
//  Created by Volkov Alexander on 9/27/20.
//  Copyright © 2020 Topcoder. All rights reserved.
//

import ARKit

protocol AnchorHandler {
    
    /// Process added node for anchor
    /// - Parameters:
    ///   - node: the node
    ///   - anchor: the anchor
    func processAdded(node: SCNNode, for anchor: ARAnchor)
    
    /// Process updated node
    /// - Parameters:
    ///   - node: the node
    ///   - anchor: the anchor
    func processUpdated(node: SCNNode, for anchor: ARAnchor)
    
    /// Process removed node
    /// - Parameters:
    ///   - node: the node
    ///   - anchor: the anchor
    func processRemoved(node: SCNNode, for anchor: ARAnchor)

    /// Remove all added nodes
    func removeAll()
}
