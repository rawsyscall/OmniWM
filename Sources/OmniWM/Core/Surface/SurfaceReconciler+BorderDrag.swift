// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics

/// A separate border window always trails a window the user drags across the screen, and a trailing
/// border looks broken, so the border of a floating window is put away while a press on that window
/// drags or resizes it, and comes back where the window lands once that button is let go.
struct BorderDragState: Equatable {
    var button: MouseEventHandler.MouseButton?
    var location: CGPoint?
    var windowId: Int?
    var pressFrame: CGRect?
    var hiddenToken: WindowToken?
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

    func noteBorderPointerReleased(button: MouseEventHandler.MouseButton) {
        guard borderDrag.button == button else { return }
        cancelBorderDrag()
    }

    func cancelBorderDrag() {
        let wasHidden = borderDrag.hiddenToken != nil
        borderDrag = BorderDragState()
        if wasHidden { noteBorderChanged() }
    }

    /// The bordered window moved or resized: follow it at once, or hide the border once its own press drags it.
    func noteBorderWindowFrameChanged(_ token: WindowToken) {
        if let controller, let button = borderDrag.button {
            if controller.mouseEventHandler.pressedMouseButtonsProvider() & button.pressedMask == 0 {
                // The release never reached the event tap.
                borderDrag = BorderDragState()
            } else if borderDrag.hiddenToken == nil,
                      controller.workspaceManager.entry(for: token)?.mode == .floating,
                      let frame = borderDragBounds(controller, token.windowId)
            {
                if borderDrag.windowId == nil, let location = borderDrag.location, frame.contains(location) {
                    borderDrag.windowId = token.windowId
                    borderDrag.pressFrame = frame
                } else if borderDrag.windowId == token.windowId, let start = borderDrag.pressFrame,
                          abs(frame.minX - start.minX) > 1 || abs(frame.minY - start.minY) > 1
                          || abs(frame.width - start.width) > 1 || abs(frame.height - start.height) > 1
                {
                    borderDrag.hiddenToken = token
                }
            }
        }
        reconcileBorderNow()
    }
}
