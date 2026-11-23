// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
import Foundation
import OmniWMIPC

@MainActor @Observable
final class MonitorConfigurationSettings {
    private nonisolated static let defaults = SettingsExport.Routing.defaults()
    @ObservationIgnored var onChange: (() -> Void)?

    var routingMode = MonitorConfigurationSettings.defaults.mode {
        didSet { onChange?() }
    }

    var arrangements = MonitorConfigurationSettings.defaults.arrangements {
        didSet { onChange?() }
    }

    var ranking: [OutputId] = [] {
        didSet {
            let normalized = MonitorRanking.normalized(ranking)
            if normalized != ranking {
                ranking = normalized
                return
            }
            onChange?()
        }
    }

    var orientationOverrides: [MonitorOrientationSettings] = [] {
        didSet { onChange?() }
    }

    var nativeModeByDefault = true {
        didSet { onChange?() }
    }

    var nativeModeOutputs: [OutputId] = [] {
        didSet { onChange?() }
    }

    var tilingOutputs: [OutputId] = [] {
        didSet { onChange?() }
    }

    func export() -> SettingsExport.Routing {
        SettingsExport.Routing(
            mode: routingMode,
            arrangements: arrangements
        )
    }

    func orientationSettings(for monitor: Monitor) -> MonitorOrientationSettings? {
        MonitorSettingsStore.get(for: monitor, in: orientationOverrides)
    }

    func effectiveOrientation(for monitor: Monitor) -> Monitor.Orientation {
        if let override = orientationSettings(for: monitor),
           let orientation = override.orientation
        {
            return orientation
        }
        return monitor.autoOrientation
    }

    func updateOrientationSettings(_ settings: MonitorOrientationSettings, for monitor: Monitor) {
        MonitorSettingsStore.update(settings, for: monitor, in: &orientationOverrides)
    }

    func removeOrientationSettings(for monitor: Monitor) {
        MonitorSettingsStore.remove(for: monitor, from: &orientationOverrides)
    }

    /// A monitor's own choice wins; monitors without one follow `nativeModeByDefault`.
    func isNativeMode(_ monitor: Monitor) -> Bool {
        let output = OutputId(from: monitor)
        if nativeModeOutputs.contains(output) { return true }
        if tilingOutputs.contains(output) { return false }
        return nativeModeByDefault
    }

    func setNativeMode(_ enabled: Bool, for monitor: Monitor) {
        let output = OutputId(from: monitor)
        let native = nativeModeOutputs.filter { $0 != output } + (enabled ? [output] : [])
        let tiling = tilingOutputs.filter { $0 != output } + (enabled ? [] : [output])
        if native != nativeModeOutputs { nativeModeOutputs = native }
        if tiling != tilingOutputs { tilingOutputs = tiling }
    }

    func storeRoutingLayout(_ layout: [MonitorRoutingSettings], for monitors: [Monitor]) {
        MonitorRouting.store(layout, for: monitors, in: &arrangements)
    }
}
