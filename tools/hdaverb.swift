import Foundation
import IOKit

// Deep ADC-path telemetry via ALCUserClient.
func findService() -> io_connect_t? {
    let dict = IOServiceMatching("ALCUserClientProvider")
    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, dict, &iterator)
    guard kr == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }
    let service = IOIteratorNext(iterator)
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var connect: io_connect_t = 0
    let openKr = IOServiceOpen(service, mach_task_self_, 0, &connect)
    if openKr != KERN_SUCCESS { return nil }
    return connect
}

func verb(_ connect: io_connect_t, _ nid: UInt64, _ verb: UInt64, _ param: UInt64) -> UInt64 {
    var input: [UInt64] = [nid, verb, param]
    var output: UInt64 = 0
    var outCount: UInt32 = 1
    let kr = IOConnectCallScalarMethod(connect, 0, &input, 3, &output, &outCount)
    if kr != KERN_SUCCESS { return UInt64.max }
    return output
}


// write mode: set connection select on a node
if CommandLine.arguments.count > 3 && CommandLine.arguments[1] == "sel" {
    let nid = UInt64(CommandLine.arguments[2])!
    let idx = UInt64(CommandLine.arguments[3])!
    guard let c = findService() else { print("no service"); exit(1) }
    defer { IOServiceClose(c) }
    _ = verb(c, nid, 0x701, idx) // SET_CONNECT_SEL
    let back = verb(c, nid, 0xF01, 0)
    print(String(format: "wrote sel idx %llu on 0x%02llX, readback=%llX", idx, nid, back))
    exit(0)
}

guard let connect = findService() else {
    print("ALCUserClientProvider not found")
    exit(1)
}
defer { IOServiceClose(connect) }

let round = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "0"
print("== probe round \(round) @ \(Int(Date().timeIntervalSince1970)) ==")
for nid in [UInt64(0x08), 0x09, 0x22, 0x23, 0x12, 0x19, 0x1A] {
    let pwr = verb(connect, nid, 0xF05, 0)
    print(String(format: "  0x%02llX pwr=%llX", nid, pwr))
}
for nid in [UInt64(0x22), 0x23] {
    let sel = verb(connect, nid, 0xF01, 0)
    print(String(format: "  mixer 0x%02llX connSel=%llX", nid, sel))
    var entries: [UInt64] = []
    for idx in 0..<6 {
        let e = verb(connect, nid, 0xF02, UInt64(idx))
        if e == UInt64.max { break }
        entries.append(e & 0xFF)
    }
    print(String(format: "  mixer 0x%02llX connList=[%@]", nid, entries.map { String(format: "0x%02llX", $0) }.joined(separator: ",")))
}
for nid in [UInt64(0x12), 0x19, 0x1A] {
    let gain = verb(connect, nid, 0xF0B, 0x8000)
    print(String(format: "  pin 0x%02llX inAmp=%llX", nid, gain))
}
for nid in [UInt64(0x08), 0x09] {
    let gain = verb(connect, nid, 0xF0B, 0x8000)
    print(String(format: "  ADC 0x%02llX inAmp=%llX", nid, gain))
}
let cfg1A = verb(connect, 0x1A, 0xF1C, 0)
let cfg12 = verb(connect, 0x12, 0xF1C, 0)
print(String(format: "  cfg byte0: 0x12=%llX 0x1A=%llX", cfg12, cfg1A))
