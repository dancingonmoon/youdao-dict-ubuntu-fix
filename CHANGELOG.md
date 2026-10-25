# 变更日志

## v1.1.0 — 2026-10-25

新增补丁 05，针对 **GNOME Wayland** 会话（`XDG_SESSION_TYPE=wayland`）：

- **新增 05-wayland-stability** —— 修两处 Wayland 下的失效：
  - `dae/shadowwindow.py` 在窗口映射前就向 X 写阴影属性 → `BadWindow` → Qt5WebKit 段错误，**进程偶发消失**。现在 X 错误只忽略 `BadWindow`，写属性前先确认窗口存在，阴影属性延后到事件循环。
  - 主窗口 `QQuickView` 缺少 `x/y/move/resize`，QML 和拖动代码静默失败 → **缩放不跟手**。现在在 `QQuickView` 上补齐这些接口并委托给 `QWindow`；`getXWindow()` 拿不到真窗口时返回 `None`，不再发无效 X 请求。
  - `DragableArea.qml` 在支持的合成器上改由系统代为拖动（不支持时行为与原来一致）。

**已知限制（同样写进了 TROUBLESHOOTING）**：

- GNOME Wayland 下**无法用鼠标拖动窗口**。Wayland 不允许客户端设置窗口位置（`setPosition()` 静默无效），Qt 5.15 的 `startSystemMove()` 在非 tiling 合成器上直接返回 false。已逐一实测 ALT / CTRL+ALT / ALT+CTRL / SUPER 组合键与滚轮方案，均被系统占用或不适用。需要拖动只能让有道单独走 X11（`QT_QPA_PLATFORM=xcb`，代价是 125% 缩放下文字略糊）。
- **左上角拖动缩放不跟手**是有道自带的逻辑问题（每次移动重算端点方向），补丁未改；右下角正常。

`verify.sh` 新增 5 项检查（共 12 项），`uninstall.sh` 的文件清单同步扩展到 12 个。

## v1.0.0 — 2026-10-01

首个版本。针对有道词典 Linux 版 **6.0.0** 在 Ubuntu 24.04（Python 3.12）上的四处缺陷：

- **新增 01-py312-compat** —— 适配新版 Python 删除的三处 API（`imp` / `inspect.getargspec` / `collections.Mapping`），解决**启动即崩、弹 apport「系统出错」**。按解释器实际能力逐项判断，Python 版本较老时自动跳过。
- **新增 02-backend-indent** —— 修掉 `youdao-dict-backend.py` 第 37 行多出的一个空格，解决**顶部四个菜单点击无效**（根因是该语法错误让 DBus 后端永远起不来，界面每次调用后端都同步阻塞约 5 秒）。
- **新增 03-desktop-appid** —— 补 `app.setDesktopFileName('youdao-dict')`，解决**左侧 dock 多出 python3 齿轮图标**。
- **新增 04-tray-setvisible** —— 修正 `dae/window.py` 中 `setVisible` 的 Qt 槽签名，解决**托盘图标点击无反应**。

配套：

- `install.sh` / `uninstall.sh` / `verify.sh` 三个入口脚本，全部幂等、防呆、自动备份、改后语法校验（失败回滚）
- 文档：`docs/INSTALL.md`（操作步骤）、`docs/HOW-IT-WORKS.md`（根因与验证手段）、`docs/TROUBLESHOOTING.md`（常见问题与已知限制）

已在 Ubuntu 24.04.5（Python 3.12.3）+ 官方 `youdao-dict_6.0.0-ubuntu-amd64.deb` 上完成端到端验证：
装机 → 崩溃 → 打补丁 → 启动正常 → 四个菜单可用 → 托盘左键可用 → 可正常退出。
