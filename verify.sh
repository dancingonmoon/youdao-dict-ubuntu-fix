#!/bin/bash
# 有道词典 Ubuntu 兼容修复 —— 体检
#
#   用法： bash verify.sh          （只读，不需要 root）
#
# 逐项检查四个补丁是否已生效，并给出环境信息。全部通过时退出码为 0。
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=payload/lib.sh
source "$HERE/payload/lib.sh"

# 本脚本只读，不要求 root；lib.sh 里只用到输出与 sys_python
pass=0; fail=0; skip=0

row() {   # row <名称> <状态符号> <说明>
    printf '  %-42s %b %s\n' "$1" "$2" "$3"
}
ok()   { row "$1" '\033[32m✓\033[0m' "$2"; pass=$((pass+1)); }
bad()  { row "$1" '\033[31m✗\033[0m' "$2"; fail=$((fail+1)); }
n_a()  { row "$1" '\033[90m—\033[0m' "$2"; skip=$((skip+1)); }

PY="$(sys_python 2>/dev/null || true)"

hdr "环境"
[ -n "$PY" ] && c_info "python3      : $PY（$("$PY" -V 2>&1)）" || c_err "找不到 python3"
if [ -f "$YD_DIR/main.py" ]; then
    c_info "安装目录     : $YD_DIR"
else
    c_err "安装目录     : 未找到 $YD_DIR/main.py"
    echo; c_err "有道词典似乎没有安装。"; exit 1
fi

hdr "补丁状态"

# ── 01a dae/plugins.py（imp）──────────────────────────────────
F="$YD_DIR/dae/plugins.py"
if [ ! -f "$F" ]; then
    n_a "01a dae/plugins.py (imp)" "文件不存在"
elif grep -q '_load_source' "$F" && grep -q '^import importlib.util' "$F"; then
    ok "01a dae/plugins.py (imp)" "已修（改用 importlib）"
elif api_present 'import imp'; then
    n_a "01a dae/plugins.py (imp)" "当前 Python 仍有 imp，无需修"
else
    bad "01a dae/plugins.py (imp)" "未修 —— 应用会启动即崩"
fi

# ── 01b pyquery.py（getargspec）───────────────────────────────
F="$YD_DIR/app/plugins/youdao/pyquery/pyquery.py"
if [ ! -f "$F" ]; then
    n_a "01b pyquery.py (getargspec)" "文件不存在"
elif ! grep -q 'inspect\.getargspec(' "$F"; then
    ok "01b pyquery.py (getargspec)" "已修（getfullargspec）"
elif api_present 'import inspect; inspect.getargspec'; then
    n_a "01b pyquery.py (getargspec)" "当前 Python 仍有 getargspec，无需修"
else
    bad "01b pyquery.py (getargspec)" "未修 —— 插件加载会失败（界面成空壳）"
fi

# ── 01c/01d 两个 utils.py（collections.Mapping）───────────────
for rel in app/plugins/youdao/utils.py backend/utils.py; do
    F="$YD_DIR/$rel"
    tag="01c $rel"
    [ "$rel" = "backend/utils.py" ] && tag="01d $rel"
    if [ ! -f "$F" ]; then
        n_a "$tag (collections.Mapping)" "文件不存在"
    elif ! grep -q 'collections\.Mapping' "$F"; then
        ok "$tag (collections.Mapping)" "已修（collections.abc.Mapping）"
    elif api_present 'import collections; collections.Mapping'; then
        n_a "$tag (collections.Mapping)" "当前 Python 仍有该属性，无需修"
    else
        bad "$tag (collections.Mapping)" "未修 —— 运行期一旦触发即报错"
    fi
done

# ── 02 后端脚本缩进 ───────────────────────────────────────────
F="$YD_DIR/youdao-dict-backend.py"
if [ ! -f "$F" ]; then
    n_a "02 youdao-dict-backend.py" "文件不存在"
elif grep -qxF '     print("Youdao Backend Service is started...")' "$F"; then
    bad "02 youdao-dict-backend.py" "未修（第 37 行仍多一个空格）—— 四个菜单点了没反应"
else
    ok "02 youdao-dict-backend.py" "已修（缩进正常）"
fi

# ── 03 桌面文件名 ─────────────────────────────────────────────
F="$YD_DIR/dae/daeclient.py"
if [ ! -f "$F" ]; then
    n_a "03 dae/daeclient.py" "文件不存在"
elif grep -q "setDesktopFileName('youdao-dict')" "$F"; then
    ok "03 dae/daeclient.py" "已修（app_id = youdao-dict）"
else
    bad "03 dae/daeclient.py" "未修 —— dock 上会多一个 python3 齿轮图标"
fi

# ── 04 托盘 setVisible 槽签名 ─────────────────────────────────
F="$YD_DIR/dae/window.py"
if [ ! -f "$F" ]; then
    n_a "04 dae/window.py (setVisible)" "文件不存在"
elif grep -A2 '设置窗口可见状态' "$F" | grep -q '@pyqtSlot(bool)'; then
    ok "04 dae/window.py (setVisible)" "已修（@pyqtSlot(bool)）"
else
    bad "04 dae/window.py (setVisible)" "未修 —— 托盘图标点了没反应"
fi

# ── 备份情况 ─────────────────────────────────────────────────
n_bak="$(find "$YD_DIR" -name '*.bak-*' -type f 2>/dev/null | wc -l)"
hdr "备份"
c_info "找到 $n_bak 个 *.bak-* 备份（uninstall.sh 靠它们还原）"

# ── 汇总 ─────────────────────────────────────────────────────
hdr "结果"
printf '  \033[32m通过 %d\033[0m    \033[31m失败 %d\033[0m    不适用 %d\n' "$pass" "$fail" "$skip"
echo

if [ "$fail" -gt 0 ]; then
    c_err "有 $fail 项未修复。请运行： sudo bash $HERE/install.sh"
    exit 1
fi

c_ok "所有适用的补丁都已生效"
c_info "若界面仍有问题，记得【完全退出并重新打开】有道词典（补丁需要重启应用才生效）。"
exit 0
