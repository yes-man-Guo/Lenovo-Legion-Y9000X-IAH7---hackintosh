#!/usr/bin/env bash
# ============================================================
#  Y9000X (2022 IAH7) 内建麦克风取证 — Ubuntu 侧
#  目的: 终验麦克风阵列接在 ALC287 codec 还是 PCH DMIC (Intel SST/SOF)
#  用法: sudo bash collect-ubuntu-mic.sh
#  产物: 桌面 y9000x-mic-verdict.txt + mic-test-*.wav (每段录完自动回放)
#        并自动回拷到 EFI 分区 /EFI/mic-forensics/ 供 macOS 读取
# ============================================================
set +e
[ "$EUID" -ne 0 ] && { echo "请用 sudo 运行: sudo bash $0"; exit 1; }

REAL_USER="${SUDO_USER:-$USER}"
UID_R="$(id -u "$REAL_USER" 2>/dev/null || echo 1000)"

DESK="$(sudo -u "$REAL_USER" xdg-user-dir DESKTOP 2>/dev/null)"
[ -z "$DESK" ] && DESK="$(getent passwd "$REAL_USER" | cut -d: -f6)/Desktop"
[ ! -d "$DESK" ] && DESK="/home/$REAL_USER/Desktop"
mkdir -p "$DESK"

R="$DESK/y9000x-mic-verdict.txt"
: > "$R"

log() { echo "$@" | tee -a "$R"; }
sec() { log ""; log "============================================================"; log "== $1"; log "============================================================"; }

sec "0. 机器与时间"
log "时间: $(date '+%F %T')"
log "内核: $(uname -r)"
log "机型: $(cat /sys/class/dmi/id/product_name 2>/dev/null)"

sec "1. 声卡总览"
log "-- /proc/asound/cards --"
cat /proc/asound/cards >> "$R" 2>&1
log "-- /proc/asound/pcm --"
cat /proc/asound/pcm >> "$R" 2>&1
log "-- arecord -l (录音设备) --"
arecord -l >> "$R" 2>&1

sec "2. PulseAudio/PipeWire 输入源"
XDG_RUNTIME_DIR="/run/user/$UID_R" sudo -u "$REAL_USER" pactl list short sources >> "$R" 2>&1 || log "(pactl 不可用)"

sec "3. 内核消息 (sof/dmic/snd_hda/sst)"
{ journalctl -b -k --no-pager 2>/dev/null | grep -iE "sof|dmic|snd_hda|skl|sst"; dmesg 2>/dev/null | grep -iE "sof|dmic|snd_hda|skl|sst"; } | sort -u >> "$R" 2>&1

sec "4. SOF 相关模块与固件"
log "-- lsmod (sof/sst/snd_hda) --"
lsmod | grep -E "sof|sst|snd_hda" >> "$R" 2>&1
log "-- /lib/firmware/intel/sof* --"
ls -d /lib/firmware/intel/sof* >> "$R" 2>&1 || log "(无 SOF 固件目录 —— 若无 sof 声卡先查这里)"

sec "5. 内核启动参数"
cat /proc/cmdline >> "$R" 2>&1

sec "6. codec 转储 (完整)"
for f in /proc/asound/card*/codec#*; do
  log "--- $f ---"
  cat "$f" >> "$R" 2>&1
done

sec "7. 录音回放实测 (每个录音设备 6 秒, 录完自动回放)"
log "听到倒计时提示后, 请持续正常说话 (离屏幕 30-50cm)。"
DEVS=$(arecord -l 2>/dev/null | sed -n 's/^card \([0-9]*\): .*, device \([0-9]*\): .*/\1 \2/p')
if [ -z "$DEVS" ]; then
  log "!! 没有发现任何录音设备 —— 若确无 sof 声卡, 指向 PCH DMIC 未被驱动或无录音硬件"
fi
echo "$DEVS" | while read -r c d; do
  [ -z "$c" ] && continue
  name=$(arecord -l 2>/dev/null | grep "^card $c:" | head -1)
  log ""
  log ">>> 设备 hw:$c,$d  ($name)"
  f="$DESK/mic-test-card$c-dev$d.wav"
  log "    3 秒后开始录音 6 秒, 请开始说话..."
  sleep 3
  ok=0
  for opts in "-f S16_LE -r 48000 -c 2" "-f S16_LE -r 16000 -c 4" "-f S16_LE -r 16000 -c 1"; do
    if arecord -D "hw:$c,$d" $opts -d 6 "$f" >> "$R" 2>&1; then
      ok=1; log "    录音成功 ($opts) -> $(basename "$f")"
      break
    fi
  done
  if [ "$ok" = "1" ]; then
    log "    3 秒后自动回放, 请仔细听有没有自己的人声..."
    sleep 3
    aplay "$f" >> "$R" 2>&1 && log "    回放完成" || log "    回放失败 (报告里看错误)"
  else
    log "    !! 该设备录音失败 (格式不支持/权限/无信号源), 细节见报告尾部错误"
  fi
done
chown "$REAL_USER" "$DESK"/mic-test-*.wav 2>/dev/null

sec "8. 判读指南"
log "A. 出现 sof-xxx 声卡且其录音设备实测录到人声:"
log "   => 阵列在 PCH DMIC (Intel SST/SOF)。macOS 无驱动, 硬件级死路终审成立。"
log "B. 只有 HDA Intel PCH 卡 (ALC287), 但某个录音设备录到人声:"
log "   => 阵列竟在 codec 上! 带报告回 macOS 继续修 (概率很低)。"
log "C. 完全没有录音设备:"
log "   => Ubuntu 也驱动不了 —— 先查第 4 节 SOF 固件是否安装; 若固件齐全仍无 sof 卡,"
log "      说明本机 DMIC 通道 BIOS 层面就没启用 (或阵列确实在别处), 同样是 macOS 无解。"

log ""
log "报告: $R"
log "录音: $DESK/mic-test-*.wav"

sec "9. 回拷 EFI 分区 (回 macOS 后从 /Volumes/EFI/EFI/mic-forensics/ 读取)"
mounted=""
mkdir -p /mnt/efi
for dev in /dev/nvme0n1p1 /dev/nvme1n1p1; do
  if [ -b "$dev" ] && mount -t vfat "$dev" /mnt/efi 2>>"$R"; then mounted="$dev"; break; fi
done
if [ -n "$mounted" ]; then
  mkdir -p /mnt/efi/EFI/mic-forensics
  cp "$R" /mnt/efi/EFI/mic-forensics/ 2>>"$R"
  cp "$DESK"/mic-test-*.wav /mnt/efi/EFI/mic-forensics/ 2>>"$R"
  log "已拷回 EFI ($mounted) -> /EFI/mic-forensics/"
  umount /mnt/efi
else
  log "!! EFI 自动挂载失败, 请手动执行 (分区名以 'lsblk -f' 里 ~200MB vfat 的 EFI 分区为准):"
  log "   sudo mount /dev/nvme0n1p1 /mnt/efi"
  log "   sudo mkdir -p /mnt/efi/EFI/mic-forensics"
  log "   sudo cp $R $DESK/mic-test-*.wav /mnt/efi/EFI/mic-forensics/"
  log "   sudo umount /mnt/efi"
fi

echo ""
echo "完成。报告: $R"
