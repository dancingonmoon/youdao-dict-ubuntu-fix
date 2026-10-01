# 常见问题与已知限制

## 快速对照：症状 → 怎么办

| 症状 | 处理 |
|---|---|
| 一启动就崩、弹「系统出错」 | 跑 `sudo bash install.sh`（补丁 01） |
| 窗口能开，但四个菜单点了没反应 | 跑 `sudo bash install.sh`（补丁 02），**然后必须重启应用** |
| dock 上多一个 python3 齿轮图标 | 跑 `sudo bash install.sh`（补丁 03），然后重启应用 |
| 托盘图标点了没反应 | 跑 `sudo bash install.sh`（补丁 04），然后重启应用 |
| **所有补丁都打了还是不生效** | **九成是没重启应用**——补丁改的是启动时加载的代码 |
| 百科搜不到 / 权威词典只剩柯林斯 | **修不了**，见下文「已知限制 1」 |
| 托盘右键弹不出菜单 | **修不了**（成本过高），见「已知限制 2」 |
| 点 × 只隐藏、退不掉 | 不是 bug，见「已知限制 3」 |
| 重装 deb 后毛病全回来了 | 补丁被覆盖了，重跑 `sudo bash install.sh` |

---

## 已知限制（脚本解决不了）

### 1. 百科搜不到、权威词典只剩柯林斯

**这是服务器端的下架，不是客户端的问题。**

应用的翻译/词典数据来自 `dict.youdao.com/jsonapi`，请求里要指名要哪些数据源。把包里 `dicts.json` 列出的 27 个数据源一次性问遍服务器，2026-09-27 的实测结果是：

| 仍然可用（9） | 已下线（18） |
|---|---|
| `ec`（基础释义）、`web_trans`（网络释义）、`ee`、`collins`（柯林斯）、`phrs`（词组）、`syno`（同义词）、`blng_sents_part`（双语例句）、`media_sents_part`、`auth_sents_part` | **`baike`（百科）**、**`ec21`（21世纪大英汉）**、**`ce_new`**、`fanyi`、`pic_dict`、`typos`、`web_search`、`special`… |

所以「释义 / 用法 / 例句」是正常的，只有「百科」是空的、权威词典只剩柯林斯一本。
客户端问得没错，是服务器答「我没有」——**改客户端救不回来**。真想恢复得重写成抓取今天的网页版，那是另一个项目，且官方一改版就再坏。

> 自己复核：
> ```bash
> curl -s -G 'http://dict.youdao.com/jsonapi' \
>   --data-urlencode 'client=deskdict_deepin' --data-urlencode 'le=eng' \
>   --data-urlencode 'q=hello' \
>   --data-urlencode 'dicts={"count":1,"dicts":[["baike"]]}' | head -c 300
> ```
> 返回里找不到 `"baike"` 这个键，就说明确实没有了。

### 2. 托盘图标右键菜单弹不出来

托盘图标走的是 Qt 的 StatusNotifierItem。用 `busctl` 能查到它导出的属性：

```
Menu       = "/NO_DBUSMENU"     ← Qt5 不实现 DBusMenu，这里是个占位符
ItemIsMenu = false
```

GNOME 的托盘扩展需要一份 DBusMenu 才能画出菜单，Qt5 根本不给，于是**没有菜单可弹**。
左键是好的（切换窗口显示/隐藏）。要彻底修得自己实现 DBusMenu 协议并接管托盘——工作量远超本项目的其它修复，收益只是一个菜单，**不建议**。

### 3. 点窗口右上角 × 只是隐藏，退不掉

这不是 bug，是应用原本的设计（常驻托盘）。三种退出方式：

- 窗口**左下角「开始」→ 退出**（推荐）
- 命令行 `pkill -f youdao-dict`
- 想改成点 × 直接退出：**软件设置 → 取消勾选「窗口关闭时最小化到托盘」**
  （对应配置项 `~/.config/youdao-dict/config.ini` 里的 `[basic_option] close_to_tray`，默认 `True`）

---

## 其它常见问题

### 会不会开机自启？

**不会。** 包里确实带了一个自启项 `/etc/xdg/autostart/youdao-dict-autostart.desktop`，但文件内容里有 `Hidden=true`（包原版就是这样），实际不生效。
另外它还会被 systemd 抱怨一句「marked executable」（文件权限不该带可执行位），无害。

### 占多少资源？

实测（Ubuntu 24.04 + 移植 GPU 驱动）：空闲常驻约 **7–10% 单核**，启动瞬间峰值约 30%，另外给桌面合成器增加 5–8%。
对一个常驻词典来说偏重（QtWebKit 老引擎），介意就关掉它——不会有残留进程。

### 支持 ARM / 其它架构吗？

脚本本身与架构无关，改的是 Python 源码。但补丁按**文件内容**匹配，如果你用的是 `youdao-dict_6.0.0-arm64.deb`，**部分位置可能对不上**——脚本会中止并告诉你哪一项没匹配上，不会改坏。届时可以对照 `payload/` 里的补丁手工处理。

### 支持 Ubuntu 22.04 吗？

支持。22.04 是 Python 3.10，`imp` 和 `getargspec` 都还在，脚本会**自动跳过**这两项，只做 `collections.Mapping` 那一项（如果它确实需要）。体检表里显示「不适用」是正常的。

### 会不会破坏我的词典数据 / 设置？

不会。补丁只改 `/usr/share/youdao-dict/` 下的 7 个**程序文件**，不碰 `~/.config/youdao-dict/`（设置）和 `~/.local/share/Youdao/`（数据）。

### 还原后会不会有残留？

`uninstall.sh` 从 `*.bak-<日期>` 备份逐字节还原，脚本本身不往系统里装任何东西（没有 systemd 单元、没有 autostart、没有环境变量）。

### 装完 `dpkg -V youdao-dict` 会报文件被改，正常吗？

正常。补丁就地修改了 7 个文件，`dpkg -V` 会把它们标成 `??5??????`。这是**预期行为**，不是损坏。
（如果你看到 `missing ... __pycache__/*.cpython-35.pyc` 之类，那说明有人清理过字节码缓存——不影响运行，Python 3.12 根本不会读 Python 3.5 的 `.pyc`。）

### 还有别的毛病，本仓库没修

AUR 的 [`youdao-dict`](https://aur.archlinux.org/packages/youdao-dict) 包还额外修了两处（**本仓库未包含、也未验证**，需要的话可以自行参考）：

- `window.py` 里 `self.setX(x)` / `self.setY(y)` 未取整 → 改成 `int(x)` / `int(y)`。某些环境下窗口会跑到屏幕外或位置异常
- `shadowwindow.py` 去掉 `if not wmHelper.hasComposite:` 一行（合成器/阴影相关）

另外 Aur 上还有一批**替代方案**（都是独立实现，与有道无关）：`ydict`、`ydcv`、`wudao-dict`。
