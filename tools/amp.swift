import Foundation
import IOKit

// Amp probe/set via AppleALC ALCUserClient.
// Apple executeVerb ABI: verb<0x10 = 4-bit class + 16-bit param (alc-verb main.c).
//   GET amp: verb 0xB, param = dir|channel|idx:
//     out-left 0xA000|idx, out-right 0x8000|idx, in-left 0x2000|idx, in-right idx
//   SET amp: verb 0x3, param = dir|L+R(0x3000)|idx<<8|value
//     input: 0x4000, output: 0x8000; value bit7 = mute, bits6:0 = gain
// GET response: bit7 = mute, bits6:0 = stored gain.

func findService() -> io_connect_t? {
    let dict = IOServiceMatching("ALCUserClientProvider")
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, dict, &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    let s = IOIteratorNext(it)
    guard s != 0 else { return nil }
    defer { IOObjectRelease(s) }
    var c: io_connect_t = 0
    return IOServiceOpen(s, mach_task_self_, 0, &c) == KERN_SUCCESS ? c : nil
}
func verb(_ c: io_connect_t, _ nid: UInt64, _ v: UInt64, _ p: UInt64) -> UInt64 {
    var i: [UInt64] = [nid, v, p]; var o: UInt64 = 0; var n: UInt32 = 1
    return IOConnectCallScalarMethod(c, 0, &i, 3, &o, &n) == KERN_SUCCESS ? o : UInt64.max
}
func dec(_ r: UInt64) -> String {
    if r == UInt64.max { return "ERR" }
    return String(format: "%@%02llX", (r & 0x80) != 0 ? "M" : "u", r & 0x7F)
}

guard let c = findService() else { print("no svc"); exit(1) }
defer { IOServiceClose(c) }

let args = CommandLine.arguments
guard args.count >= 3, let nid = UInt64(args[2], radix: 16) else {
    print("usage: amp read <nid-hex> [input|output] | amp set <nid-hex> <in|out> <idx> <0xVAL>")
    exit(1)
}

if args[1] == "read" {
    let out = args.count > 3 && args[3] == "output"
    for idx in 0..<6 {
        let l = verb(c, nid, 0xB, (out ? 0xA000 : 0x2000) | UInt64(idx))
        let r = verb(c, nid, 0xB, (out ? 0x8000 : 0x0000) | UInt64(idx))
        if l == UInt64.max && r == UInt64.max { break }
        print(String(format: "nid 0x%02llX %@amp idx%llu: L=%@ R=%@", nid, out ? "out" : "in", idx, dec(l), dec(r)))
    }
} else if args[1] == "raw", args.count >= 5, let rv = UInt64(args[3].hasPrefix("0x") ? String(args[3].dropFirst(2)) : args[3], radix: 16), let rp = UInt64(args[4].hasPrefix("0x") ? String(args[4].dropFirst(2)) : args[4], radix: 16) {
    let resp = verb(c, nid, rv, rp)
    print(String(format: "raw nid 0x%02llX verb=0x%03llX param=0x%02llX resp=0x%llX", nid, rv, rp, resp))
} else if args[1] == "set", args.count >= 6, let idx = UInt64(args[4]), let val = UInt64(args[5].hasPrefix("0x") ? String(args[5].dropFirst(2)) : args[5], radix: 16) {
    let out = args[3] == "out"
    let param = (out ? 0x8000 : 0x4000) | 0x3000 | (idx << 8) | val
    let resp = verb(c, nid, 0x3, param)
    print(String(format: "set nid 0x%02llX %@amp idx%llu val=0x%02llX param=0x%04llX resp=0x%llX", nid, out ? "out" : "in", idx, val, param, resp))
}
