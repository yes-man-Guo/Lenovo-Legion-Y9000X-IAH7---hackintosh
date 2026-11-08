import VideoToolbox
import CoreMedia

let codecs: [(String, CMVideoCodecType)] = [
    ("H.264/AVC      ", kCMVideoCodecType_H264),
    ("HEVC/H.265     ", kCMVideoCodecType_HEVC),
    ("VP8            ", CMVideoCodecType(0x76703038)),
    ("VP9            ", kCMVideoCodecType_VP9),
    ("AV1            ", kCMVideoCodecType_AV1),
    ("AppleProRes422HQ", kCMVideoCodecType_AppleProRes422HQ),
    ("MPEG-2         ", kCMVideoCodecType_MPEG2Video),
    ("MJPEG          ", kCMVideoCodecType_JPEG),
]
print("== 硬件解码 VTIsHardwareDecodeSupported ==")
for (n, c) in codecs { print(n, VTIsHardwareDecodeSupported(c)) }

print("== 硬件编码器列表 VTCopyVideoEncoderList ==")
var list: CFArray?
let st = VTCopyVideoEncoderList(nil, &list)
if st == noErr, let arr = list as? [[String: Any]] {
    for e in arr {
        print("encoder:", e)
    }
} else {
    print("VTCopyVideoEncoderList error:", st)
}
