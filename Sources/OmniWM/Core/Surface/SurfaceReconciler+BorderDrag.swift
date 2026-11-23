// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

/// The window server reports a dragged window's new position only after it moved it, so a border placed from
/// those reports always trails by a frame. While a press drags the bordered floating window, the window keeps
/// a fixed offset from the pointer, so the border is placed from the pointer instead and lands with the window.
struct BorderDragState: Equatable {
    var button: MouseEventHandler.MouseButton?
    var location: CGPoint?
    var windowId: Int?
    var pressFrame: CGRect?
    var pointer: CGPoint?
    /// The window server's latest bounds for the carried window.
    var lastFrame: CGRect?
    /// Set once the window server shows the window moving with the pointer, not resizing or sitting still.
    var isFollowingPointer = false
    /// Window-server reports in a row that disagreed with the pointer; two end following for this drag.
    var drifts = 0
    var gaveUp = false
}

extension SurfaceReconciler {
    /// Arms only for a press on a window: the bordered one now, or the one focus moves to when the press
    /// lands on it (bound on its first move, while the press point still lies inside it).
    func noteBorderPointerPressed(
        button: MouseEventHandler.MouseButton,
        at location: CGPoint,
        windowIdUnderPointer: Int?
    ) {
        cancelBorderDrag()
        guard let controller else { return }
        borderDrag = BorderDragState(button: button, location: location)
        let windowId = windowIdUnderPointer ?? controller.workspaceManager.borderFocusToken.flatMap { token in
            borderDragBounds(controller, token.windowId)?.contains(location) == true ? token.windowId : nil
        }
        guard let windowId else { return }
        borderDrag.windowId = windowId
        borderDrag.pressFrame = borderDragBounds(controller, windowId)
    }

    func noteBorderPointerDragged(to location: CGPoint, button: MouseEventHandler.MouseButton) {
        guard borderDrag.button == button else { return }
        borderDrag.pointer = location
        guard borderDrag.isFollowingPointer, let controller, let windowId = borderDrag.windowId,
              let token = controller.workspaceManager.borderFocusToken, token.windowId == windowId
        else { return }
        // A window that stopped sends no more move reports, so the pointer alone could pull the border away.
        let frame = borderDragBounds(controller, windowId)
        if let frame { borderDrag.lastFrame = frame }
        if let predicted = borderDragFrame(for: token), let frame,
           abs(frame.minX - predicted.minX) > 48 || abs(frame.minY - predicted.minY) > 48
        {
            borderDrag.isFollowingPointer = false
            borderDrag.gaveUp = true
        }
        reconcileBorderNow()
    }

    func noteBorderPointerReleased(button: MouseEventHandler.MouseButton) {
        guard borderDrag.button == button else { return }
        cancelBorderDrag()
    }

    func cancelBorderDrag() {
        let wasFollowing = borderDrag.isFollowingPointer
        borderDrag = BorderDragState()
        if wasFollowing { noteBorderChanged() }
    }

    /// Where the border goes while the pointer carries its window, or nil to use the window server's bounds.
    func borderDragFrame(for token: WindowToken) -> CGRect? {
        guard borderDrag.isFollowingPointer, borderDrag.windowId == token.windowId,
              let start = borderDrag.location, let pressFrame = borderDrag.pressFrame
        else { return nil }
        let pointer = borderDrag.pointer ?? start
        var frame = pressFrame.offsetBy(dx: pointer.x - start.x, dy: pointer.y - start.y)
        // The window server stops a title bar from rising under the menu bar of the display under the pointer,
        // but leaves one that comes down from a display above where it is.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
           frame.maxY > screen.visibleFrame.maxY,
           (borderDrag.lastFrame ?? pressFrame).maxY <= screen.visibleFrame.maxY + 1
        {
            frame.origin.y = screen.visibleFrame.maxY - frame.height
        }
        return frame
    }

    /// The bordered window moved or resized: follow it at once, from the pointer while the press carries it.
    func noteBorderWindowFrameChanged(_ token: WindowToken) {
        if let controller, let button = borderDrag.button {
            if controller.mouseEventHandler.pressedMouseButtonsProvider() & button.pressedMask == 0 {
                // The release never reached the event tap.
                borderDrag = BorderDragState()
            } else if controller.workspaceManager.entry(for: token)?.mode == .floating,
                      let frame = borderDragBounds(controller, token.windowId)
            {
                if borderDrag.windowId == nil, let location = borderDrag.location, frame.contains(location) {
                    borderDrag.windowId = token.windowId
                    borderDrag.pressFrame = frame
                    borderDrag.location = borderDrag.pointer ?? location
                } else if borderDrag.windowId == token.windowId, !borderDrag.gaveUp,
                          let pressFrame = borderDrag.pressFrame
                {
                    borderDrag.lastFrame = frame
                    noteCarriedWindowFrame(frame, pressFrame: pressFrame, token: token)
                }
            }
        }
        reconcileBorderNow()
    }

    private func noteCarriedWindowFrame(_ frame: CGRect, pressFrame: CGRect, token: WindowToken) {
        let keepsSize = abs(frame.width - pressFrame.width) <= 1 && abs(frame.height - pressFrame.height) <= 1
        guard keepsSize else {
            // A resize, which the pointer cannot predict.
            borderDrag.isFollowingPointer = false
            borderDrag.gaveUp = true
            return
        }
        guard borderDrag.isFollowingPointer else {
            guard abs(frame.minX - pressFrame.minX) > 1 || abs(frame.minY - pressFrame.minY) > 1,
                  let start = borderDrag.location, let pointer = borderDrag.pointer
            else { return }
            borderDrag.isFollowingPointer = true
            // The window starts moving only past a small dead zone; carry the border the same way.
            let slackX = pointer.x - start.x - (frame.minX - pressFrame.minX)
            let slackY = pointer.y - start.y - (frame.minY - pressFrame.minY)
            if abs(slackX) <= 4, abs(slackY) <= 4 {
                borderDrag.location = CGPoint(x: start.x + slackX, y: start.y + slackY)
            }
            return
        }
        // macOS or the app held the window back (screen edges, snapping): the pointer no longer predicts it.
        guard let predicted = borderDragFrame(for: token),
              abs(frame.minX - predicted.minX) > 12 || abs(frame.minY - predicted.minY) > 12
        else {
            borderDrag.drifts = 0
            return
        }
        borderDrag.drifts += 1
        if borderDrag.drifts >= 2 {
            borderDrag.isFollowingPointer = false
            borderDrag.gaveUp = true
        }
    }
}
