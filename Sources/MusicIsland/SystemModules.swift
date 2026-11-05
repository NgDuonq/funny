import Foundation
import CoreAudio
import IOKit.ps

/// Core Audio property notifications and IOKit power-source notifications; no polling timer.
@MainActor final class SystemModules {
    let bus: EventBus
    private var powerSource: CFRunLoopSource?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var lastVolume: Float32?
    private var lastPower: String?
    private var device: AudioObjectID = 0
    init(bus: EventBus) { self.bus = bus }
    func start() {
        guard powerSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let module = Unmanaged<SystemModules>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in module.readBattery() }
        }, context)?.takeRetainedValue() {
            powerSource = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        readBattery()
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal) { [weak self] in self?.bindOutput() }
        bindOutput()
    }
    func stop() {
        if let source = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        powerSource = nil
        for entry in listeners { var address = entry.1; AudioObjectRemovePropertyListenerBlock(entry.0, &address, .main, entry.2) }
        listeners.removeAll(); lastVolume = nil; lastPower = nil
    }
    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, action: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in Task { @MainActor in action() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr { listeners.append((object, address, block)) }
    }
    private func bindOutput() {
        for entry in listeners where entry.0 != AudioObjectID(kAudioObjectSystemObject) {
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(entry.0, &address, .main, entry.2)
        }
        listeners.removeAll { $0.0 != AudioObjectID(kAudioObjectSystemObject) }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return }
        lastVolume = nil; readVolume()
        listen(device, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput) { [weak self] in self?.readVolume() }
        listen(device, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput) { [weak self] in self?.readVolume() }
    }
    private func readVolume() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return }
        var mute: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size); address.mSelector = kAudioDevicePropertyMute
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr && mute != 0 { value = 0 }
        defer { lastVolume = value }
        guard let old = lastVolume, abs(old - value) > 0.001 else { return }
        bus.post(IslandCoreEvent.volume(value))
    }
    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = capacity * 100 / maximum
            let ac = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let key = "\(ac)-\(percent <= 20)"
            defer { lastPower = key }
            guard let old = lastPower, old != key else { continue }
            bus.post(IslandCoreEvent.battery(ac: ac, percent: percent))
        }
    }
}
import IslandCore
private enum IslandCoreEvent {
    static func volume(_ value: Float32) -> IslandEvent {
        IslandEvent(id: "system.volume", title: "Âm lượng \(Int(value * 100))%", symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", priority: 30, progress: Double(value), expiresAt: Date().addingTimeInterval(1.5))
    }
    static func battery(ac: Bool, percent: Int) -> IslandEvent {
        IslandEvent(id: "system.battery", title: "\(ac ? "Đã cắm sạc" : "Dùng pin") · \(percent)%", symbol: ac ? "battery.100.bolt" : "battery.25", priority: percent <= 20 ? 70 : 40, progress: Double(percent) / 100, expiresAt: Date().addingTimeInterval(3))
    }
}
