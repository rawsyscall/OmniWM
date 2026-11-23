// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class MonitorNativeModeTests: XCTestCase {
    func testWindowsFloatOnNativeMonitorAndRetileWhenTheyLeaveIt() throws {
        let fixture = try makeFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let carried = manager.addWindow(axRef(7_301, 1), pid: 7_301, windowId: 1, to: fixture.nativeWorkspace)
        let pinned = manager.addWindow(axRef(7_302, 2), pid: 7_302, windowId: 2, to: fixture.nativeWorkspace)
        manager.setManualLayoutOverride(.forceTile, for: pinned)
        let userFloated = manager.addWindow(
            axRef(7_303, 3), pid: 7_303, windowId: 3, to: fixture.tilingWorkspace, mode: .floating
        )

        controller.setNativeMode(true, for: fixture.native)

        XCTAssertEqual(manager.entry(for: carried)?.mode, .floating)
        XCTAssertEqual(manager.entry(for: pinned)?.mode, .tiling)

        controller.reassignManagedWindow(carried, to: fixture.tilingWorkspace)
        controller.reassignManagedWindow(userFloated, to: fixture.nativeWorkspace)
        controller.syncNativeModeWindows()

        XCTAssertEqual(manager.entry(for: carried)?.mode, .tiling)
        XCTAssertEqual(manager.entry(for: userFloated)?.mode, .floating)

        controller.reassignManagedWindow(carried, to: fixture.nativeWorkspace)
        controller.reassignManagedWindow(userFloated, to: fixture.tilingWorkspace)
        controller.syncNativeModeWindows()
        XCTAssertEqual(manager.entry(for: carried)?.mode, .floating)

        controller.setNativeMode(false, for: fixture.native)

        XCTAssertEqual(manager.entry(for: carried)?.mode, .tiling)
        XCTAssertEqual(manager.entry(for: userFloated)?.mode, .floating)
        XCTAssertTrue(controller.nativeModeFloatedTokens.isEmpty)
    }

    func testFloatRuleAddedWhileNativeKeepsWindowFloatingAfterNativeModeEnds() async throws {
        let fixture = try makeFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let token = WindowToken(pid: 7_321, windowId: 21)
        _ = manager.addWindow(axRef(token.pid, token.windowId), pid: token.pid, windowId: token.windowId,
                              to: fixture.nativeWorkspace)
        controller.setNativeMode(true, for: fixture.native)
        XCTAssertEqual(manager.entry(for: token)?.mode, .floating)

        controller.axEventHandler.ruleReevaluation.axWindowRefProvider = {
            AXWindowRef(element: AXUIElementCreateApplication($0.pid), windowId: $0.windowId)
        }
        controller.windowDispositionEvaluationForTests = { token in
            WMController.WindowDecisionEvaluation(
                token: token,
                facts: Self.facts(for: token),
                decision: Self.floatRuleDecision,
                appFullscreen: false,
                manualOverride: nil,
                admissionGeometry: WindowAdmissionGeometryEvidence(
                    isSizeSettable: true,
                    frame: CGRect(x: 2000, y: 100, width: 800, height: 600)
                )
            )
        }
        let outcome = await controller.reevaluateWindowRules(for: [.window(token)])
        XCTAssertTrue(outcome.evaluatedAnyWindow)

        controller.setNativeMode(false, for: fixture.native)

        XCTAssertEqual(manager.entry(for: token)?.mode, .floating)
        XCTAssertFalse(controller.nativeModeFloatedTokens.contains(token))
    }

    func testReplacedWindowStillRetilesWhenItLeavesTheNativeMonitor() throws {
        let fixture = try makeFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let original = manager.addWindow(axRef(7_331, 31), pid: 7_331, windowId: 31, to: fixture.nativeWorkspace)
        controller.setNativeMode(true, for: fixture.native)
        XCTAssertEqual(manager.entry(for: original)?.mode, .floating)

        let replacement = WindowToken(pid: 7_331, windowId: 32)
        XCTAssertNotNil(controller.axEventHandler.commitManagedWindowIdentityRebind(
            from: original,
            to: replacement,
            axRef: axRef(replacement.pid, replacement.windowId),
            managedReplacementMetadata: nil
        ))
        controller.reassignManagedWindow(replacement, to: fixture.tilingWorkspace)
        controller.syncNativeModeWindows()

        XCTAssertEqual(manager.entry(for: replacement)?.mode, .tiling)
        XCTAssertTrue(controller.nativeModeFloatedTokens.isEmpty)
    }

    func testIPCToggleAndMonitorMovesCarryModesThroughRelayout() async throws {
        let fixture = try makeRoutedFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let router = IPCCommandRouter(controller: controller, sessionToken: "test")
        let token = manager.addWindow(axRef(7_351, 51), pid: 7_351, windowId: 51, to: fixture.nativeWorkspace)
        _ = manager.withEngineMutationScope(in: fixture.nativeWorkspace) {
            controller.niriEngine?.addWindow(token: token, to: fixture.nativeWorkspace, afterSelection: nil)
        }
        try selectTiled(token, in: fixture.nativeWorkspace, on: fixture.native, controller: controller)

        XCTAssertEqual(router.handle(.toggleMonitorNativeMode), .executed)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(controller)
        XCTAssertTrue(controller.isNativeMode(fixture.native))
        XCTAssertFalse(controller.isNativeMode(fixture.tiling))
        XCTAssertEqual(manager.entry(for: token)?.mode, .floating)
        XCTAssertNil(controller.niriEngine?.findNode(for: token, in: fixture.nativeWorkspace))

        XCTAssertEqual(router.handle(.workspace(.moveToMonitor(direction: .right))), .executed)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(controller)
        XCTAssertEqual(manager.workspace(for: token), fixture.tilingWorkspace)
        XCTAssertEqual(manager.entry(for: token)?.mode, .tiling)
        XCTAssertNotNil(controller.niriEngine?.findNode(for: token, in: fixture.tilingWorkspace))

        try selectTiled(token, in: fixture.tilingWorkspace, on: fixture.tiling, controller: controller)
        XCTAssertEqual(router.handle(.workspace(.moveToMonitor(direction: .left))), .executed)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(controller)
        XCTAssertEqual(manager.workspace(for: token), fixture.nativeWorkspace)
        XCTAssertEqual(manager.entry(for: token)?.mode, .floating)
        XCTAssertTrue(controller.nativeModeFloatedTokens.contains(token))
        XCTAssertNil(controller.niriEngine?.findNode(for: token, in: fixture.nativeWorkspace))
    }

    func testDraggedWindowSettlesOnlyAfterTheButtonIsReleased() throws {
        let fixture = try makeFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let token = manager.addWindow(axRef(7_311, 11), pid: 7_311, windowId: 11, to: fixture.tilingWorkspace)
        controller.setNativeMode(true, for: fixture.native)
        controller.reassignManagedWindow(token, to: fixture.nativeWorkspace)

        controller.mouseEventHandler.pressedMouseButtonsProvider = { MouseEventHandler.MouseButton.left.pressedMask }
        controller.syncNativeModeWindows()
        XCTAssertEqual(manager.entry(for: token)?.mode, .tiling)

        controller.syncNativeModeWindows(leftButtonReleased: true)
        XCTAssertEqual(manager.entry(for: token)?.mode, .floating)
    }

    func testMonitorsWithoutTheirOwnChoiceFollowTheNativeDefault() throws {
        let fixture = try makeFixture(nativeByDefault: true)
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let onNative = manager.addWindow(axRef(7_341, 41), pid: 7_341, windowId: 41, to: fixture.nativeWorkspace)
        let onTiling = manager.addWindow(axRef(7_342, 42), pid: 7_342, windowId: 42, to: fixture.tilingWorkspace)

        controller.syncNativeModeWindows()
        XCTAssertEqual(manager.entry(for: onNative)?.mode, .floating)
        XCTAssertEqual(manager.entry(for: onTiling)?.mode, .floating)

        controller.setNativeMode(false, for: fixture.tiling)
        XCTAssertEqual(manager.entry(for: onTiling)?.mode, .tiling)

        controller.setNativeModeByDefault(false)
        XCTAssertEqual(manager.entry(for: onNative)?.mode, .tiling)
        XCTAssertEqual(manager.entry(for: onTiling)?.mode, .tiling)

        controller.setNativeModeByDefault(true)
        XCTAssertEqual(manager.entry(for: onNative)?.mode, .floating)
        XCTAssertEqual(manager.entry(for: onTiling)?.mode, .tiling)
    }

    func testNativeModeChoicesPersistThroughTOMLEvenWithoutRanking() throws {
        let fixture = try makeFixture()
        let settings = fixture.controller.settings
        settings.monitors.setNativeMode(true, for: fixture.native)
        settings.monitors.setNativeMode(false, for: fixture.tiling)

        let encoded = String(decoding: try SettingsTOMLCodec.encode(settings.toExport()), as: UTF8.self)
        XCTAssertTrue(encoded.contains("nativeModeByDefault = false"))
        XCTAssertTrue(encoded.contains("ranking = []"))
        let export = try SettingsTOMLCodec.decode(Data(encoded.replacingOccurrences(of: "ranking = []", with: "").utf8))
        settings.applyExport(.defaults())
        XCTAssertTrue(settings.monitors.nativeModeByDefault)
        XCTAssertTrue(settings.monitors.isNativeMode(fixture.tiling))

        settings.applyExport(export)

        XCTAssertFalse(settings.monitors.nativeModeByDefault)
        XCTAssertTrue(settings.monitors.isNativeMode(fixture.native))
        XCTAssertFalse(settings.monitors.isNativeMode(fixture.tiling))
    }

    private static let floatRuleDecision = WindowDecision(
        disposition: .floating,
        source: .userRule(UUID()),
        layoutDecisionKind: .explicitLayout,
        workspaceName: nil,
        ruleEffects: .none,
        admissionHints: .none,
        ruleProvenance: .none,
        heuristicReasons: [],
        deferredReason: nil
    )

    private static func facts(for token: WindowToken) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: "Native Mode",
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                title: "Notes",
                hasCloseButton: true,
                hasFullscreenButton: true,
                fullscreenButtonEnabled: true,
                hasZoomButton: true,
                hasMinimizeButton: true,
                appPolicy: .regular,
                bundleId: "com.example.native-mode",
                attributeFetchSucceeded: true
            ),
            sizeConstraints: .unconstrained,
            windowServer: WindowServerInfo(
                id: UInt32(token.windowId),
                pid: token.pid,
                level: 0,
                frame: CGRect(x: 2000, y: 100, width: 800, height: 600)
            )
        )
    }

    private struct Fixture {
        let controller: WMController
        let native: Monitor
        let tiling: Monitor
        let nativeWorkspace: WorkspaceDescriptor.ID
        let tilingWorkspace: WorkspaceDescriptor.ID
    }

    /// Tests start from tiling monitors unless they exercise the native default itself.
    private func makeFixture(nativeByDefault: Bool = false) throws -> Fixture {
        let controller = WMController(
            settings: makeSettings(),
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.mouseEventHandler.pressedMouseButtonsProvider = { 0 }
        controller.settings.monitors.nativeModeByDefault = nativeByDefault
        addTeardownBlock { @MainActor in
            controller.layoutRefreshController.resetState()
            controller.axManager.cleanup()
        }
        let mainDisplayId = CGMainDisplayID()
        let tiling = makeMonitor(mainDisplayId, "Primary", CGRect(x: 0, y: 0, width: 1800, height: 1169))
        let native = makeMonitor(mainDisplayId &+ 1, "Secondary", CGRect(x: 1800, y: 0, width: 1920, height: 1080))
        controller.workspaceManager.applyMonitorConfigurationChange([tiling, native])
        let tilingWorkspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let nativeWorkspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "6", createIfMissing: true))
        XCTAssertEqual(controller.workspaceManager.monitorId(for: tilingWorkspace), tiling.id)
        XCTAssertEqual(controller.workspaceManager.monitorId(for: nativeWorkspace), native.id)
        return Fixture(
            controller: controller,
            native: native,
            tiling: tiling,
            nativeWorkspace: nativeWorkspace,
            tilingWorkspace: tilingWorkspace
        )
    }

    /// Two side-by-side monitors with homed Niri workspaces, so monitor moves have real destinations.
    private func makeRoutedFixture() throws -> Fixture {
        let settings = makeSettings()
        settings.animationsEnabled = false
        settings.focus.followsWindowToMonitor = true
        settings.focus.moveCrossesMonitorAtEdge = false
        settings.monitors.nativeModeByDefault = false
        let native = makeMonitor(488_510, "Native Mode Left", CGRect(x: 0, y: 0, width: 1600, height: 900))
        let tiling = makeMonitor(488_511, "Native Mode Right", CGRect(x: 1600, y: 0, width: 1600, height: 900))
        settings.workspaces.configurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .specificDisplay(OutputId(from: native)), layoutType: .niri),
            WorkspaceConfiguration(name: "2", monitorAssignment: .specificDisplay(OutputId(from: tiling)), layoutType: .niri)
        ]
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.mouseEventHandler.pressedMouseButtonsProvider = { 0 }
        addTeardownBlock { @MainActor in
            controller.layoutRefreshController.resetState()
            controller.axManager.cleanup()
        }
        controller.workspaceManager.applyMonitorConfigurationChange([native, tiling])
        controller.workspaceManager.applySettings()
        let niriEngine = NiriLayoutEngine()
        niriEngine.animationClock = controller.animationClock
        controller.niriEngine = niriEngine
        controller.niriLayoutHandler.syncMonitorsToNiriEngine()

        let nativeWorkspace = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "1"))
        let tilingWorkspace = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "2"))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(
            tilingWorkspace, on: tiling.id, updateInteractionMonitor: false
        ))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(nativeWorkspace, on: native.id))
        controller.layoutRefreshController.resetState()
        return Fixture(
            controller: controller,
            native: native,
            tiling: tiling,
            nativeWorkspace: nativeWorkspace,
            tilingWorkspace: tilingWorkspace
        )
    }

    private func selectTiled(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        on monitor: Monitor,
        controller: WMController
    ) throws {
        let engine = try XCTUnwrap(controller.niriEngine)
        let handle = try XCTUnwrap(controller.workspaceManager.handle(for: token))
        let node = try XCTUnwrap(engine.findNode(for: handle, in: workspaceId))
        controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
            engine.activateWindow(node.id, in: workspaceId)
        }
        _ = controller.workspaceManager.commitWorkspaceSelection(
            nodeId: node.id,
            focusedToken: token,
            in: workspaceId,
            onMonitor: monitor.id
        )
        _ = controller.workspaceManager.setManagedFocus(token, in: workspaceId, onMonitor: monitor.id)
    }

    private func makeSettings() -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMMonitorNativeModeTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config"),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(directory: root.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
    }

    private func makeMonitor(_ displayId: CGDirectDisplayID, _ name: String, _ frame: CGRect) -> Monitor {
        Monitor(
            id: .init(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: name
        )
    }

    private func axRef(_ pid: pid_t, _ windowId: Int) -> AXWindowRef {
        AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
    }
}
