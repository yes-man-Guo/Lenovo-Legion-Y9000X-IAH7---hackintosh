#!/bin/bash
# Y9000X 2022 IAH7 扬声器取证 — 在 Ubuntu 中以 sudo 运行
# 用法: sudo bash collect-ubuntu-audio.sh
# 产物: 桌面/y9000x-audio-forensics.txt + 桌面/dsdt.aml (+ dsdt.dsl 若已装 acpica-tools)
#       并自动复制到 ESP 的 /EFI/forensics/，回 macOS 后 ZCode 可直接读取。

# 桌面目录（兼容中文系统"桌面"）
desktop="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
mkdir -p "$desktop"

out="$desktop/y9000x-audio-forensics.txt"
{
echo "===== 采集时间: $(date) / 内核: $(uname -r) ====="

echo; echo "===== 1. cs35l41 / serial-multi / CSC3551 内核日志 ====="
dmesg | grep -iE "cs35l41|cirrus|serial.multi|CSC3551|17AA386E|CLSA"

echo; echo "===== 2. IRQ mismatch / genirq 相关 ====="
dmesg | grep -iE "genirq|flags mismatch" | head -20

echo; echo "===== 3. GPIO 消费者（关键：找 cs35l41-reset 占用了哪个 chip/line） ====="
[ -d /sys/kernel/debug/gpio ] || mount -t debugfs none /sys/kernel/debug 2>/dev/null
cat /sys/kernel/debug/gpio 2>/dev/null || echo "debugfs gpio 不可用"

echo; echo "===== 3b. pinctrl pinmux 转储（关键：pin 67=SNDW0_CLK/GPP_S0 的 mode 与实际电平） ====="
for d in /sys/kernel/debug/pinctrl/*/; do
    echo "-- $(basename "$d")"
    grep -E "pin 6[5-9]|pin 7[0-5]|SNDW|GPP_S" "$d/pinmux-pins" 2>/dev/null
    grep -E "^pin67 |^pin68 |SNDW0" "$d/pins" 2>/dev/null
done

echo; echo "===== 3c. SoundWire / 音频 DSP 控制器状态（GPP_S 组是 SNDW pad） ====="
lspci -d 8086: | grep -iE "sound|audio|hda|dsp" 
for sw in /sys/bus/soundwire/devices/*; do [ -e "$sw" ] && echo "soundwire device: $sw"; done 2>/dev/null
cat /sys/bus/platform/drivers/sof-audio-pci*/*/status 2>/dev/null | head -3

echo; echo "===== 4. I2C 总线列表（DesignWare 控制器编号） ====="
ls -l /dev/i2c-* 2>/dev/null || echo "无 /dev/i2c-*（需 i2c-dev 模块）"
for n in /sys/bus/i2c/devices/i2c-*/name; do echo "$n: $(cat $n)"; done 2>/dev/null

echo; echo "===== 5. HDA codec 概要 ====="
grep -iE "codec|cirrus|realtek|address" /proc/asound/card*/codec* 2>/dev/null | head -12

echo; echo "===== 6. cirrus 固件文件 ====="
ls -la /lib/firmware/cirrus/ 2>/dev/null | grep -i "17aa\|386e" | head

echo; echo "===== 7. 17AA386E 驱动绑定证据 ====="
grep -iE "17AA386E|Using extra _DSD|Adding DSD properties" /var/log/syslog 2>/dev/null | head -5
} > "$out" 2>&1

cp /sys/firmware/acpi/tables/DSDT "$desktop/dsdt.aml" 2>/dev/null && echo "DSDT 已导出到 $desktop/dsdt.aml"
command -v iasl >/dev/null 2>&1 && iasl -d "$desktop/dsdt.aml" >/dev/null 2>&1 && echo "DSDT 已反编译为 $desktop/dsdt.dsl" || echo "未装 iasl（可 sudo apt install acpica-tools 后运行: iasl -d dsdt.aml）"

esp=""
for m in /boot/efi /boot /efi; do [ -d "$m/EFI" ] && esp="$m" && break; done
if [ -n "$esp" ]; then
    mkdir -p "$esp/EFI/forensics"
    cp "$out" "$desktop/dsdt.aml" "$esp/EFI/forensics/" 2>/dev/null
    [ -f "$desktop/dsdt.dsl" ] && cp "$desktop/dsdt.dsl" "$esp/EFI/forensics/" 2>/dev/null
    echo "取证文件已复制到 ESP: $esp/EFI/forensics/"
else
    echo "未找到已挂载的 ESP — 请手动把桌面上的 y9000x-audio-forensics.txt 和 dsdt.aml 放进 ESP 的 EFI/forensics/"
fi
echo "完成。回 macOS 后对 ZCode 说「继续」。"
