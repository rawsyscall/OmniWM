// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class BorderDragFollowTests: XCTestCase {
    func testBorderOfACarriedFloatingWindowFollowsThePointer() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 200, y: 390), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 240, y: 380), button: .left)
        XCTAssertNil(reconciler.borderDragFrame(for: token), "the pointer leads only once the window moves with it")

        bounds.frame.origin = CGPoint(x: 140, y: 90)
        reconciler.noteBorderWindowFrameChanged(token)
        bounds.frame.origin = CGPoint(x: 180, y: 70)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 300, y: 350), button: .left)
        XCTAssertEqual(reconciler.borderDragFrame(for: token), CGRect(x: 200, y: 60, width: 400, height: 300))

        reconciler.noteBorderPointerReleased(button: .right)
        XCTAssertNotNil(reconciler.borderDragFrame(for: token), "another button's release does not end the drag")
        reconciler.noteBorderPointerReleased(button: .left)
        XCTAssertNil(reconciler.borderDragFrame(for: token))
    }

    func testCarriedBorderKeepsTheWindowsDragDeadZone() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 200, y: 390), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 240, y: 380), button: .left)
        bounds.frame.origin = CGPoint(x: 139, y: 91)
        reconciler.noteBorderWindowFrameChanged(token)
        bounds.frame.origin = CGPoint(x: 180, y: 70)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 300, y: 350), button: .left)

        XCTAssertEqual(reconciler.borderDragFrame(for: token), CGRect(x: 199, y: 61, width: 400, height: 300))
    }

    func testWindowHeldAtADisplayEdgeHandsTheBorderToTheWindowServerThenReanchors() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 200, y: 390), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 200, y: 370), button: .left)
        bounds.frame.origin.y -= 20
        reconciler.noteBorderWindowFrameChanged(token)
        XCTAssertNotNil(reconciler.borderDragFrame(for: token))

        // Held: the pointer runs on while the window stays put.
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 200, y: 358), button: .left)
        reconciler.noteBorderWindowFrameChanged(token)
        XCTAssertNil(reconciler.borderDragFrame(for: token), "a window the pointer no longer predicts shows as it is")

        // Released: it rides 16 pt further from the pointer than before.
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 200, y: 346), button: .left)
        bounds.frame.origin.y = 72
        reconciler.noteBorderWindowFrameChanged(token)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 200, y: 334), button: .left)
        bounds.frame.origin.y -= 12
        reconciler.noteBorderWindowFrameChanged(token)

        XCTAssertEqual(reconciler.borderDragFrame(for: token), bounds.frame)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 200, y: 324), button: .left)
        XCTAssertEqual(reconciler.borderDragFrame(for: token), bounds.frame.offsetBy(dx: 0, dy: -10))
    }

    func testPointerCannotCarryTheBorderAwayFromAWindowThatStopped() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 200, y: 390), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 240, y: 390), button: .left)
        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 270, y: 390), button: .left)
        XCTAssertNotNil(reconciler.borderDragFrame(for: token), "a frame of lag stays carried")

        reconciler.noteBorderPointerDragged(to: CGPoint(x: 440, y: 390), button: .left)

        XCTAssertNil(reconciler.borderDragFrame(for: token))
    }

    func testProgrammaticMoveDuringAnUnrelatedHeldClickFollowsTheWindowServer() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 1200, y: 800), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 1240, y: 820), button: .left)
        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)

        XCTAssertNil(reconciler.borderDragFrame(for: token))
    }

    func testResizingDragFollowsTheWindowServer() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 499, y: 250), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 540, y: 250), button: .left)
        bounds.frame.size.width += 40
        reconciler.noteBorderWindowFrameChanged(token)

        XCTAssertNil(reconciler.borderDragFrame(for: token))
    }

    func testTiledWindowDragFollowsTheWindowServer() throws {
        let (controller, token) = try makeFocusedWindow(mode: .tiling)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 200, y: 390), windowIdUnderPointer: nil)
        reconciler.noteBorderPointerDragged(to: CGPoint(x: 240, y: 390), button: .left)
        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)

        XCTAssertNil(reconciler.borderDragFrame(for: token))
    }

    private final class BoundsBox {
        var frame = CGRect(x: 100, y: 100, width: 400, height: 300)
    }

    private func makeFocusedWindow(mode: TrackedWindowMode) throws -> (WMController, WindowToken) {
        let controller = WindowAdmissionTestSupport.controller(prefix: "OmniWMBorderDragFollowTests")
        controller.mouseEventHandler.pressedMouseButtonsProvider = {
            MouseEventHandler.MouseButton.left.pressedMask | MouseEventHandler.MouseButton.right.pressedMask
        }
        addTeardownBlock { @MainActor in
            controller.layoutRefreshController.resetState()
            controller.surfaceReconciler.cleanupBorder()
        }
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let monitor = Monitor(
            id: .init(displayId: 489_001),
            displayId: 489_001,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Border Drag"
        )
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange([monitor])
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(7_401), windowId: 61),
            pid: 7_401,
            windowId: 61,
            to: workspaceId,
            mode: mode
        )
        _ = manager.confirmManagedFocus(token, in: workspaceId, activateWorkspaceOnMonitor: false)
        XCTAssertEqual(manager.borderFocusToken, token)
        return (controller, token)
    }
}
