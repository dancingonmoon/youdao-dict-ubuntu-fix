#!/bin/bash
# 有道词典 Linux 版 —— Ubuntu 现代版本兼容修复（安装入口）
#
#   用法： sudo bash install.sh
#
# 做四件事（每件都可单独运行 payload/ 下对应的脚本）：
#   01 修 Python 3.12 已删除的三处 API      → 解决「启动即崩 / 弹系统出错」
#   02 修后端脚本多出的一个空格            → 解决「四个菜单点了没反应」
#   03 补 setDesktopFileName               → 解决「dock 上多一个 python3 齿轮」
#   04 修 setVisible 槽签名                → 解决「托盘图标点了没反应」
#
# 只会就地修改 /usr/share/youdao-dict/ 下的 7 个文件，改前自动备份为 *.bak-<日期>，
# 每步改完都做语法校验，失败自动回滚。卸载见 uninstall.sh。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=payload/lib.sh
source "$HERE/payload/lib.sh"

VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo '?')"

printf '\n\033[1m有道词典 Ubuntu 兼容修复 v%s\033[0m\n' "$VERSION"
printf '安装目录：%s\n' "$YD_DIR"

need_write_access
need_installed

# ── 提示：先退出正在运行的有道词典 ────────────────────────────
if pgrep -f 'youdao-dict' >/dev/null 2>&1; then
    hdr "提示：检测到有道词典正在运行"
    c_warn "补丁改的是磁盘上的文件，运行中的进程不会变；而且改完必须重启应用才生效。"
    c_info "建议先退出：窗口左下角「开始」→ 退出（或 pkill -f youdao-dict）"
    echo
fi

# ── 依次执行四个补丁 ──────────────────────────────────────────
for p in 01-py312-compat 02-backend-indent 03-desktop-appid 04-tray-setvisible; do
    S="$HERE/payload/$p.sh"
    [ -f "$S" ] || die "缺少补丁脚本：$S"
    bash "$S"
done

# ── 自检 ──────────────────────────────────────────────────────
bash "$HERE/verify.sh"

# ── 收尾 ──────────────────────────────────────────────────────
hdr "下一步"
c_info "1) 完全退出有道词典，再重新打开（三个补丁都要重启才生效）"
c_info "2) 退出方式：窗口左下角「开始」→ 退出"
c_info "3) 确认四个菜单、托盘图标都能用了"
echo
c_info "如需还原：sudo bash $HERE/uninstall.sh"
