# 变更日志

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
