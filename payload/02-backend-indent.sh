#!/bin/bash
# 补丁 02 —— 后端脚本第 37 行行首多了一个空格（包自带的笔误）
#
# 后果：youdao-dict-backend.py 直接 IndentationError → DBus 服务 com.youdao.backend
#       永远起不来 → 界面每次触碰后端都在 GUI 主线程同步阻塞约 5 秒，且每 5 秒重试一次。
#       表现为：顶部「词典/例句/百科/翻译」四个菜单点了没反应。
#
# 注意：与 Python 版本无关，任何系统上都是坏的。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

need_write_access
need_installed

hdr "补丁 02：后端脚本多余的缩进"

F="$YD_DIR/youdao-dict-backend.py"
[ -f "$F" ] || die "找不到 $F"

# 用精确字符串替换，不用正则（这一行的 . 和 ) 用 BRE 转义很容易踩坑）
BROKEN='     print("Youdao Backend Service is started...")'
FIXED='    print("Youdao Backend Service is started...")'

if ! grep -qxF "$BROKEN" "$F"; then
    c_ok "无需修改：没有发现多余缩进的那一行（已修过，或版本不同）"
    exit 0
fi

# 防呆：同文件里应另有正确缩进的那一行（原文第 44 行）。
# 数量必须是 1 —— 否则说明文件结构与我们预期不同。
n_fixed="$(grep -cxF "$FIXED" "$F" || true)"
[ "$n_fixed" = "1" ] \
    || die "预期内容不符：正确缩进的那一行有 $n_fixed 处（预期 1 处），已中止，未做任何改动"

OLD_F="$(mktemp)"; NEW_F="$(mktemp)"
trap 'rm -f "$OLD_F" "$NEW_F"' EXIT

tmp_write "$OLD_F" <<'EOF'
     print("Youdao Backend Service is started...")
EOF
tmp_write "$NEW_F" <<'EOF'
    print("Youdao Backend Service is started...")
EOF

BAK="$(backup_once "$F")"

rc=0
replace_once "$F" "$OLD_F" "$NEW_F" || rc=$?
case "$rc" in
    0) : ;;
    3) die "没找到那一行，文件未改动" ;;
    4) die "匹配到多处，为免误改已中止，文件未改动" ;;
    *) die "替换失败（退出码 $rc），文件未改动" ;;
esac

commit_or_rollback "$F" "$BAK"

# 校验：坏行消失，且正确缩进的版本应恰好 2 处（原第 37、44 行）
if grep -qxF "$BROKEN" "$F"; then
    die "修改后坏行仍在，请检查 $F"
fi
n_now="$(grep -cxF "$FIXED" "$F" || true)"
if [ "$n_now" = "2" ]; then
    c_ok "已修复：多出的缩进已删除（正确缩进的打印语句现有 2 处）"
    c_info "生效方式：退出并重新打开有道词典"
else
    c_warn "坏行已消失，但正确缩进的打印语句有 $n_now 处（预期 2 处）—— 文件可能与本脚本预期的版本不同，请手工确认"
fi
