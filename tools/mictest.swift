import AVFoundation
import Foundation
import AppKit

// Mic signal test v2: bypass AVAudioFile — accumulate raw float32 samples
// from the tap and dump to /tmp/micraw.f32 for offline RMS analysis.
let sem = DispatchSemaphore(value: 0)
AVCaptureDevice.requestAccess(for: .audio) { granted in
    print("mic permission granted: \(granted)")
    sem.signal()
}
sem.wait()

let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
guard format.sampleRate > 0, format.channelCount > 0 else {
    print("ERROR: no input format")
    exit(1)
}
print("input: \(format.sampleRate) Hz, \(format.channelCount) ch")

var samples: [Float] = []
var taps = 0
var firstDesc = ""
let lock = NSLock()
engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    lock.lock()
    taps += 1
    if taps == 1 {
        firstDesc = "buffer format: \(buffer.format.sampleRate) Hz, \(buffer.format.channelCount) ch, interleaved=\(buffer.format.isInterleaved)"
    }
    let n = Int(buffer.frameLength)
    if let chans = buffer.floatChannelData, buffer.format.channelCount > 0 {
        let c = Int(buffer.format.channelCount)
        for f in 0..<n {
            for k in 0..<c {
                samples.append(chans[k][f])
            }
        }
    }
    lock.unlock()
}

do { try engine.start() } catch {
    print("ERROR: engine start failed: \(error)")
    exit(1)
}
print("recording 8 seconds...")
Thread.sleep(forTimeInterval: 8.0)
engine.inputNode.removeTap(onBus: 0)
engine.stop()

lock.lock()
print("tap buffers: \(taps), samples: \(samples.count)")
print(firstDesc)
if taps == 0 {
    print("SUSPECT: no input buffers delivered")
    exit(2)
}
let out = samples.withUnsafeBytes { Data($0) }
try? out.write(to: URL(fileURLWithPath: "/tmp/micraw.f32"))
print("dumped /tmp/micraw.f32 (\(out.count) bytes)")
if let first = samples.prefix(8).first {
    print("first sample: \(first)")
}
lock.unlock()
