#!/bin/bash
# 有道词典 Ubuntu 兼容修复 —— 还原
#
#   用法： sudo bash uninstall.sh
#
# 把 install.sh 改过的 12 个文件从 *.bak-* 备份还原回官方原版。
# 注意：还原后应用会恢复「启动即崩」的原始状态（这正是还原的意义）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=payload/lib.sh
source "$HERE/payload/lib.sh"

need_write_access
need_installed

hdr "还原为官方原版"

# install.sh 可能改动的 12 个文件
FILES=(
    "dae/plugins.py"
    "app/plugins/youdao/pyquery/pyquery.py"
    "app/plugins/youdao/utils.py"
    "backend/utils.py"
    "youdao-dict-backend.py"
    "dae/daeclient.py"
    "dae/window.py"
    "dae/xutils.py"
    "dae/shadowwindow.py"
    "app/plugins/youdao/window.py"
    "app/plugins/youdao/qml/DragableArea.qml"
)

if pgrep -f 'youdao-dict' >/dev/null 2>&1; then
    c_warn "有道词典正在运行，建议先退出再还原"
fi

restored=0 absent=0
for rel in "${FILES[@]}"; do
    F="$YD_DIR/$rel"
    [ -f "$F" ] || { c_warn "跳过（文件不存在）：$rel"; continue; }

    # 找该文件最新的一个 .bak-* 备份
    B="$(ls -1t "$F".bak-* 2>/dev/null | head -n1 || true)"
    if [ -z "$B" ]; then
        c_warn "无备份，跳过：$rel"
        absent=$((absent+1))
        continue
    fi
    cp -a "$B" "$F"
    c_ok "已还原：$rel  ← $(basename "$B")"
    restored=$((restored+1))
done

echo
if [ "$restored" -gt 0 ]; then
    c_ok "完成：还原 $restored 个文件"
else
    c_warn "没有还原任何文件（可能本来就没打过补丁，或备份已被清理）"
fi

if [ "$absent" -gt 0 ]; then
    hdr "有 $absent 个文件没有备份"
    c_info "兜底办法：用官方 deb 重装一遍，效果等同于还原："
    c_info "  sudo apt install --reinstall ./youdao-dict_6.0.0-ubuntu-amd64.deb"
fi

c_info "说明：不清理 __pycache__。Python 按源文件的 mtime+大小校验缓存，"
c_info "      还原后旧缓存自动失效，删掉它反而会让 dpkg -V 报一堆 missing。"
