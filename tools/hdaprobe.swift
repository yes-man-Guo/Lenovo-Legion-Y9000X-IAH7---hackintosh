import Foundation
import IOKit

// HDA path telemetry via AppleALC ALCUserClient (selector 0: nid/verb/param).
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
guard let c = findService() else { print("no svc"); exit(1) }
defer { IOServiceClose(c) }

let round = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "0"
print("== probe \(round) ==")
for nid in [UInt64(0x08), 0x09, 0x22, 0x23, 0x12, 0x19, 0x1A] {
    let pwr = verb(c, nid, 0xF05, 0)
    print(String(format: "  0x%02llX pwr=%llX", nid, pwr))
}
// raw list packs + select
for nid in [UInt64(0x08), 0x09, 0x22, 0x23] {
    let sel = verb(c, nid, 0xF01, 0)
    var packs: [String] = []
    for idx in 0..<2 {
        let e = verb(c, nid, 0xF02, UInt64(idx))
        if e == UInt64.max { break }
        packs.append(String(format: "%08llX", e))
    }
    print(String(format: "  nid 0x%02llX: sel=0x%02llX packs=[%@]", nid, sel, packs.joined(separator: " ")))
}
// pin widget control of mic candidates
for nid in [UInt64(0x12), 0x19, 0x1A] {
    let pwc = verb(c, nid, 0xF07, 0)
    print(String(format: "  pin 0x%02llX pinctrl=%llX", nid, pwc))
}
// write mode: sel  hdaprobe sel <nid-hex> <idx>
if CommandLine.arguments.count > 3 && CommandLine.arguments[1] == "sel" {
    let nid = UInt64(CommandLine.arguments[2], radix: 16)!
    let idx = UInt64(CommandLine.arguments[3])!
    _ = verb(c, nid, 0x701, idx)
    let back = verb(c, nid, 0xF01, 0)
    print(String(format: "sel write %llX on 0x%02llX readback=0x%02llX", idx, nid, back))
}
// read mode: hdaprobe read <nid-hex>
if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "read" {
    let nid = UInt64(CommandLine.arguments[2], radix: 16)!
    let pwr = verb(c, nid, 0xF05, 0)
    let sel = verb(c, nid, 0xF01, 0)
    var packs: [String] = []
    for idx in 0..<3 {
        let e = verb(c, nid, 0xF02, UInt64(idx))
        if e == UInt64.max { break }
        packs.append(String(format: "%08llX", e))
    }
    let pwc = verb(c, nid, 0xF07, 0)
    print(String(format: "nid 0x%02llX: pwr=%llX sel=0x%02llX pinctrl=%llX packs=[%@]",
                 nid, pwr, sel, pwc, packs.joined(separator: " ")))
}
