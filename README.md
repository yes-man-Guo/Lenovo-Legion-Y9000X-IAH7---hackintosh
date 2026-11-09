# Lenovo Legion Y9000X 2022 (IAH7) Hackintosh

Lenovo Legion Y9000X 2022 的 OpenCore 黑苹果工程与排查记录。

- **机型**：i5-12500H (Alder Lake-P) + RTX 3050 Ti Laptop + AX211 Wi-Fi/BT
- **系统**：macOS 15.8 Sequoia，OpenCore（AAPL debug 版）
- **图形**：NullMoth/NVRM 社区驱动（NVRM/NVAccel/NVRMAGDC/NVRMFB）直驱内屏，H.264/HEVC 硬编硬解全通

## 当前状态（2026-11-08）

| 部件 | 状态 | 方案 |
|---|---|---|
| GPU 加速 | ✅ | NVRM 2.7.2 社区驱动（`/Library/Extensions`）+ AMFIPass |
| 扬声器 | ✅ | ALC287 (alcid=13) + CS35L41 I2C 功放，SSDT-CSPK `RPST` AML 复位脉冲 + CirrusAudioFixup + VoodooGPIO |
| Wi-Fi | ✅ | itlwm + HeliPort |
| 蓝牙 | ✅ | AX211 (8087:0033, BlazarU) 需要 IntelBluetoothFirmware v2.5.3 的 ibt-0093-0041 固件 |
| 触摸板 | ✅ | VoodooI2C fork（ADL-P personality + TransfeToAddress 补丁） |
| 内建麦克风 | ❌ | 阵列接 PCH DMIC (Intel SST/SOF)，AppleHDA 无此驱动，**macOS 硬件级无解**（Ubuntu 实测：DMIC 录到声、codec 路径 -85dB 纯静音，双系统互证结案）；用 3.5mm 耳麦 / USB 麦替代 |
| 电池修正 | ✅ | SSDT-BAT0 v3.1：EC 容量换算 + critical 位清洗 + **序列号覆盖**（powerd 按序列号持久化 "Check Battery" 判决，换序列号强制重评估 → 状态转"正常"） |

## 目录说明

- `EFI/` — 完整 OpenCore EFI（**config.plist 的 SMBIOS 序列号/MLB/ROM/UUID 已脱敏，自用请用 GenSMBIOS 重新生成**）
- `tools/` — 排查工具链：HDA verb 探针（`hdaprobe.swift`/`amp.swift`）、ASL 编译器、电池/GPU 工具、Ubuntu 取证脚本
- `staging-cirrus-1107/` — 自编 CirrusAudioFixup / VoodooI2C kext
- `lbs253/` — IntelBluetoothFirmware v2.5.3（BlazarU 支持）
- `CHANGES-*.md` — 逐日变更记录

## 重要警告

- 本机 `boot-args` 含 `-cirrusnodsp`（无 DSP 扬声器保护），**播放请保持低音量**，直到嵌入 `17aa386e` DSP 调音
- 17AA386E 这块板（CS35L41 ×2, I2C3）的完整攻坚记录见 `CHANGES-2026-11-07.md` 系列与各上游仓库 issue

相关上游：[CirrusAudioFixup](https://github.com/hoaug-tran/CirrusAudioFixup) · [AppleALC](https://github.com/acidanthera/AppleALC) · [IntelBluetoothFirmware](https://github.com/lshbluesky/IntelBluetoothFirmware) · [NVRM driver](https://github.com/nullmoth/nvidia-macos-driver)
