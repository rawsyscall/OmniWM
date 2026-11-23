// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class BorderDragSuppressionTests: XCTestCase {
    func testFloatingBorderHidesOnlyWhileAPressOnItsWindowDragsIt() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)
        XCTAssertNil(reconciler.borderDrag.hiddenToken, "a move without a press is followed, not hidden")

        reconciler.noteBorderPointerPressed(button: .left, at: bounds.frame.center, windowIdUnderPointer: nil)
        reconciler.noteBorderWindowFrameChanged(token)
        XCTAssertNil(reconciler.borderDrag.hiddenToken, "a click that moves nothing keeps the border")

        bounds.frame.origin.y += 30
        reconciler.noteBorderWindowFrameChanged(token)
        XCTAssertEqual(reconciler.borderDrag.hiddenToken, token)
        XCTAssertEqual(WorldView(controller: controller).borderHiddenForDragToken, token)

        reconciler.noteBorderPointerReleased(button: .right)
        XCTAssertEqual(reconciler.borderDrag.hiddenToken, token, "another button's release does not end the drag")
        reconciler.noteBorderPointerReleased(button: .left)
        XCTAssertNil(reconciler.borderDrag.hiddenToken)
    }

    func testProgrammaticMoveDuringAnUnrelatedHeldClickKeepsTheBorder() throws {
        let (controller, token) = try makeFocusedWindow(mode: .floating)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: CGPoint(x: 1200, y: 800), windowIdUnderPointer: nil)
        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)
        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)

        XCTAssertNil(reconciler.borderDrag.hiddenToken)
        XCTAssertNil(WorldView(controller: controller).borderHiddenForDragToken)
    }

    func testTiledWindowDragKeepsItsBorder() throws {
        let (controller, token) = try makeFocusedWindow(mode: .tiling)
        let reconciler = controller.surfaceReconciler
        let bounds = BoundsBox()
        reconciler.borderDragBounds = { _, _ in bounds.frame }

        reconciler.noteBorderPointerPressed(button: .left, at: bounds.frame.center, windowIdUnderPointer: nil)
        bounds.frame.origin.x += 40
        reconciler.noteBorderWindowFrameChanged(token)

        XCTAssertNil(reconciler.borderDrag.hiddenToken)
    }

    private final class BoundsBox {
        var frame = CGRect(x: 100, y: 100, width: 400, height: 300)
    }

    private func makeFocusedWindow(mode: TrackedWindowMode) throws -> (WMController, WindowToken) {
        let controller = WindowAdmissionTestSupport.controller(prefix: "OmniWMBorderDragSuppressionTests")
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
