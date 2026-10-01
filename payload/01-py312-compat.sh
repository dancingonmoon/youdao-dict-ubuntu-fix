#!/bin/bash
# 补丁 01 —— 新版 Python 删掉的三处 API（应用启动即崩的根因）
#
#   imp                    Python 3.12 删除（PEP 594）
#   inspect.getargspec     Python 3.11 删除
#   collections.Mapping    Python 3.10 起移出到 collections.abc
#
# 三处**按实际解释器能力**逐项判断：API 还在就跳过，已被删才改。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

need_write_access
need_installed

hdr "补丁 01：Python 新版本已删除的 API"
c_info "解释器：$(sys_python) → $("$(sys_python)" -V 2>&1)"
echo

applied=0 skipped=0

# ─────────────────────────────────────────────────────────────
# 1a) dae/plugins.py —— imp.load_source（Python 3.12 删除）
# ─────────────────────────────────────────────────────────────
F="$YD_DIR/dae/plugins.py"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif grep -q '_load_source' "$F"; then
    c_ok "dae/plugins.py：已是修复状态，跳过"
    skipped=$((skipped+1))
elif api_present 'import imp'; then
    c_ok "dae/plugins.py：当前 Python 仍有 imp 模块，无需修改"
    skipped=$((skipped+1))
else
    c_info "dae/plugins.py：需要修复（本机 Python 无 imp 模块）"
    grep -qx 'import imp' "$F"  || die "预期内容不符（找不到独立成行的 import imp），已中止，未做任何改动"
    grep -q  'imp\.load_source(' "$F" || die "预期内容不符（找不到 imp.load_source 调用），已中止，未做任何改动"

    BAK="$(backup_once "$F")"
    sed -i 's/^import imp$/import importlib.util/' "$F"
    sed -i 's/imp\.load_source(/_load_source(/'   "$F"
    cat >> "$F" <<'PYEOF'

def _load_source(name, pathname):
    """imp.load_source() 的 importlib 等价实现。

    Python 3.12 起标准库移除了 imp 模块（PEP 594），故改用 importlib。
    """
    spec = importlib.util.spec_from_file_location(name, pathname)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module
PYEOF
    commit_or_rollback "$F" "$BAK"
    c_ok "dae/plugins.py：已改用 importlib"
    applied=$((applied+1))
fi

# ─────────────────────────────────────────────────────────────
# 1b) pyquery.py —— inspect.getargspec（Python 3.11 删除），共 2 处
# ─────────────────────────────────────────────────────────────
F="$YD_DIR/app/plugins/youdao/pyquery/pyquery.py"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif ! grep -q 'inspect\.getargspec(' "$F"; then
    c_ok "pyquery.py：无需修改（已修或本就没有该调用）"
    skipped=$((skipped+1))
elif api_present 'import inspect; inspect.getargspec'; then
    c_ok "pyquery.py：当前 Python 仍有 getargspec，无需修改"
    skipped=$((skipped+1))
else
    n="$(grep -c 'inspect\.getargspec(' "$F")"
    c_info "pyquery.py：需要修复（$n 处 getargspec）"
    BAK="$(backup_once "$F")"
    sed -i 's/inspect\.getargspec(/inspect.getfullargspec(/g' "$F"
    commit_or_rollback "$F" "$BAK"
    c_ok "pyquery.py：getargspec → getfullargspec（$n 处）"
    applied=$((applied+1))
fi

# ─────────────────────────────────────────────────────────────
# 1c) 两个 utils.py —— collections.Mapping（3.10 起移入 collections.abc）
# ─────────────────────────────────────────────────────────────
for F in "$YD_DIR/app/plugins/youdao/utils.py" "$YD_DIR/backend/utils.py"; do
    name="${F#$YD_DIR/}"
    if [ ! -f "$F" ]; then
        c_warn "跳过：找不到 $name"
    elif ! grep -q 'collections\.Mapping' "$F"; then
        c_ok "$name：无需修改"
        skipped=$((skipped+1))
    elif api_present 'import collections; collections.Mapping'; then
        c_ok "$name：当前 Python 仍有 collections.Mapping，无需修改"
        skipped=$((skipped+1))
    else
        c_info "$name：需要修复"
        grep -qx 'import collections' "$F" \
            || die "$name 预期内容不符（找不到独立成行的 import collections），已中止"
        BAK="$(backup_once "$F")"
        sed -i 's/^import collections$/import collections.abc/' "$F"
        sed -i 's/collections\.Mapping/collections.abc.Mapping/g'  "$F"
        commit_or_rollback "$F" "$BAK"
        c_ok "$name：collections.Mapping → collections.abc.Mapping"
        applied=$((applied+1))
    fi
done

echo
if [ "$applied" -eq 0 ]; then
    c_ok "补丁 01：无需改动（已修 ${skipped} 项）"
else
    c_ok "补丁 01：完成（改动 ${applied} 项，跳过 ${skipped} 项）"
fi
