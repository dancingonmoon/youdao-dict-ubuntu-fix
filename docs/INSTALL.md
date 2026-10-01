# 安装与使用

## 0. 前提

| 项目 | 要求 |
|---|---|
| 系统 | Ubuntu 22.04 / 24.04（其它 Debian 系同理） |
| 应用 | 有道词典 Linux 版 6.0.0（`youdao-dict_6.0.0-ubuntu-amd64.deb`） |
| 权限 | 打补丁需要 `sudo`（改的是 `/usr/share/youdao-dict/` 下的系统文件） |

**下载官方原版**：

- 下载页 <https://fanyi.youdao.com/download-multi/>
- 直链 <https://codown.youdao.com/cidian/linux/youdao-dict_6.0.0-ubuntu-amd64.deb>
- sha256 应为 `e56f248c3caf7d0bff9f4f18780d9b258612b490c1c0f332335b8d15471e0dd2`

> 校验下载是否完整：
> ```bash
> sha256sum youdao-dict_6.0.0-ubuntu-amd64.deb
> ```
> 对不上就不要用——补丁按文件内容匹配，包不对会直接中止（不会改坏），但也没意义。

## 1. 安装官方原版

```bash
sudo apt install ./youdao-dict_6.0.0-ubuntu-amd64.deb
```

如果提示依赖缺失：

```bash
sudo apt --fix-broken install
```

装完**先别急着用**——在 Ubuntu 24.04 上它一启动就会崩，这是正常的（这正是本补丁要解决的）。

## 2. 打补丁

```bash
# 进入本仓库目录后
sudo bash install.sh
```

脚本会依次：

1. 检查有道词典是否已安装
2. 如果检测到应用正在运行，提醒你先退出（补丁改的是磁盘文件，运行中的进程不会变）
3. 依次执行四个补丁（`payload/01` ~ `payload/04`），每个补丁都会**备份 → 修改 → 语法校验**
4. 最后自动跑一遍体检

想只修某一个问题，也可以单独运行，例如：

```bash
sudo bash payload/02-backend-indent.sh   # 只修「菜单点不动」
```

## 3. 重启应用

```bash
pkill -f youdao-dict     # 如果它正在运行
```

然后从应用菜单打开有道词典。**必须重启才生效**——补丁改的是启动时加载的代码。

> 顺带记住怎么**退出**这个应用：点右上角的 × 只是隐藏到托盘（应用原本的设计）。
> 真正退出是**窗口左下角「开始」→ 退出**。
> 想改成点 × 直接退出：软件设置里取消勾选「窗口关闭时最小化到托盘」。

## 4. 验证

```bash
bash verify.sh
```

期望输出（Ubuntu 24.04）：

```
环境
    python3      : /usr/bin/python3（Python 3.12.3）
    安装目录     : /usr/share/youdao-dict

补丁状态
  01a dae/plugins.py (imp)                   ✓ 已修（改用 importlib）
  01b pyquery.py (getargspec)                ✓ 已修（getfullargspec）
  01c app/plugins/youdao/utils.py (collections.Mapping) ✓ 已修（collections.abc.Mapping）
  01d backend/utils.py (collections.Mapping) ✓ 已修（collections.abc.Mapping）
  02 youdao-dict-backend.py                  ✓ 已修（缩进正常）
  03 dae/daeclient.py                        ✓ 已修（app_id = youdao-dict）
  04 dae/window.py (setVisible)              ✓ 已修（@pyqtSlot(bool)）

结果
  通过 7    失败 0    不适用 0
```

在 Python 3.10 的老系统上，前四项可能显示「不适用——当前 Python 仍有该 API」，这是**正常的**（那些 API 还没被删，无需修）。

## 5. 人工确认

启动有道词典，确认：

- [ ] 窗口正常打开，不再弹「系统出错」
- [ ] 顶部**词典 / 例句 / 百科 / 翻译**四个菜单点得动、内容会切换
- [ ] 输入一个单词查询，能出结果（`ec` 释义、柯林斯、例句等）
- [ ] 左侧 dock 上**没有**多余的 python3 齿轮图标
- [ ] 点顶栏的托盘小图标，窗口能显示/隐藏

## 6. 卸载 / 还原

```bash
sudo bash uninstall.sh
```

会从 `*.bak-<日期>` 备份还原全部 7 个文件（还原后应用回到「启动即崩」的原版状态）。

如果备份被清理掉了，用官方 deb 重装一遍等同于还原：

```bash
sudo apt install --reinstall ./youdao-dict_6.0.0-ubuntu-amd64.deb
```

## 7. 重装系统 / 换了新机器？

直接重跑第 1、2 步即可。补丁脚本不依赖任何本机状态，也**不需要联网**（除了你自己下载 deb）。
