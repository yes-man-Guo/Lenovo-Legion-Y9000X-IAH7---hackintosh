import Metal
import VideoToolbox
import CoreMedia
import CoreVideo
import MachO

final class Box {
    var compressed: [CMSampleBuffer] = []
    var decoded = 0
    var decodeStatus: [OSStatus] = []
}
var gBox = Box()

func grayPixelBuffer(pool: CVPixelBufferPool!, i: Int) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    guard let buf = pb else { return nil }
    CVPixelBufferLockBaseAddress(buf, [])
    if let base = CVPixelBufferGetBaseAddress(buf) {
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        for y in 0..<h {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w { row[x] = UInt8((x + y + i * 37) & 0xFF) }
        }
    }
    CVPixelBufferUnlockBaseAddress(buf, [])
    return buf
}

func compCallback(_ refCon: UnsafeMutableRawPointer?, _ src: UnsafeMutableRawPointer?, _ st: OSStatus, _ info: VTEncodeInfoFlags, _ sb: CMSampleBuffer?) {
    guard st == noErr, let sb = sb else { return }
    var cp: CMSampleBuffer?
    if CMSampleBufferCreateCopy(allocator: nil, sampleBuffer: sb, sampleBufferOut: &cp) == noErr, let c = cp {
        Unmanaged<Box>.fromOpaque(refCon!).takeUnretainedValue().compressed.append(c)
    }
}
func decompCallback(_ refCon: UnsafeMutableRawPointer?, _ src: UnsafeMutableRawPointer?, _ st: OSStatus, _ info: VTDecodeInfoFlags, _ img: CVImageBuffer?, _ pts: CMTime, _ dur: CMTime) {
    let b = Unmanaged<Box>.fromOpaque(refCon!).takeUnretainedValue()
    b.decodeStatus.append(st)
    if st == noErr && img != nil { b.decoded += 1 }
}

let codec: CMVideoCodecType = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "hevc"
    ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264

// 1. 强制加载 Metal 插件（触发解码器注册）
if let dev = MTLCreateSystemDefaultDevice() { print("Metal:", dev.name ?? "?") }
print("VTIsHardwareDecodeSupported:", VTIsHardwareDecodeSupported(codec))

// 2. 软编码 8 帧
var cs: VTCompressionSession?
let ccb: VTCompressionOutputCallback = compCallback
let ctx = Unmanaged.passRetained(gBox)
let st1 = VTCompressionSessionCreate(allocator: nil, width: 320, height: 240, codecType: codec,
    encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
    outputCallback: ccb, refcon: ctx.toOpaque(), compressionSessionOut: &cs)
print("compress session:", st1)
guard let csession = cs, st1 == noErr else { exit(1) }
VTSessionSetProperty(csession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue as CFTypeRef)
VTCompressionSessionPrepareToEncodeFrames(csession)
let pool = VTCompressionSessionGetPixelBufferPool(csession)
for i in 0..<8 {
    guard let pb = grayPixelBuffer(pool: pool, i: i) else { print("no pb"); break }
    var props: [CFString: Any] = [:]
    if i == 0 { props[kVTEncodeFrameOptionKey_ForceKeyFrame] = true }
    let r = VTCompressionSessionEncodeFrame(csession, imageBuffer: pb,
        presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: 30),
        duration: CMTime.invalid, frameProperties: props as CFDictionary,
        sourceFrameRefcon: nil, infoFlagsOut: nil)
    if r != noErr { print("encode \(i) err:", r) }
}
VTCompressionSessionCompleteFrames(csession, untilPresentationTimeStamp: CMTime.invalid)
usleep(500_000)
print("compressed frames:", gBox.compressed.count)
guard let first = gBox.compressed.first, let fmt = CMSampleBufferGetFormatDescription(first) else { print("no fmt"); exit(1) }

// 3. 用「强制硬件解码器」规格建解压会话
var ds: VTDecompressionSession?
var rec = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: nil, decompressionOutputRefCon: nil)
let wantHwOnly = !(CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "any")
let spec = wantHwOnly
    ? [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: kCFBooleanTrue] as CFDictionary
    : [:] as CFDictionary
let st3 = VTDecompressionSessionCreate(allocator: nil, formatDescription: fmt, decoderSpecification: spec,
    imageBufferAttributes: nil, outputCallback: &rec, decompressionSessionOut: &ds)
print(wantHwOnly ? "HW-REQUIRED decode session" : "NORMAL-RATING decode session (\(String(format: "%c%c%c%c", (codec>>24)&0xFF, (codec>>16)&0xFF, (codec>>8)&0xFF, codec&0xFF))):", st3,
      st3 == noErr ? "✅ 硬件解码器存在" : "❌ 无硬件解码器")
if let dsession = ds, st3 == noErr {
    for _ in 0..<2 {
        for sb in gBox.compressed {
            var fl = VTDecodeInfoFlags()
            let r = VTDecompressionSessionDecodeFrame(dsession, sampleBuffer: sb, flags: [], infoFlagsOut: &fl, completionHandler: { st2, _, img, _, _, _ in
            if st2 == noErr && img != nil { gBox.decoded += 1 }
            gBox.decodeStatus.append(st2)
        })
            if r != noErr { print("decode submit err:", r) }
        }
        // tight loop
    }
    usleep(800_000)
    usleep(300_000)
    print("decoded frames OK:", gBox.decoded, "of", gBox.compressed.count, "| statuses:", gBox.decodeStatus.map { $0 == noErr ? "ok" : "\($0)" })
}

// 4. 列出进程里加载的 nv 库
var nvlibs: [String] = []
for i in 0..<_dyld_image_count() {
    if let n = _dyld_get_image_name(i) {
        let name = String(cString: n)
        if name.contains("nvdec") || name.contains("nvenc") { nvlibs.append((name as NSString).lastPathComponent) }
    }
}
print("已加载 NV 视频库:", nvlibs.isEmpty ? "无" : nvlibs.joined(separator: ", "))
