// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics

/// A separate border window always trails a window the user drags across the screen, and a trailing
/// border looks broken, so the border of a floating window is put away while a press drags it and
/// comes back where the window lands once the button is let go.
struct BorderDragState: Equatable {
    var isPressed = false
    var pressedToken: WindowToken?
    var pressFrame: CGRect?
    var hiddenToken: WindowToken?
}

extension SurfaceReconciler {
    func noteBorderPointerPressed() {
        borderDrag = BorderDragState(isPressed: true)
        guard let controller, let token = controller.workspaceManager.borderFocusToken else { return }
        borderDrag.pressedToken = token
        borderDrag.pressFrame = borderDragBounds(controller, token.windowId)
    }

    func noteBorderPointerReleased() {
        let wasHidden = borderDrag.hiddenToken != nil
        borderDrag = BorderDragState()
        if wasHidden { noteBorderChanged() }
    }

    /// The bordered window moved or resized: follow it at once, or hide the border once a press drags it.
    func noteBorderWindowFrameChanged(_ token: WindowToken) {
        if borderDrag.isPressed, borderDrag.hiddenToken == nil, let controller,
           controller.workspaceManager.entry(for: token)?.mode == .floating
        {
            let frame = borderDragBounds(controller, token.windowId)
            if borderDrag.pressedToken != token {
                // Focus moved to this window after the press went down; measure the drag from here.
                borderDrag.pressedToken = token
                borderDrag.pressFrame = frame
            } else if let frame, let start = borderDrag.pressFrame,
                      abs(frame.minX - start.minX) > 1 || abs(frame.minY - start.minY) > 1
                      || abs(frame.width - start.width) > 1 || abs(frame.height - start.height) > 1
            {
                borderDrag.hiddenToken = token
            }
        }
        reconcileBorderNow()
    }
}
