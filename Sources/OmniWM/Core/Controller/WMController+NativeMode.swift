// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

/// Native mode lets a monitor behave like stock macOS: every window on it floats freely.
/// Windows that native mode floated go back to tiling once they sit on a tiling monitor again,
/// whether the monitor leaves native mode or the window moves to another monitor.
extension WMController {
    func isNativeMode(_ monitor: Monitor) -> Bool {
        settings.monitors.isNativeMode(monitor)
    }

    func setNativeMode(_ enabled: Bool, for monitor: Monitor) {
        guard isNativeMode(monitor) != enabled else { return }
        settings.monitors.setNativeMode(enabled, for: monitor)
        // An explicit toggle (hotkey, menu click) never carries a window, even if the button is still down.
        syncNativeModeWindows(leftButtonReleased: true)
    }

    func setNativeModeByDefault(_ enabled: Bool) {
        guard settings.monitors.nativeModeByDefault != enabled else { return }
        settings.monitors.nativeModeByDefault = enabled
        syncNativeModeWindows(leftButtonReleased: true)
    }

    func toggleNativeModeOnInteractionMonitor() -> ExternalCommandResult {
        guard let monitor = monitorForInteraction() else { return .notFound }
        setNativeMode(!isNativeMode(monitor), for: monitor)
        return .executed
    }

    /// Floats tiled windows on native-mode monitors and retiles the windows native mode floated
    /// that now sit on tiling monitors. Runs before layout planning so a window never shows a tiled frame
    /// on a native monitor; any change also schedules a relayout so the layout engines drop or adopt it.
    func syncNativeModeWindows(leftButtonReleased: Bool = false) {
        let nativeMonitors = workspaceManager.monitors.filter(isNativeMode)
        guard !nativeMonitors.isEmpty || !nativeModeFloatedTokens.isEmpty else { return }
        // A drag or gesture is still carrying a window; settle once it is dropped.
        let leftButtonDown = !leftButtonReleased
            && mouseEventHandler.pressedMouseButtonsProvider() & MouseEventHandler.MouseButton.left.pressedMask != 0
        guard !leftButtonDown, !mouseEventHandler.isCarryingWindowByGesture else { return }

        let nativeMonitorIds = Set(nativeMonitors.map(\.id))
        var changedWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        for entry in workspaceManager.allEntries() {
            let token = entry.token
            guard entry.layoutReason == .standard,
                  entry.target.hostedMetadata?.role.parent == nil,
                  !workspaceManager.isScratchpadToken(token),
                  let monitor = workspaceManager.monitor(for: entry.workspaceId)
            else { continue }
            let isNative = nativeMonitorIds.contains(monitor.id)

            switch entry.mode {
            case .tiling:
                nativeModeFloatedTokens.remove(token)
                guard isNative, workspaceManager.manualLayoutOverride(for: token) != .forceTile else { continue }
                if floatForNativeMode(entry, on: monitor) {
                    nativeModeFloatedTokens.insert(token)
                    changedWorkspaceIds.insert(entry.workspaceId)
                }
            case .floating:
                guard !isNative, nativeModeFloatedTokens.remove(token) != nil,
                      workspaceManager.manualLayoutOverride(for: token) != .forceFloat
                else { continue }
                if transitionWindowMode(for: token, to: .tiling, preferredMonitor: monitor) {
                    changedWorkspaceIds.insert(entry.workspaceId)
                }
            }
        }
        nativeModeFloatedTokens = nativeModeFloatedTokens.filter { workspaceManager.entry(for: $0) != nil }

        guard !changedWorkspaceIds.isEmpty else { return }
        layoutRefreshController.requestRelayout(
            reason: .windowRuleReevaluation,
            affectedWorkspaceIds: changedWorkspaceIds
        )
    }

    /// Re-evaluation recomputes a window's baseline mode, which tiles most windows. On a native monitor that
    /// would flash the window into the layout (at the layout's frame, even mid-drag) before native mode floats
    /// it again, so a floating window there keeps floating and native mode owns it.
    func nativeModeKeepsFloating(_ entry: WindowState, decidedMode: TrackedWindowMode) -> Bool {
        guard entry.mode == .floating, decidedMode == .tiling,
              workspaceManager.manualLayoutOverride(for: entry.token) != .forceTile,
              let monitor = workspaceManager.monitor(for: entry.workspaceId), isNativeMode(monitor)
        else { return false }
        nativeModeFloatedTokens.insert(entry.token)
        return true
    }

    /// A window that its own rule or override now floats no longer belongs to native mode,
    /// so leaving the native monitor must keep it floating instead of retiling it.
    func releaseNativeModeOwnership(of token: WindowToken, ifBaselineFloats decision: WindowDecision) {
        guard decision.trackedMode == .floating,
              decision.layoutDecisionKind == .explicitLayout,
              !decision.isUnprovenIndependentRootDecision
        else { return }
        nativeModeFloatedTokens.remove(token)
    }

    /// Keeps ownership when an app replaces a window, so the replacement still retiles on a tiling monitor.
    func rekeyNativeModeOwnership(from oldToken: WindowToken, to newToken: WindowToken) {
        guard nativeModeFloatedTokens.remove(oldToken) != nil else { return }
        nativeModeFloatedTokens.insert(newToken)
    }

    private func floatForNativeMode(_ entry: WindowState, on monitor: Monitor) -> Bool {
        let token = entry.token
        let isVisible = !workspaceManager.isHiddenInCorner(token)
            && workspaceManager.activeWorkspace(on: monitor.id)?.id == entry.workspaceId
        let currentFrame = liveFrame(for: entry)
        guard workspaceManager.setWindowMode(.floating, for: token) else { return false }
        mouseEventHandler.discardNativeTitleBarDrag(for: token)
        guard let currentFrame else { return true }

        // Keep the window where it is when it already sits on this monitor; a window arriving
        // from another monitor or from a hidden workspace is centered instead.
        let visibleFrame = monitor.visibleFrame
        let frame = visibleFrame.contains(currentFrame.center)
            ? currentFrame
            : CGRect(
                x: visibleFrame.midX - currentFrame.width / 2,
                y: visibleFrame.midY - currentFrame.height / 2,
                width: currentFrame.width,
                height: currentFrame.height
            )
        if isVisible, let handle = workspaceManager.handle(for: token) {
            placeFloatingWindow(handle, frame: frame)
        } else if workspaceManager.floatingState(for: token) == nil {
            workspaceManager.updateFloatingGeometry(
                frame: FloatingFrameGeometry.clamped(frame, in: visibleFrame),
                for: token,
                referenceMonitor: monitor,
                restoreToFloating: true
            )
        }
        return true
    }
}
