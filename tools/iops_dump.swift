import Foundation
import IOKit.ps

// Dump all power source dictionaries published by powerd (IOPowerSources API).
let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [AnyObject]
print("power sources: \(list.count)")
for ps in list {
    let desc = IOPSGetPowerSourceDescription(blob, ps).takeUnretainedValue() as! [String: Any]
    print("== power source ==")
    for (k, v) in desc.sorted(by: { $0.key < $1.key }) {
        print("  " + k + " = " + String(describing: v))
    }
}
// Top-level power sources details
if let details = IOPSGetPowerSourceDescription(blob, nil) {
    // nil returns the overall details dictionary on some versions
    print("== top-level ==")
    print(details)
}
