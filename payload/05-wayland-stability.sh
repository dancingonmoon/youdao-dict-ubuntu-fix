#!/bin/bash
# 补丁 05 —— Wayland 下启动即崩溃（BadWindow → Qt5WebKit 段错误）与窗口缩放
#
# 症状：
#   在 GNOME Wayland 会话里，有道词典偶尔（常是启动后第一下交互时）整个进程消失；
#   /var/crash 出现 _usr_share_youdao-dict_main.py.*.crash（Signal: 11 SIGSEGV），
#   journalctl 里紧挨着能看到：
#       <class 'Xlib.error.BadWindow'>: code = 3 ... major_opcode = 18
#       python3[pid]: segfault at ... in libQt5WebKit.so.5
#
# 根因：
#   dae/shadowwindow.py 的 setShadowWidth() 在 __init__ 里（窗口尚未映射）就取
#   int(self.winId())，再用 python-xlib 直接往这个窗口写 DEEPIN_WINDOW_SHADOW；
#   GNOME Wayland 会话里 Qt 没有创建 X 窗口，WM 回 BadWindow，异常从事件回调里
#   逸出，正好和第一次 WebKit 绘制相撞 → 段错误。
#
#   另外主窗口是 QQuickView（QWindow，没有 move()/setX()/setY()）：QML 用
#   mainView.setX/setY 摆位置、dae/window.py 的拖拽缩放又走 Xlib set_geometry，
#   在 Wayland 下两处都在悄悄失败，于是窗口挪不动、缩放不跟手。
#
# 修法（只改逻辑，不改界面）：
#   dae/xutils.py                 X 错误只忽略 BadWindow；新增 is_x_client_window()
#   dae/shadowwindow.py           阴影属性延到下一轮事件循环再写
#   dae/window.py                 getXWindow() 拿不到真窗口返回 None；缩放改走 Qt
#   app/plugins/youdao/window.py  QQuickView 上补 x/y/move/resize，主窗口不再跑偏
#   qml/DragableArea.qml          拖动优先请系统代为移动（不支持时行为不变）
#
# 已知限制：GNOME Wayland 不支持客户端定位窗口，Qt 5.15 的 startSystemMove()
#   在这种合成器上返回 false，所以【鼠标拖动窗口仍然无效】；窗口缩放正常。
#   需要拖动请让有道单独走 X11，见 docs/TROUBLESHOOTING.md「已知限制 5」。
#
# 生效方式：完全退出并重开有道词典。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

need_write_access
need_installed

hdr "补丁 05：Wayland 崩溃与窗口缩放"

PY="$(sys_python)"
changed=0
already=0

run_py() {   # run_py <file> <<'PY' ... PY  —— 出错时回滚到 $BAK 并 die
    local file="$1"
    if ! "$PY" - "$file"; then
        cp -a "$BAK" "$F"
        die "改写失败，已回滚：$(basename "$F")"
    fi
}

# ── 5a) dae/xutils.py ─────────────────────────────────────────
F="$YD_DIR/dae/xutils.py"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif grep -q '_on_x_error' "$F"; then
    c_ok "dae/xutils.py：已是修复状态，跳过"; already=$((already+1))
else
    grep -qx 'import Xlib.X' "$F" || die "预期内容不符（找不到 import Xlib.X），已中止，未做改动"
    grep -qx 'ewmh = EWMH()' "$F" || die "预期内容不符（找不到 ewmh = EWMH()），已中止，未做改动"
    BAK="$(backup_once "$F")"
    run_py "$F" <<'PY'
import sys
GUARD = '# In a Wayland session Qt renders through Wayland and the process is not an X\n# client. Writing properties on a window Qt never created makes the WM reply\n# BadWindow; that error used to escape from setShadowWidth() while the first\n# WebKit frame was being painted. Ignore only BadWindow.\ndef _on_x_error(err, request):\n    if isinstance(err, xerror.BadWindow):\n        print("xutils: ignoring BadWindow (not an X client window)", file=sys.stderr)\n    else:\n        print("xutils: X error %r" % (err,), file=sys.stderr)\n\newmh.display.set_error_handler(_on_x_error)\n\ndef is_x_client_window(xwin):\n    """False when we are not really an X client (Wayland session, no XID)."""\n    if xwin is None or not getattr(xwin, "id", 0):\n        return False\n    try:\n        xwin.get_attributes()\n        ewmh.display.sync()\n        return True\n    except (xerror.BadWindow, xerror.ConnectionClosedError):\n        return False'
f = sys.argv[1]
s = open(f, encoding='utf-8').read()
old = "import Xlib.X\nfrom dae.ewmh import EWMH\newmh = EWMH()\n"
assert s.count(old) == 1, "import block not found exactly once"
new = ("import sys\n\nimport Xlib.X\nfrom Xlib import error as xerror\n"
       "from dae.ewmh import EWMH\newmh = EWMH()\n\n" + GUARD + "\n")
s = s.replace(old, new, 1)
for fn in ("show_shadow", "hide_shadow"):
    i = s.index("def %s(xwin" % fn)
    j = s.index("    ewmh.setXWindowProperty(xwin,", i)
    s = s[:j] + "    if not is_x_client_window(xwin):\n        return\n" + s[j:]
open(f, 'w', encoding='utf-8').write(s)

PY
    commit_or_rollback "$F" "$BAK"
    grep -q 'is_x_client_window(xwin):' "$F" || die "改写后校验失败：is_x_client_window 未插入"
    c_ok "dae/xutils.py：写 X 属性前先确认窗口存在"; changed=$((changed+1))
fi

# ── 5b) dae/shadowwindow.py ───────────────────────────────────
F="$YD_DIR/dae/shadowwindow.py"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif grep -q '_defer_shadow' "$F"; then
    c_ok "dae/shadowwindow.py：已是修复状态，跳过"; already=$((already+1))
else
    grep -qF 'xutils.show_shadow(xutils.get_xwindow(int(self.winId())), str(width))' "$F" \
        || die "预期内容不符（找不到 setShadowWidth 里的 show_shadow 调用），已中止，未做改动"
    BAK="$(backup_once "$F")"
    run_py "$F" <<'PY'
import sys
SW_BLOCK = '    def _defer_shadow(self, width):\n        # setShadowWidth() runs from __init__, before the window is mapped; do\n        # the Xlib round-trip on the next event-loop pass instead.\n        QtCore.QTimer.singleShot(0, lambda: self._apply_shadow(width))\n\n    def _apply_shadow(self, width):\n        try:\n            win_id = int(self.winId())\n        except RuntimeError:  # C++ widget already deleted\n            return\n        if not win_id:\n            return\n        xutils.show_shadow(xutils.get_xwindow(win_id), str(width))'
f = sys.argv[1]
s = open(f, encoding='utf-8').read()
tail = "        xutils.show_shadow(xutils.get_xwindow(int(self.winId())), str(width))\n"
assert s.count(tail) == 1
s = s.replace(tail, "        self._defer_shadow(width)\n", 1)
anchor = "    @pyqtSlot(result = int)\n    def getShadowWidth(self):"
assert s.count(anchor) == 1
s = s.replace(anchor, SW_BLOCK + "\n\n" + anchor, 1)
open(f, 'w', encoding='utf-8').write(s)

PY
    commit_or_rollback "$F" "$BAK"
    c_ok "dae/shadowwindow.py：阴影属性改在窗口映射后再写"; changed=$((changed+1))
fi

# ── 5c) dae/window.py ─────────────────────────────────────────
F="$YD_DIR/dae/window.py"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif grep -q 'return xwin if xutils.is_x_client_window(xwin) else None' "$F"; then
    c_ok "dae/window.py：已是修复状态，跳过"; already=$((already+1))
else
    grep -q '    def getXWindow(self):' "$F" || die "预期内容不符（找不到 getXWindow），已中止，未做改动"
    grep -qF 'xutils.set_geometry(self.getXWindow(), x, y, width, height)' "$F" \
        || die "预期内容不符（找不到拖动处的 set_geometry 调用），已中止，未做改动"
    BAK="$(backup_once "$F")"
    run_py "$F" <<'PY'
import sys
GETX = '    def getXWindow(self):\n        # Before the window is realised winId() is not a real X window; in a\n        # Wayland session it is not an XID at all. Callers treat None as "no\n        # X window" instead of sending BadWindow requests.\n        try:\n            win_id = int(self.winId())\n        except RuntimeError:\n            return None\n        if not win_id:\n            return None\n        xwin = xutils.get_xwindow(win_id)\n        return xwin if xutils.is_x_client_window(xwin) else None'
DRAG = '            xwin = self.getXWindow()\n            if xwin is not None:\n                xutils.set_geometry(xwin, x, y, width, height)\n            else:\n                # Wayland: not an X client, so move/resize on our side.\n                self.resize(width, height)\n                self.move(x, y)'
f = sys.argv[1]
s = open(f, encoding='utf-8').read()
old_getx = "    def getXWindow(self):\n        return xutils.get_xwindow(int(self.winId()))\n"
assert s.count(old_getx) == 1
s = s.replace(old_getx, GETX + "\n", 1)
old_drag = "            xutils.set_geometry(self.getXWindow(), x, y, width, height)\n"
assert s.count(old_drag) == 1
s = s.replace(old_drag, DRAG + "\n", 1)
open(f, 'w', encoding='utf-8').write(s)

PY
    commit_or_rollback "$F" "$BAK"
    c_ok "dae/window.py：无窗口句柄时不再发请求，缩放改走 Qt"; changed=$((changed+1))
fi

# ── 5d) app/plugins/youdao/window.py ──────────────────────────
F="$YD_DIR/app/plugins/youdao/window.py"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif grep -q 'def _putOnScreen' "$F"; then
    c_ok "app/plugins/youdao/window.py：已是修复状态，跳过"; already=$((already+1))
else
    grep -q '    def showScreenCenter(self):' "$F" || die "预期内容不符（找不到 showScreenCenter），已中止，未做改动"
    BAK="$(backup_once "$F")"
    run_py "$F" <<'PY'
import sys
APP_BLOCK = '    def _putOnScreen(self, x, y):\n        screen = QtWidgets.qApp.primaryScreen()\n        available = screen.availableGeometry()\n        # Keep a small part of the window reachable.\n        x = max(min(x, available.x() + available.width() - 10),\n                available.x() - self.width() + 10)\n        y = max(min(y, available.y() + available.height() - 10),\n                available.y() - 10)\n        self._lastPos = (int(x), int(y))\n        self._ensurePlatformWindow()\n        if not self._underWayland():\n            self.setPosition(*self._lastPos)\n\n    # QML positions the window with mainView.setX()/setY() and reads mainView.x\n    # and mainView.y back; on a QQuickView these must delegate to the QWindow.\n    def x(self):\n        return QtQuick.QQuickView.x(self)\n\n    def y(self):\n        return QtQuick.QQuickView.y(self)\n\n    _lastPos = None\n    _waylandHint = None\n\n    def _ensurePlatformWindow(self):\n        # QQuickView creates its QPlatformWindow only inside show() (or when\n        # winId() is asked for); setPosition() is a silent no-op before that.\n        if not self.isVisible():\n            self.winId()\n\n    def _underWayland(self):\n        # On Wayland QWindow.setPosition() is ignored (xdg-shell has no\n        # client-side positioning).\n        if self._waylandHint is None:\n            self._waylandHint = QtGui.QGuiApplication.platformName() == "wayland"\n        return self._waylandHint\n\n    def move(self, *args):\n        if len(args) >= 2:\n            x, y = args[0], args[1]\n        else:\n            point = args[0] if args else QtCore.QPoint()\n            x, y = point.x(), point.y()\n        self._putOnScreen(x, y)\n\n    def resize(self, *args):\n        if len(args) >= 2:\n            width, height = args[0], args[1]\n        else:\n            size = args[0]\n            width, height = size.width(), size.height()\n        return QtQuick.QQuickView.resize(self, int(width), int(height))\n\n    def startMove(self):\n        # Wayland replacement for DragableArea.qml\'s absolute positioning:\n        # hand the move over to the compositor for the rest of the drag.\n        # Returns False where plain setPosition() works (X11).\n        if not self._underWayland():\n            return False\n        self._ensurePlatformWindow()\n        return QtQuick.QQuickView.startSystemMove(self)\n\n    @QtCore.pyqtSlot()\n    def showScreenCenter(self):\n        screen = QtWidgets.qApp.primaryScreen()\n        geometry = screen.availableGeometry()\n        if self._lastPos is None:     # nothing picked yet: first time on screen\n            self._putOnScreen(geometry.x() + (geometry.width() - self.width())/2,\n                              geometry.y() + (geometry.height() - self.height())/2)\n        self.show()'
f = sys.argv[1]
s = open(f, encoding='utf-8').read()
old = """    @QtCore.pyqtSlot()
    def showScreenCenter(self):
        screen = QtWidgets.qApp.primaryScreen()
        geometry = screen.availableGeometry()
        self.setX(int(geometry.x() + (geometry.width() - self.width())/2))
        self.setY(int(geometry.y() + (geometry.height() - self.height())/2))
        self.show()
"""
assert s.count(old) == 1, "showScreenCenter not found exactly once"
s = s.replace(old, APP_BLOCK + "\n", 1)
open(f, 'w', encoding='utf-8').write(s)

PY
    commit_or_rollback "$F" "$BAK"
    c_ok "app/plugins/youdao/window.py：主窗口改用 QWindow 的定位与缩放"; changed=$((changed+1))
fi

# ── 5e) qml/DragableArea.qml ──────────────────────────────────
F="$YD_DIR/app/plugins/youdao/qml/DragableArea.qml"
if [ ! -f "$F" ]; then
    c_warn "跳过：找不到 $F"
elif grep -q 'window.startMove()' "$F"; then
    c_ok "qml/DragableArea.qml：已是修复状态，跳过"; already=$((already+1))
elif grep -qF 'systemMove = window.startMove()' "$F"; then
    c_ok "qml/DragableArea.qml：已是修复状态，跳过"; already=$((already+1))
else
    grep -qF "$(printf "	onPressed: {
")" "$F" || die "预期内容不符（找不到 onPressed: {），已中止，未做改动"
    BAK="$(backup_once "$F")"
    run_py "$F" <<'PY'
import sys
QML_PROP = ('\t' + '// Wayland: a client cannot position its own window; let the' + '\n'
            + '\t' + '// compositor take over the move (returns false on X11).' + '\n'
            + '\t' + 'property bool systemMove: false')
QML_COND = ('\t' + 'onPositionChanged: { ' + '\n'
            + '        if (pressed && !systemMove) {')
f = sys.argv[1]
s = open(f, encoding='utf-8').read()
press = "\tonPressed: { \n"
assert s.count(press) == 1
s = s.replace(press, QML_PROP + "\n\n" + press, 1)
cond = "	" + "onPositionChanged: { \n" + "        if (pressed) {"
assert s.count(cond) == 1
s = s.replace(cond, QML_COND, 1)
i = s.index(press) + len(press)
j = s.index("    }\n", i)
s = s[:j] + "        systemMove = window.startMove()\n" + s[j:]
open(f, 'w', encoding='utf-8').write(s)

PY
    # QML 没有 Python 的语法校验，至少确认 systemMove 确实插进去了
    n0=$(grep -o 'startMove' "$BAK" | wc -l); n1=$(grep -o 'startMove' "$F" | wc -l)
    if [ "$n1" -lt $((n0+1)) ]; then
        cp -a "$BAK" "$F"
        die "QML 改写后结构不对，已回滚"
    fi
    c_ok "qml/DragableArea.qml：拖动优先交给系统（不支持时与原来一致）"; changed=$((changed+1))
fi

echo
if [ "$changed" -eq 0 ]; then
    c_ok "全部已是修复状态（$already 项），无需改动"
else
    c_ok "本次修改 $changed 个文件，跳过 $already 个"
    c_info "生效方式：完全退出有道词典后再重新打开"
fi
