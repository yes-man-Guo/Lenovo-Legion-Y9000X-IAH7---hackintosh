import Foundation
import IOKit

// AppleSMCClient protocol (Apple's real AppleSMC.kext, verified against beltex/SMCKit):
//   IOConnectCallStructMethod(conn, selector=2, struct, stride=80, out, 80)
//   command in struct.data8: 9 = key info, 5 = read, 6 = write, 8 = key from index
//   out.result: 0 = ok, 132 = key not found

struct SMCParamStruct {
    struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    struct SMCKeyInfoData {
        var dataSize: IOByteCount = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

func packKey(_ s: String) -> UInt32 {
    var b = Array(s.utf8.prefix(4))
    while b.count < 4 { b.append(0x20) }
    // SMC keys are big-endian FourCC: first char in the highest byte ('T','C','0','P' -> 0x54433050)
    return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
}

func typeStr(_ t: UInt32) -> String {
    let b = [UInt8(truncatingIfNeeded: t), UInt8(truncatingIfNeeded: t >> 8), UInt8(truncatingIfNeeded: t >> 16), UInt8(truncatingIfNeeded: t >> 24)]
    return String(bytes: b, encoding: .ascii) ?? "????"
}

func smcCall(_ conn: io_connect_t, _ inS: inout SMCParamStruct) -> SMCParamStruct? {
    var out = SMCParamStruct()
    var isz = MemoryLayout<SMCParamStruct>.stride
    var osz = isz
    let kr = IOConnectCallStructMethod(conn, 2, &inS, isz, &out, &osz)
    guard kr == KERN_SUCCESS else { print("  kr=0x" + String(UInt32(kr), radix: 16)); return nil }
    return out
}

func smcRead(_ conn: io_connect_t, _ key: String) -> (type: String, data: [UInt8], result: UInt8)? {
    var inS = SMCParamStruct()
    inS.key = packKey(key)
    inS.data8 = 9 // key info
    guard let o1 = smcCall(conn, &inS) else { return nil }
    guard o1.result == 0 else { return (typeStr(o1.keyInfo.dataType), [], o1.result) }
    let size = Int(o1.keyInfo.dataSize)
    let type = typeStr(o1.keyInfo.dataType)
    inS.data8 = 5 // read
    guard let o2 = smcCall(conn, &inS) else { return nil }
    guard o2.result == 0 else { return (type, [], o2.result) }
    let tuple = withUnsafeBytes(of: o2.bytes) { Array($0) }
    return (type, Array(tuple.prefix(size)), o2.result)
}

func fmt(_ type: String, _ data: [UInt8]) -> String {
    let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
    switch type {
    case "ui8": return String(data.first ?? 0) + "  [" + hex + "]"
    case "ui16", "ui32", "ui64":
        var v: UInt64 = 0
        for (i, b) in data.enumerated() { v |= UInt64(b) << (8 * i) }
        return String(v) + "  [" + hex + "]"
    case "si8":
        return String(Int8(bitPattern: data.first ?? 0)) + "  [" + hex + "]"
    case "ch8*":
        return (String(bytes: data, encoding: .ascii) ?? hex) + "  [" + hex + "]"
    default: return hex
    }
}

let dict = IOServiceMatching("AppleSMC")
var it: io_iterator_t = 0
guard IOServiceGetMatchingServices(kIOMainPortDefault, dict, &it) == KERN_SUCCESS else { print("no AppleSMC match"); exit(1) }
defer { IOObjectRelease(it) }
let svc = IOIteratorNext(it)
guard svc != 0 else { print("no AppleSMC service"); exit(1) }
var conn: io_connect_t = 0
guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { print("open fail"); exit(1) }
defer { IOServiceClose(conn) }

print("stride=" + String(MemoryLayout<SMCParamStruct>.stride))
var argv = Array(CommandLine.arguments.dropFirst())
if argv.first == "-d" { argv.removeFirst() }
let keys = argv.isEmpty ? ["B0St", "BATP", "BBAD", "BBIN", "B0FC", "B0CT", "B0AC", "B0RM", "B0PS", "B0TF", "BSIn", "BFCL", "BRSC", "BNum", "#KEY", "B0AV", "TB0T", "B0BI"] : argv
for k in keys {
    if let r = smcRead(conn, k) {
        if r.result == 0 {
            print(k.padding(toLength: 5, withPad: " ", startingAt: 0) + ": type=" + r.type + " data=" + fmt(r.type, r.data))
        } else {
            print(k.padding(toLength: 5, withPad: " ", startingAt: 0) + ": result=" + String(r.result))
        }
    } else {
        print(k.padding(toLength: 5, withPad: " ", startingAt: 0) + ": 调用失败")
    }
}
