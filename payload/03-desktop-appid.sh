#!/bin/bash
# 补丁 03 —— 补上 setDesktopFileName，让 GNOME 能认出这个窗口属于有道词典
#
# 症状：左侧 dock 里除了词典图标，还多出一个名叫 "python3" 的齿轮图标。
# 根因：程序只设了 setApplicationName，没设 setDesktopFileName；
#       Qt5 在 Wayland 下会用【进程名】当窗口的 xdg app_id，
#       于是窗口上报 set_app_id("python3")，GNOME 找不到 python3.desktop，
#       只能给一个通用齿轮图标。
# 修法：显式声明 desktop file 名，与 /usr/share/applications/youdao-dict.desktop 对齐。
#
# 生效方式：完全退出并重开有道词典（GNOME 在窗口建立时才判定归属）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

need_write_access
need_installed

hdr "补丁 03：窗口的桌面文件名（dock 上的 python3 齿轮图标）"

F="$YD_DIR/dae/daeclient.py"
[ -f "$F" ] || die "找不到 $F"

if grep -q 'setDesktopFileName' "$F"; then
    c_ok "无需修改：已经是修复状态"
    exit 0
fi

ANCHOR='        app = QApplication(sys.argv)'
grep -qxF "$ANCHOR" "$F" \
    || die "预期内容不符：找不到「$ANCHOR」，已中止，未做任何改动"

OLD_F="$(mktemp)"; NEW_F="$(mktemp)"
trap 'rm -f "$OLD_F" "$NEW_F"' EXIT

tmp_write "$OLD_F" <<'EOF'
        app = QApplication(sys.argv)
EOF
tmp_write "$NEW_F" <<'EOF'
        app = QApplication(sys.argv)
        app.setDesktopFileName('youdao-dict')
EOF

BAK="$(backup_once "$F")"

if ! replace_once "$F" "$OLD_F" "$NEW_F"; then
    die "替换失败（没找到锚点，或匹配到多处），文件未改动"
fi

commit_or_rollback "$F" "$BAK"
c_ok "已修复：QApplication 之后新增 app.setDesktopFileName('youdao-dict')"
c_info "生效方式：完全退出有道词典后再重新打开（退出走窗口左下角「开始」→ 退出）"
