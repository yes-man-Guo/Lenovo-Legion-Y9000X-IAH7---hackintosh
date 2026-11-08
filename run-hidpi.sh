#!/bin/bash
# 一键生成内屏 HiDPI 覆盖（one-key-hidpi 机制，非交互）
# 分辨率档位：中间层 1920x1200 / 1680x1050 / 1440x900（16:10 面板）
# 脚本来源: https://github.com/xzhih/one-key-hidpi (jsdelivr 镜像下载至 /tmp/hidpi.sh)
printf '1\n6\n7\n1920x1200 1680x1050 1440x900\n' | bash /tmp/hidpi.sh
echo "=== 生成结果 ==="
find /Library/Displays -type f -exec ls -la {} \;
