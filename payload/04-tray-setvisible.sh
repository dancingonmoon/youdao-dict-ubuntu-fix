#!/bin/bash
# 补丁 04 —— 托盘的 setVisible 槽签名写错（托盘图标点了没反应）
#
# 症状：顶栏托盘小图标左键、右键都没反应（窗口既不显示也不隐藏）。
# 根因：dae/window.py 里 setVisible 的装饰器被写成了 isVisible 的：
#           @pyqtSlot(result = bool)          ← 声明成「无参数、返回 bool」
#           def setVisible(self, visible):    ← 但方法需要一个参数
#       于是 JS 端 app.setVisible(true) 传参调用时，PyQt 抛
#           TypeError: setVisible() missing 1 required positional argument: 'visible'
#       而 JS 侧看不到这个异常 —— 静默失败，界面上什么都不发生。
# 修法：改回 @pyqtSlot(bool)。（同文件里的 isVisible 用 @pyqtSlot(result=bool) 是对的，别动。）
#
# 生效方式：完全退出并重开有道词典。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

need_write_access
need_installed

hdr "补丁 04：托盘图标的 setVisible 槽签名"

F="$YD_DIR/dae/window.py"
[ -f "$F" ] || die "找不到 $F"

OLD_F="$(mktemp)"; NEW_F="$(mktemp)"
trap 'rm -f "$OLD_F" "$NEW_F"' EXIT

tmp_write "$OLD_F" <<'EOF'
    # 设置窗口可见状态
    @pyqtSlot(result = bool)
    def setVisible(self, visible):
EOF
tmp_write "$NEW_F" <<'EOF'
    # 设置窗口可见状态
    @pyqtSlot(bool)
    def setVisible(self, visible):
EOF

# 幂等：已经是正确签名就跳过
# 注意：第一个 grep 不能加 -q —— -q 会抑制输出，管道里的第二个 grep 就永远匹配不到。
if grep -A2 '设置窗口可见状态' "$F" | grep -q '@pyqtSlot(bool)'; then
    c_ok "无需修改：已经是修复状态"
    exit 0
fi

BAK="$(backup_once "$F")"

rc=0
replace_once "$F" "$OLD_F" "$NEW_F" || rc=$?
case "$rc" in
    0) : ;;
    3) die "预期内容不符：没找到那段「设置窗口可见状态 + @pyqtSlot(result = bool) + def setVisible」——
      文件可能与本脚本预期的版本不同，已中止，未做任何改动" ;;
    4) die "匹配到多处，为避免误改已中止，未做任何改动" ;;
    *) die "替换失败（退出码 $rc），文件未改动" ;;
esac

commit_or_rollback "$F" "$BAK"
c_ok "已修复：setVisible 的装饰器改为 @pyqtSlot(bool)"
c_info "生效方式：完全退出有道词典后再重新打开"
