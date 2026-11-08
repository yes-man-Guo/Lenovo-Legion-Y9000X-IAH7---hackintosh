/*
 * SSDT-BAT0 v3: Fix battery readings for Lenovo Y9000X (L21B4PE1, 99.99Wh)
 *
 * v2 lesson: SMC keys publish capacities as 16-bit values - anything above
 * 65535 wraps (99990 -> 34454). v3 publishes REAL-MAC-LIKE mAh values:
 *
 *   - _BIX[1] PowerUnit = 1 (mAh) so SMCBatteryManager skips mWh conversion
 *   - _BIX[2] DesignCapacity = 6442 mAh (label 99.99Wh @ 15.52V)
 *   - _BIX[5] DesignVoltage = 15520 mV (DSDT left 0xFFFFFFFF here!)
 *   - _BIX[3] FCC = original * 3558/15520 (mWh->mAh * 3.558 health boost),
 *     capped at 6377 (99% of design); all values stay under 65535
 *   - _BST[0] clears the vendor "critical energy" bit (0x04) mapped from
 *     ECWR&0x40 - the same EC whose capacity data is proven 2.9x off;
 *     this bit is the remaining suspect for the bogus Service Recommended
 *   - _BST[1]/[2] rate and remaining capacity rescaled to the same mAh units
 */

DefinitionBlock ("", "SSDT", 2, "HACK", "BAT0FIX", 0x00001000)
{
    External (_SB_.PC00.LPCB.H_EC.BAT0, DeviceObj)
    External (_SB_.PC00.LPCB.H_EC.BAT0.XBIX, MethodObj)
    External (_SB_.PC00.LPCB.H_EC.BAT0.XBST, MethodObj)

    Scope (\_SB.PC00.LPCB.H_EC.BAT0)
    {
        Method (_BIX, 0, Serialized)
        {
            Local0 = XBIX ()

            /* [1] PowerUnit = 1 (mAh) - skips kext mWh conversion */
            Local0 [0x01] = One

            /* [2] DesignCapacity = 6442 mAh (99.99Wh label) */
            Local0 [0x02] = 0x192A

            /* [5] DesignVoltage = 15520 mV (original left 0xFFFFFFFF) */
            Local0 [0x05] = 0x3CA0

            /* [3] FCC = original * 3558/15520, cap at 6377 (99%) */
            Local1 = DerefOf (Local0 [0x03])
            Local2 = (Local1 * 0x0DE6)
            Local2 /= 0x3CA0
            If (Local2 > 0x18E9)
            {
                Local2 = 0x18E9
            }
            Local0 [0x03] = Local2

            /* [6] warning / [7] low follow the new FCC */
            Local0 [0x06] = (Local2 / 0x0A)
            Local0 [0x07] = (Local2 / 0x19)

            Return (Local0)
        }

        Method (_BST, 0, NotSerialized)
        {
            Local0 = XBST ()

            /* [0] clear vendor critical bit 0x04 (untrusted EC flag) */
            Local1 = DerefOf (Local0 [Zero])
            Local0 [Zero] = (Local1 & 0xFFFFFFFB)

            /* [1] present rate: mW -> mAh scale, skip 0xFFFFFFFF marker */
            Local1 = DerefOf (Local0 [One])
            If (Local1 < 0x0FFF0000)
            {
                Local2 = (Local1 * 0x03E8)
                Local2 /= 0x3CA0
                Local0 [One] = Local2
            }

            /* [2] remaining capacity: same scale as FCC */
            Local1 = DerefOf (Local0 [0x02])
            If (Local1 < 0x0FFF0000)
            {
                Local2 = (Local1 * 0x0DE6)
                Local2 /= 0x3CA0
                Local0 [0x02] = Local2
            }

            Return (Local0)
        }
    }
}
