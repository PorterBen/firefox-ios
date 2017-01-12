/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * ScreenGraph helps you get rid of the navigation boiler plate found in a lot of whole-application UI testing.
 *
 * You create a shared graph of UI 'screens' or 'scenes' for your app, and use it for every test.
 *
 * In your tests, you use a navigator which does the job of getting your tests from place to place in your application,
 * leaving you to concentrate on testing, rather than maintaining brittle and duplicated navigation code.
 * 
 * The shared graph may also have other uses, such as generating screen shots for the App Store or L10n translators.
 *
 * Under the hood, the ScreenGraph is using GameplayKit's path finding to do the heavy lifting.
 */

import Foundation
import GameplayKit
import XCTest

typealias Edge = (XCTestCase, String, UInt) -> ()
typealias SceneBuilder = (ScreenGraphNode) -> ()
typealias NodeVisitor = (String) -> ()

/**
 * ScreenGraph
 * This is the main interface to building a graph of screens/app states and how to navigate between them.
 * The ScreenGraph will be used as a map to navigate the test agent around the app.
 */
public class ScreenGraph {
    let app: XCUIApplication
    var initialSceneName: String?

    var namedScenes: [String: ScreenGraphNode] = [:]
    var nodedScenes: [GKGraphNode: ScreenGraphNode] = [:]

    var isReady: Bool = false

    let gkGraph: GKGraph

    init(_ app: XCUIApplication) {
        self.app = app
        self.gkGraph = GKGraph()
    }
}

extension ScreenGraph {
    /**
     * Method for creating a ScreenGraphNode in the graph. The node should be accompanied by a closure 
     * used to document the exits out of this node to other nodes.
     */
    func createScene(name: String, builder: (ScreenGraphNode) -> ()){
        let scene = ScreenGraphNode(map: self, name: name, builder: builder)
        namedScenes[name] = scene
        nodedScenes[scene.gkNode] = scene
    }
}

extension ScreenGraph {
    /**
     * Create a new navigator object. Navigator objects are the main way of getting around the app.
     * Typically, you'll do this in `TestCase.setUp()`
     */
    func navigator(xcTest: XCTestCase, startingAt: String? = nil, file: String = #file, line: UInt = #line) -> Navigator {
        buildGkGraph()
        var current: ScreenGraphNode?
        if let name = startingAt ?? initialSceneName {
            current = namedScenes[name]
        }

        if current == nil {
            xcTest.recordFailureWithDescription("The app's initial state couldn't be established.",
                inFile: file, atLine: line, expected: false)
        }
        return Navigator(self, xcTest: xcTest, initialScene: current!)
    }

    private func buildGkGraph() {
        if isReady {
            return
        }

        isReady = true

        // Construct all the GKGraphNodes, and add them to the GKGraph.
        let scenes = namedScenes.values
        gkGraph.addNodes(scenes.map { $0.gkNode })

        // Now, use the scene builders to collect edge actions and destinations.
        scenes.forEach { scene in
            scene.builder(scene)
        }

        scenes.forEach { scene in
            let gkNodes = scene.edges.keys.flatMap { self.namedScenes[$0]?.gkNode } as [GKGraphNode]
            scene.gkNode.addConnectionsToNodes(gkNodes, bidirectional: false)
        }
    }
}

typealias Gesture = () -> ()

/**
 * The ScreenGraph is made up of nodes. It is not possible to init these directly, only by creating 
 * screen nodes from the ScreenGraph object.
 * 
 * The ScreenGraphNode has all the methods needed to navigate from this node to another node, using the usual 
 * XCUIElement method of moving about.
 */
class ScreenGraphNode {
    let name: String
    private let builder: SceneBuilder
    private let gkNode: GKGraphNode
    private var edges: [String: Edge] = [:]

    private weak var map: ScreenGraph?

    // Iff this node has a backAction, this store temporarily stores 
    // the node we were at before we got to this one. This becomes the node we return to when the backAction is 
    // invoked.
    private weak var returnNode: ScreenGraphNode?

    private var hasBack: Bool {
        return backAction != nil
    }

    /**
     * This is an action that will cause us to go back from where we came from.
     * This is most useful when the same screen is accessible from multiple places, 
     * and we have a back button to return to where we came from.
     */
    var backAction: Gesture?

    /**
     * This flag indicates that once we've moved on from this node, we can't come back to 
     * it via `backAction`. This is especially useful for Menus, and dialogs.
     */
    var dismissOnUse: Bool = false

    var existsWhen: XCUIElement? = nil

    private init(map: ScreenGraph, name: String, backAction: Gesture? = nil, builder: SceneBuilder) {
        self.map = map
        self.name = name
        self.gkNode = GKGraphNode()
        self.builder = builder
        self.backAction = backAction
    }

    private func addEdge(dest: String, by edge: Edge) {
        edges[dest] = edge
        // by this time, we should've added all nodes in to the gkGraph.

        assert(map?.namedScenes[dest] != nil, "Destination scene '\(dest)' has not been created anywhere")
    }
}

private let existsPredicate = NSPredicate(format: "exists == true")

// A set of methods for defining edges out of this node.
extension ScreenGraphNode {
    private func waitForElement(element: XCUIElement, withTest xcTest: XCTestCase) {
        // TODO report the error in the correct place.
        // Two options: where the graph is constructed (graph is wrong), or where the app is tested (app is wrong).
        xcTest.expectationForPredicate(existsPredicate,
                                       evaluatedWithObject: element, handler: nil)
        xcTest.waitForExpectationsWithTimeout(2, handler: nil)
    }

    // A gesture that takes the navigator from the current scene to the named one.
    // If an element is provided, then the wait for it to appear on the screen.
    func gesture(withElement element: XCUIElement? = nil, to nodeName: String, g: () -> ()) {
        addEdge(nodeName) { xcTest, file, line in
            if let el = element {
                self.waitForElement(el, withTest: xcTest)
            }
            g()
        }
    }

    func noop(to nodeName: String) {
        self.gesture(to: nodeName) {
            // NOOP.
        }
    }

    func tap(element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.tap()
        }
    }

    func doubleTap(element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.doubleTap()
        }
    }

    func typeText(text: String, into element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.typeText(text)
        }
    }

    func swipeLeft(element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.swipeLeft()
        }
    }

    func swipeRight(element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.swipeRight()
        }
    }

    func swipeUp(element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.swipeUp()
        }
    }

    func swipeDown(element: XCUIElement, to nodeName: String) {
        self.gesture(withElement: element, to: nodeName) {
            element.swipeDown()
        }
    }
}

class Navigator {
    private let map: ScreenGraph
    private var currentScene: ScreenGraphNode
    private var returnToRecentScene: ScreenGraphNode
    private let xcTest: XCTestCase

    private init(_ map: ScreenGraph, xcTest: XCTestCase, initialScene: ScreenGraphNode) {
        self.map = map
        self.xcTest = xcTest
        self.currentScene = initialScene
        self.returnToRecentScene = initialScene
    }

    // Use the map to move the user to the given node.
    func goto(nodeName: String, file: String = #file, line: UInt = #line) {
        let gkSrc = currentScene.gkNode
        guard let gkDest = map.namedScenes[nodeName]?.gkNode else {
            xcTest.recordFailureWithDescription("Cannot route to \(nodeName), because it doesn't exist", inFile: file, atLine: line, expected: false)
            return
        }

        var gkPath = map.gkGraph.findPathFromNode(gkSrc, toNode: gkDest)
        guard gkPath.count > 0 else {
            xcTest.recordFailureWithDescription("Cannot route to \(nodeName) from \(currentScene.name)", inFile: file, atLine: line, expected: false)
            return
        }

        gkPath.removeFirst()
        gkPath.forEach { gkNext in
            if !currentScene.dismissOnUse {
                returnToRecentScene = currentScene
            }

            let nextScene = map.nodedScenes[gkNext]!
            let action = currentScene.edges[nextScene.name]!

            // We definitely have an action, so it's save to unbox.
            action(xcTest, file, line)

            if let testElement = nextScene.existsWhen {
                nextScene.waitForElement(testElement, withTest: xcTest)
            }

            if nextScene.hasBack {
                if nextScene.returnNode == nil {
                    nextScene.returnNode = returnToRecentScene
                    nextScene.gkNode.addConnectionsToNodes([ returnToRecentScene.gkNode ], bidirectional: false)
                    nextScene.gesture(to: returnToRecentScene.name, g: nextScene.backAction!)
                }
            }

            if currentScene.hasBack {
                if nextScene.name == currentScene.returnNode?.name {
                    currentScene.returnNode = nil
                    currentScene.gkNode.removeConnectionsToNodes([ nextScene.gkNode ], bidirectional: false)
                }
            }
            currentScene = nextScene
        }
    }

    // Helper method when the navigator gets out of sync with the actual app.
    // This should not be used too often, as it indicates you should probably have another node in your graph.
    func nowAt(nodeName: String, file: String = #file, line: UInt = #line) {
        guard let newScene = map.namedScenes[nodeName] else {
            xcTest.recordFailureWithDescription("Cannot force to unknown \(nodeName). Currently at \(currentScene.name)", inFile: file, atLine: line, expected: false)
            return
        }
        currentScene = newScene
    }

    func visit(nodes: String..., f: NodeVisitor) {
        self.visitNodes(nodes, f: f)
    }

    func visitNodes(nodes: [String], f: NodeVisitor) {
        nodes.forEach { node in
            self.goto(node)
            f(node)
        }
    }

    func visitAll(f: NodeVisitor) {
        let nodes: [String] = self.map.namedScenes.keys.map { $0 } // keys can't be coerced into a [String]
        self.visitNodes(nodes, f: f)
    }

    func revert() {
        if let initial = self.map.initialSceneName {
            self.goto(initial)
        }
    }
}
