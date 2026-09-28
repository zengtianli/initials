# Initials · 一个键切到任何 app

**中文** | [English](README_EN.md)

[官网、下载与安装教程](https://initials.tianli.cyou/) · [English website](https://initials.tianli.cyou/en/)

按住 **⌘** 再按字母，瞬间切到、打开或隐藏对应的 app；快速**双击 ⌘**，弹出字母面板，再按字母切换。左右两个 ⌘ 各自可设，可以同时用。原生 macOS（Swift + AppKit），常驻菜单栏，附带同源 `initials` 命令行；实测占用见[资源占用](#资源占用)。

![左右 ⌘ 都可设置：按住 + 字母直达，双击弹出字母面板](site/assets/scene-keys-zh.png)

<!-- lightweight:start -->
## 资源占用

| 安装包 | 空闲内存 | 空闲 CPU | 启动到字母面板离屏渲染完成（含 PNG 导出） |
|---|---|---|---|
| **1.8 MB**（装好后 2.0 MB） | **13.6 MB** | **0%** | **99 ms** |

纯 AppKit，零第三方依赖；按键由系统事件回调送达，回调里只做几次比较，切换动作放到回调外执行；配置改动由 kqueue 通知、不轮询，仅每 30 秒确认一次按键监听仍开着。

内存口径：活动监视器同口径 phys_footprint，主进程与辅助进程合计13 MB；原配置与辅助功能权限保留。

CPU 口径：安装版在输入设备闲置超过10分钟后后台切换；静置45秒后测60秒，CPU时间增量低于本次计时分辨率，显示0.00%。

<sub>v1.1.1 · Mac16,12 / Apple M4 / macOS 27.2 · 2026-09-26。数字来自所列设备实测，版本更新后重新测量。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->

当前 v1.1.2（4）沿用上方 v1.1.1 在 2026-09-26 的历史实测作为参考，尚未重新测量。此轮新增离屏界面自检及其关闭守卫，正常运行的按键引擎、切换、监听和界面布局未变；表中安装包体积同样属于 v1.1.1，当前下载大小以官网按钮为准。

## 用法

左右两个 ⌘ 各有两个开关，可以只开一个，也可以都开。默认：右 ⌘ 按住，左 ⌘ 双击。

- **按住 ⌘ + 字母**：
  - 指定了 app 的字母：没开就启动，开着就切过去；已在最前就隐藏，再按一次切回来。
  - 右 ⌘ 没指定的字母：在名字以它开头、正在运行的 app 之间轮换。
  - 左 ⌘ 只接管字母表里指定过的字母，⌘C、⌘V 等照常；如果指定的字母占了常用快捷键，设置窗和 `initials list` 会提示。
  - 同时按 ⇧⌥⌃ 的组合照常放行；两个 ⌘ 同时按住时以右 ⌘ 为准。
- **双击 ⌘，再按字母**：屏幕中间弹出这一边的字母面板，不抢当前窗口焦点；Esc 或 4 秒不按键自动关闭。两下之间按了别的键、点了鼠标、按住太久或左右各按一下都不算双击。
- 左右各有一张字母表；默认左边沿用右边的表，可以在设置里分开。
- **设置**（菜单栏 ⌘ 图标 → 设置）：⌘1/⌘2 切换右 ⌘ / 左 ⌘，⌘N 添加，⌫ 移除，↩ 换 app，⌘W 关闭。可一键“从 Hammerspoon 导入”已有的 rcmd 映射，确认可用后一键“关闭 Hammerspoon rcmd”。

## 安装

需要 macOS 14+，Apple Silicon。

1. 打开 DMG，把 Initials 拖到“应用程序”，从“应用程序”打开。安装包使用 Developer ID 签名并经 Apple 公证。
2. 在设置窗口点“打开辅助功能设置…”，在“系统设置 › 隐私与安全性 › 辅助功能”里打开 Initials。顶部显示“✓ 已授权辅助功能，正在工作”即可，不用重启。Initials 只看 ⌘ 和紧跟的字母，不记录、不保存输入。
3. 点“添加…”给字母指定 app，或“从 Hammerspoon 导入”。

## 命令行

```bash
initials list                      # 两边的字母表
initials set m Music               # 名字、bundle id 或 /路径/To.app
initials set w WeChat --side left  # 左边单独设（先 initials share off）
initials unset m
initials import [--from keymaps.lua]
initials hold on|off [--side right|left]  # 按住该 ⌘ + 字母
initials tap on|off [--side right|left]   # 双击该 ⌘ 弹面板
initials enable|disable [right|left|all]
initials status [--json]           # 运行、授权、拦截状态
initials hammerspoon rcmd on|off   # 切换 MacKit 的 Hammerspoon rcmd
```

退出码：0 成功，1 没找到，2 用法错误，3 Initials 没在运行（status）。配置在 `~/Library/Application Support/cyou.tianli.initials/config.json`，app 会监视文件，改动即时生效。装有 [MacKit](https://github.com/zengtianli/mackit) 时，当前字母会写入 `~/.config/mackit/keys.d/initials.json`，`mackit keys` / `mackit doctor` 可查到并检查冲突。

## 实测

[资源占用](#资源占用)区块由 [perf/lightweight.json](perf/lightweight.json) 自动生成，列出安装包、空闲内存、CPU 与启动速度及其测量版本和条件。`build.sh` 另含按键判断基准；切换动作放到拦截回调外执行。

## 构建

```bash
bash build.sh               # 先跑单元测试，再编译 app 与 CLI、签名 → build/Initials.app
bash scripts/install.sh     # 退出 Initials 后安装到 /Applications，CLI 链到 ~/.local/bin
python3 scripts/release.py  # 公证 app 与 DMG 并装订，写 build/release.json
python3 scripts/shots.py    # 从构建出的 app 重新生成 site/assets 截图与场景图
python3 scripts/build-site.py  # 用 release.json 生成 build/site（主页 + 下载）
```

界面验证不抢焦点：`Initials --snapshot out.png --settings right|left [--dark]`、`--snapshot out.png --picker [--right]` 离屏渲染；`Initials --simulate right:m,left:s` 只打印每个字母此刻会做什么，不执行。测试隔离用 `INITIALS_SUPPORT_DIR=<目录>`。

## 许可

MIT。
