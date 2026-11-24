import AppKit
import CoreAudio
import AudioToolbox
import SwiftUI

// The mono tap supplies system-output audio. Reduce each block to two numbers
// on its serial callback queue; sample data never leaves this callback.
struct RimEnergy {
    private var low = 0.0
    private var bassFloor = 0.0
    private var envelope = 0.0
    private var pulse = 0.0
    private var cooldown = 0.0

    mutating func read(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> (Double, Double) {
        guard !samples.isEmpty, sampleRate > 0 else { return (0, 0) }
        let alpha = 1 - exp(-2 * .pi * 155 / sampleRate)
        var power = 0.0, bassPower = 0.0
        for sample in samples {
            let x = Double(sample)
            low += alpha * (x - low)
            power += x * x
            bassPower += low * low
        }
        let count = Double(samples.count), dt = count / sampleRate
        let rms = sqrt(power / count)
        let bass = sqrt(bassPower / count)
        cooldown = max(0, cooldown - dt)
        pulse *= exp(-dt / 0.25)
        if bass > max(0.017, bassFloor * 1.55), cooldown == 0 {
            pulse = min(1, (bass - bassFloor) * 6 + 0.18)
            cooldown = 0.20
        }
        bassFloor += (1 - exp(-dt / 0.48)) * (bass - bassFloor)
        let target = min(1, log1p(rms * 22) / 2.75)
        envelope += (1 - exp(-dt / (target > envelope ? 0.045 : 0.30))) * (target - envelope)
        return (envelope, pulse)
    }
}

// Owned by the serial capture-control queue.
private final class OutputTap: @unchecked Sendable {
    private let ioQueue = DispatchQueue(label: "local.verseglass.rim.samples", qos: .userInitiated)
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var io: AudioDeviceIOProcID?

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func start(_ receive: @escaping (Double, Double) -> Void) throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Verseglass Lighting"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        do {
            try check(AudioHardwareCreateProcessTap(description, &tap))
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var format = AudioStreamBasicDescription()
            var bytes = UInt32(MemoryLayout.size(ofValue: format))
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &bytes, &format))
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioFormatUnsupportedDataFormatError))
            }
            let spec: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Verseglass Lighting Input",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                    kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(spec as CFDictionary, &device))
            let rate = format.mSampleRate
            var analyzer = RimEnergy()
            var accumulatedFrames = 0
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, ioQueue) { _, input, _, _, _ in
                let buffer = input.pointee.mBuffers
                guard let base = buffer.mData, buffer.mDataByteSize > 0 else { return }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = UnsafeBufferPointer(start: base.assumingMemoryBound(to: Float.self), count: count)
                let value = analyzer.read(samples, sampleRate: rate)
                accumulatedFrames += count
                if Double(accumulatedFrames) >= rate / 24 {
                    accumulatedFrames = 0
                    receive(value.0, value.1)
                }
            })
            try check(AudioDeviceStart(device, io))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let io, device != kAudioObjectUnknown {
            AudioDeviceStop(device, io)
            AudioDeviceDestroyIOProcID(device, io)
            self.io = nil
        }
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
}

@MainActor final class RoomLighting: ObservableObject {
    static let shared = RoomLighting()
    private let tap = OutputTap()
    private let control = DispatchQueue(label: "local.verseglass.rim.capture")
    private var playing = false
    private var generation = 0
    private var wantsCapture = false
    private static let d = UserDefaults.standard

    @Published var enabled = (d.object(forKey: "rimEnabled") as? Bool) ?? true { didSet { Self.d.set(enabled, forKey: "rimEnabled"); configure() } }
    @Published var reactive = (d.object(forKey: "rimReactive") as? Bool) ?? true {
        didSet { Self.d.set(reactive, forKey: "rimReactive"); configure() }
    }
    @Published var albumColors = (d.object(forKey: "rimAlbumColors") as? Bool) ?? true { didSet { Self.d.set(albumColors, forKey: "rimAlbumColors") } }
    @Published var primaryHex = d.string(forKey: "rimPrimary") ?? "FF762E" { didSet { Self.d.set(primaryHex, forKey: "rimPrimary") } }
    @Published var secondaryHex = d.string(forKey: "rimSecondary") ?? "D5399B" { didSet { Self.d.set(secondaryHex, forKey: "rimSecondary") } }
    @Published var thickness = (d.object(forKey: "rimThickness") as? Double) ?? 6 { didSet { Self.d.set(thickness, forKey: "rimThickness") } }
    @Published var glow = (d.object(forKey: "rimGlow") as? Double) ?? 0.62 { didSet { Self.d.set(glow, forKey: "rimGlow") } }
    @Published var displayID = d.string(forKey: "rimDisplay") ?? "all" { didSet { Self.d.set(displayID, forKey: "rimDisplay") } }
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    @Published private(set) var albumAccent: Color?
    // Fast-changing levels have their own observer so the settings and window
    // manager need not invalidate their entire UI at the audio meter rate.
    let meter = RimMeter()

    var saverRim: SaverRim {
        var primary = primaryHex, secondary = secondaryHex
        if albumColors, let albumAccent, let color = NSColor(albumAccent).usingColorSpace(.sRGB) {
            primary = albumAccent.rgbHex
            let hue = (Double(color.hueComponent) + 0.11).truncatingRemainder(dividingBy: 1)
            secondary = Color(hue: hue, saturation: max(0.56, Double(color.saturationComponent)), brightness: max(0.84, Double(color.brightnessComponent))).rgbHex
        }
        return SaverRim(enabled: enabled && isRunning, level: reactive ? min(1, meter.energy + meter.pulse * 0.35) : 0.48,
                        primary: primary, secondary: secondary, thickness: thickness, glow: glow, display: displayID)
    }

    func setPalette(_ accent: Color) { if albumAccent != accent { albumAccent = accent } }
    func clearPalette() { albumAccent = nil }
    func setPlaying(_ active: Bool) {
        guard playing != active || (enabled && !reactive && !isRunning) else { return }
        playing = active
        configure()
    }

    func retry() { wantsCapture = false; configure() }

    private func configure() {
        let capture = enabled && reactive && playing
        let visible = enabled && (!reactive || playing)
        if isRunning != visible { isRunning = visible }
        if capture == wantsCapture { return }
        wantsCapture = capture
        generation += 1
        let stamp = generation, driver = tap
        meter.update(0, 0)
        status = capture ? "Connecting to system audio…" : ""
        control.async { [weak self] in
            driver.stop()
            guard capture else { return }
            do {
                try driver.start { [weak self] level, beat in
                    DispatchQueue.main.async {
                        guard let self, self.generation == stamp else { return }
                        self.meter.update(level, beat)
                    }
                }
                DispatchQueue.main.async {
                    guard let self, self.generation == stamp else { return }
                    self.status = "Listening to system audio"
                }
            } catch {
                let code = (error as NSError).code
                DispatchQueue.main.async {
                    guard let self, self.generation == stamp else { return }
                    self.status = "System audio unavailable (\(code)). Check audio recording permission, then retry."
                }
            }
        }
    }
    func stop() {
        generation += 1
        wantsCapture = false
        isRunning = false
        meter.update(0, 0)
        let driver = tap
        control.async { driver.stop() }
    }
}

@MainActor final class RimMeter: ObservableObject {
    @Published private(set) var energy = 0.0
    @Published private(set) var pulse = 0.0
    func update(_ e: Double, _ p: Double) {
        if abs(e - energy) > 0.005 || (e == 0 && energy != e) { energy = e }
        if abs(p - pulse) > 0.005 || (p == 0 && pulse != p) { pulse = p }
    }
}
