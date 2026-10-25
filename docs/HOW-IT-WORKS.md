# 根因分析与验证手段

这份文档记录五个缺陷（其中 05 只影响 Wayland 会话）**为什么**会出现、**怎么定位**的，以及**怎么独立验证**。
适合想搞清楚原理、或想把这套方法用到别的老软件上的人。

---

## 总览

缺陷彼此独立，各自让应用卡在完全不同的阶段：

```
启动
 ├─ [01] import imp            → 崩在 import 阶段，窗口都出不来
 ├─ 加载插件
 │   └─ [01] getargspec        → 插件（整个词典 UI）加载失败，被 try/except 吞掉 → 空壳
 ├─ 创建主窗口
 │   └─ [03] app_id = python3  → 窗口能出来，但 GNOME 认不出归属
 ├─ 显示界面
 │   └─ [02] 后端 IndentationError → DBus 服务起不来 → 每次交互主线程卡 5 秒
 ├─ 托盘交互
 │   └─ [04] 槽签名错误        → 点击静默失败
 └─ 首次交互 (Wayland)
     └─ [05] 未映射窗口写 X 属性 → BadWindow → WebKit 段错误，进程消失
```

其中 **02 和 04 与 Python 版本毫无关系**——是这个包**自带**的笔误，任何系统上都存在。换句话说：这个包在它自己的年代、它自己的发行版上，可能也有一半功能是坏的。

---

## 01 · 新版 Python 删掉的三处 API

| API | 何时消失 | 在应用里的位置 |
|---|---|---|
| `imp`（`imp.load_source`） | Python **3.12** 删除（PEP 594） | `dae/plugins.py` —— 插件加载器 |
| `inspect.getargspec` | Python **3.11** 删除 | `app/plugins/youdao/pyquery/pyquery.py`（2 处） |
| `collections.Mapping` | Python **3.10** 起只在 `collections.abc` | `app/plugins/youdao/utils.py`、`backend/utils.py` |

**为什么这个包特别容易中招**：它的代码底子是 2011–2015 年 Deepin 的 `dae` 框架，虽然做过 Python 3 移植（文件里能看到 `PY3k` 分支），但当年移植时 `imp` 和 `getargspec` 都还在，就被留下了。

**修法**：

```python
# imp.load_source(name, path) 的等价物
spec   = importlib.util.spec_from_file_location(name, pathname)
module = importlib.util.module_from_spec(spec)
sys.modules[name] = module
spec.loader.exec_module(module)
```

`getargspec` → `getfullargspec`（两处调用只取 `.args` / `.defaults`，语义一致，可直接替换）。
`collections.Mapping` → `collections.abc.Mapping`（并把 `import collections` 改成 `import collections.abc`）。

**怎么定位**：`journalctl` 里能看到完整 traceback：

```
$ journalctl -b --no-pager | grep -A5 "youdao-dict.desktop"
  File "/usr/share/youdao-dict/dae/plugins.py", line 23, in <module>
    import imp
ModuleNotFoundError: No module named 'imp'
```

**怎么验证**：`python3 -c "import imp"` 报 ModuleNotFoundError 即需要补丁。

---

## 02 · 后端脚本多出的一个空格

**这是最难找、也最"冤"的一个。**

```python
# /usr/share/youdao-dict/youdao-dict-backend.py 第 36-37 行
    session_bus = QtDBus.QDBusConnection.sessionBus()
     print("Youdao Backend Service is started...")     # ← 行首多了一个空格
```

一个空格 → `IndentationError: unexpected indent` → 这个脚本**任何 Python 上都跑不起来**。

它是 DBus 服务 `com.youdao.backend` 的实现（见 `/usr/share/dbus-1/services/com.youdao.backend.service`）。于是：

```
主程序调用后端（比如切个 tab 会调 stopSound）
   → DBus 按需拉起 youdao-dict-backend.py
   → 进程秒崩（语法错误）
   → QtDBus 同步调用阻塞约 5 秒后返回错误      ← 主线程被卡住
   → 应用还每 ~5 秒重试一次
```

**表现**就是：窗口画出来了，但**点哪都没反应**（主线程几乎全程被阻塞），`journalctl` 里每 5 秒刷一次：

```
dbus-daemon: Activating service name='com.youdao.backend' ...
  File "/usr/share/youdao-dict/youdao-dict-backend.py", line 37
IndentationError: unexpected indent
dbus-daemon: Activated service 'com.youdao.backend' failed: Process exited with status 1
```

**怎么定位**：从"点了没反应"顺藤摸瓜——先确认是不是 UI 卡住（用 `faulthandler.dump_traceback_later()` 把所有线程栈打出来，能直接看到主线程阻塞在 `QDBusInterface.call()`）。

**怎么验证修好了**：`journalctl` 里应只出现**一次** `Successfully activated`，而不再循环失败。

**为什么不修客户端阻塞也算"修好"**：补丁 02 让服务能起来，调用瞬间返回，阻塞自然消失。若要更彻底，可把那些同步 DBus 调用改成异步——但那要改的是应用逻辑，风险大得多。

---

## 03 · dock 上的 "python3" 齿轮图标

Qt5 在 Wayland 下给窗口设置 `xdg_toplevel.set_app_id(...)` 时，来源顺序大致是：`QGuiApplication::desktopFileName()` → 拿不到就用**进程名**。

这个应用只设了 `setApplicationName("Youdao Dict")`，没设 `setDesktopFileName`，于是窗口上报：

```
-> xdg_toplevel@25.set_app_id("python3")
```

GNOME 拿 `python3` 去找 `python3.desktop`（不存在），只能给一个通用齿轮图标；而 `youdao-dict.desktop` 明明就在 `/usr/share/applications/`。

**怎么定位（直接读协议）**：

```bash
WAYLAND_DEBUG=1 QT_QPA_PLATFORM=wayland /usr/bin/python3 /usr/share/youdao-dict/main.py 2>&1 \
  | grep -i set_app_id
```

改前是 `set_app_id("python3")`，改后是 `set_app_id("youdao-dict")`。
这是最硬的证据——不是猜的，是应用亲口对合成器说的话。

**生效时机**：GNOME 在**窗口建立时**判定归属，所以必须重启应用；仅重新打开窗口不一定够。

---

## 04 · 托盘图标点了没反应

```python
# /home/.../dae/window.py
    # 设置窗口可见状态
    @pyqtSlot(result = bool)          # ← 抄了上面 isVisible 的装饰器
    def setVisible(self, visible):    # ← 但方法需要参数
```

`@pyqtSlot(result = bool)` 声明的是一个**无参数、返回 bool** 的槽。JS 端这样调：

```js
$(".js-main-menu-btn").on(...)
// 托盘点击 →  toggle()
app.setVisible(visible)      // 传了 1 个参数
```

PyQt 侧于是抛 `TypeError: setVisible() missing 1 required positional argument: 'visible'`，
而 **JS 侧完全看不到这个异常**——调用"成功返回"，什么都没发生。这就是"点了没反应"。

**怎么定位（复现 JS→Python 桥接）**：用一个最小 Qt 程序把两种签名的槽都挂给 WebView，从 JS 调用：

```python
from PyQt5.Qt import QApplication, QWebView
from PyQt5.QtCore import QObject, pyqtSlot
class W(QObject):
    @pyqtSlot(result=bool)   # 现状（错）
    def setVisible(self, v): ...
    @pyqtSlot(bool)          # 正确
    def setVisibleOk(self, v): ...
view.page().mainFrame().addToJavaScriptWindowObject('W', w)
view.page().mainFrame().evaluateJavaScript("W.setVisible(true)")
```

得到：

```
TypeError: W.setVisible() missing 1 required positional argument: 'visible'
   [Python] setVisibleOk 被调用, 参数 = True
```

**顺带一提**：托盘的 Qt 侧接口本身是好的——用 `busctl --user call <SNI> ... Activate ii 5 5` 模拟点击，Qt 会正常发出 `activated` 信号（reason=3 左键 / 1 右键）。断的是它到 JS 的这一跳。

**为什么右键仍然没救**：右键要弹菜单，而 Qt5 的托盘实现导出的是 `Menu=/NO_DBUSMENU`（Qt 不实现 DBusMenu 协议），GNOME 侧根本没有菜单可弹。要修得整个重写托盘实现，性价比太低。

---

## 05 · Wayland 下启动即崩、缩放不跟手

**症状**：GNOME Wayland 会话里，启动后第一下交互时进程消失；`journalctl` 里能看到
`<class 'Xlib.error.BadWindow'>: code = 3 ... major_opcode = 18`，紧跟着
`python3[pid]: segfault ... in libQt5WebKit.so.5`；`/var/crash` 留下 SIGSEGV 报告。

**根因**：`dae/shadowwindow.py` 的 `setShadowWidth()` 在 `__init__` 里（窗口还没映射）就取
`int(self.winId())`，用 python-xlib 直接向该窗口写 `DEEPIN_WINDOW_SHADOW`。
Wayland 会话里 Qt 不创建 X 窗口，`winId()` 得到的不是 XID，WM 回 BadWindow；
异常从事件回调里逸出，和第一次 WebKit 绘制相撞 → 段错误。

**怎么定位**：`journalctl -b | grep -A3 BadWindow`，或用 `/var/crash` 里的 `Date:` 对齐日志时间。
只用崩溃报告本身看不出原因（里面只有 SIGSEGV，没有 Python 栈）——真正有用的是崩溃前那一行 X 错误。

**第二个问题（缩放不跟手）**：主窗口是 `QQuickView`，它是 `QWindow` 而不是 `QWidget`，
**没有** `move()/setX()/setY()`。QML 用 `mainView.setX/setY` 摆位置、`dae/window.py` 的拖动又走
Xlib `set_geometry`——所以 QML 读到的坐标永远是 0、拖动时 Qt 侧的位置从未更新过。
在 Wayland 下这条 Xlib 路径不会生效，而 Qt 自己的定位又根本不存在——两个原因叠在一起，窗口就纹丝不动。

**修法**：X 错误只忽略 BadWindow；阴影属性延后到事件循环；`getXWindow()` 拿不到真窗口返回 `None`；
在 `QQuickView` 上补 `x/y/move/resize` 委托给 `QWindow`，缩放改走 Qt 自己的 `resize()`。

**怎么验证**：Wayland 会话里拖右下角，窗口应能跟着鼠标缩放；`journalctl` 里不再出现
`BadWindow` 和 `segfault`。拖动仍然无效（见 `TROUBLESHOOTING.md` 已知限制 5），这是协议层面的。

---

## 附：几个通用经验

1. **老软件在新系统上出问题，先看 `journalctl` 的 Python traceback**——多数是"逐版本删除 API"造成的年代差，而不是软件本身损坏。
2. **"界面点了没反应"要分两种**：UI 线程被阻塞（卡死），还是调用静默失败（异常被吞）。前者用 `faulthandler` 抓栈，后者要从 JS/Python 两端分别验证。
3. **两个症状、两处根因**：本项目里"菜单点不动"和"托盘点不动"长得像，实际毫无关系。
4. **验证要看"协议级证据"**（`WAYLAND_DEBUG` 的 `set_app_id`、DBus 的激活结果），不要靠"看起来好了"。
5. **测桌面性能时小心自测干扰**：在终端里跑大量输出的命令会持续重绘终端，把合成器 CPU 顶上去十几倍；要测空闲基线，得把采样放到后台任务里、自己停止输出。
