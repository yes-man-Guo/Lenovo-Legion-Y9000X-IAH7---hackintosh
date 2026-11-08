// SSDT-CSPK: release the CS35L41 smart-amp reset line at ACPI init, plus
// on-demand AML helpers for the driver.
//
// Board: Lenovo Legion Y9000X 2022 IAH7 (17AA386E, ALC287 + 2x CS35L41 on I2C3)
// Reset line: GPIO offset 96 on \_SB.GPI0 (INTC1055) = pinctrl pin 67
//             (GPP_S0 / SNDW0_CLK), BIOS-configured GPIO output driving LOW
//             (amps held in reset). Linux releases it by writing PADCFG0
//             TXVAL=1; end state = DW0 0x84000201.
// Address:    community window 0xFD6D0000 + PADCFG base 0x700 + pad 0 * 16
//             = 0xFD6D0700 (verified against the firmware's own GPCL table
//             in the DSDT: group 7 = {0x6D0000, 8 pads, padcfg 0x700}).
//             On macOS the kext MMIO path is hardware-dropped for PADCFG
//             stores; AML OperationRegion stores take — this SSDT is the
//             working write path, so the driver's on-demand reset pulse also
//             runs here instead of in the kext.
DefinitionBlock ("", "SSDT", 2, "LENOVO", "CSPK", 0x00001001)
{
    Device (\_SB.CSPK)
    {
        Name (_HID, "CSPK0000")  // no driver binds; exists to run _INI
        Name (_STA, 0x0F)
        OperationRegion (CSW0, SystemMemory, 0xFD6D0700, 0x04)
        Field (CSW0, AnyAcc, NoLock, Preserve)
        {
            CDW0, 32
        }
        Method (_INI, 0, NotSerialized)
        {
            // TXVAL=1 (release reset); preserve PMODE=GPIO, TXDIS=0, RXDIS=1.
            CDW0 = 0x84000201
        }
        // On-demand reset pulse: the Linux cs35l41_hda probe sequence
        // (RSTN asserted 10ms, then released). CS35L41 requires all supplies
        // stable BEFORE RSTN deassertion; the firmware-only release at ACPI
        // init ran before the amplifier rail could have been gated on, so a
        // fresh low→high pulse after power-up re-arms the amps. Callers must
        // only invoke this while the amplifiers are unbound (never during
        // playback — -cirrusnodsp means no DSP speaker protection).
        Method (RPST, 0, NotSerialized)
        {
            CDW0 = 0x84000200
            Sleep (10)
            CDW0 = 0x84000201
        }
        // Read-back of the reset pad's PADCFG0 (post-pulse verification).
        Method (GPDW, 0, NotSerialized)
        {
            Return (CDW0)
        }
    }
}
