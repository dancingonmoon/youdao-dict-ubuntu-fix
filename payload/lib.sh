#!/bin/bash
# 公共函数库 —— 被 install.sh / uninstall.sh / verify.sh 与 payload/*.sh 复用。
# 调用方需自行 `set -euo pipefail` 并 source 本文件。

# ---- 可覆盖的变量 ----
YD_DIR="${YD_DIR:-/usr/share/youdao-dict}"     # 有道词典安装目录
BAK_STAMP="${BAK_STAMP:-$(date +%Y%m%d)}"      # 备份后缀：<文件>.bak-<stamp>

# ---- 输出 ----
c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
c_info() { printf '    %s\n' "$*"; }
hdr()    { printf '\n\033[1m%s\033[0m\n' "$*"; }

die() { c_err "$*"; exit 1; }

# ---- 前置条件 ----
# 写权限检查：目标是系统目录（/usr/share/...）时需要 root；
# 若 YD_DIR 指向任意可写目录（例如自建的测试副本），则无需 root。
need_write_access() {
    [ -e "$YD_DIR" ] || die "目标目录不存在：$YD_DIR"
    if [ -w "$YD_DIR" ] && [ -w "$YD_DIR/dae/plugins.py" ]; then
        return 0
    fi
    [ "$(id -u)" = "0" ] || die "没有对 $YD_DIR 的写入权限。系统安装请用： sudo bash $0"
    return 0
}

need_installed() {
    [ -f "$YD_DIR/main.py" ] || die "找不到 $YD_DIR/main.py —— 请先安装有道词典（下载地址见 README）"
}

# 系统 python3：有道词典运行时用的就是它，所以补丁必须按它的版本判断
sys_python() {
    command -v python3 >/dev/null || die "找不到 python3"
    command -v python3
}

# python3 里某个 API 是否还在？ 在 → 0；已被删除 → 1
api_present() {   # api_present 'import imp'  /  'import inspect; inspect.getargspec'
    "$(sys_python)" -c "$1" 2>/dev/null
}

# ---- 备份 ----
# backup_once <file> -- 只备份一次；把备份路径打到 stdout，提示信息一律走 stderr。
# （务必如此：调用方用 $(...) 捕获路径，混入提示会让路径变成垃圾字符串。）
backup_once() {
    local f="$1" b="$1.bak-$BAK_STAMP"
    if [ -e "$b" ]; then
        c_info "备份已存在（复用）：$(basename "$b")" >&2
    else
        cp -a "$f" "$b" || die "备份失败：$f"
        c_info "已备份 → $(basename "$b")" >&2
    fi
    printf '%s' "$b"
}

# ---- 语法校验 ----
syntax_ok() {   # syntax_ok <pyfile>
    "$(sys_python)" -c 'import ast,sys
try:
    ast.parse(open(sys.argv[1], encoding="utf-8", errors="replace").read())
except SyntaxError as e:
    sys.stderr.write("SyntaxError: %s\n" % e); sys.exit(1)' "$1" 2>/dev/null
}

# 改完立刻校验，坏了就回滚。失败即 die。
commit_or_rollback() {   # commit_or_rollback <file> <backup>
    local f="$1" b="$2"
    if syntax_ok "$f"; then
        return 0
    fi
    c_err "语法校验失败，正在回滚：$(basename "$f")"
    cp -a "$b" "$f"
    die "已回滚，文件未被破坏。请把此情况反馈到项目 issue。"
}

# ---- 精确替换（结构改动用）----
# 从标准输入读 (file, old, new) 三个路径，要求 old 在 file 中恰好出现 1 次。
# 返回 0=已替换；3=未匹配；4=匹配到多处（两者都不改文件）。
replace_once() {   # replace_once <file> <old_file> <new_file>
    "$(sys_python)" - "$1" "$2" "$3" <<'PY'
import sys
f, oldf, newf = sys.argv[1], sys.argv[2], sys.argv[3]
s   = open(f,    encoding='utf-8').read()
old = open(oldf, encoding='utf-8').read()
new = open(newf, encoding='utf-8').read()
n = s.count(old)
if n == 0:
    sys.exit(3)
if n > 1:
    sys.stderr.write("匹配到 %d 处（应为 1 处）\n" % n)
    sys.exit(4)
open(f, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
}

# 供 patch 脚本使用：把一段文本写进临时文件（配合 replace_once）
tmp_write() {   # tmp_write <文件路径>  —— 内容从 stdin 读
    cat > "$1"
}
