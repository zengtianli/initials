# Initials · 一个键切到任何 app

**中文** | [English](README_EN.md)

按住**右 ⌘** 再按字母，瞬间切到、打开或隐藏对应的 app；快速**双击左 ⌘**，弹出字母面板，再按字母切换。原生 macOS（Swift + AppKit），常驻菜单栏，约 15 MB 内存，附带同源 `initials` 命令行。

## 用法

- **右 ⌘ + 字母**：
  - 指定了 app 的字母：没开就启动，开着就切过去；已在最前就隐藏，再按一次切回来。
  - 没指定的字母：在名字以它开头、正在运行的 app 之间轮换。
  - 只拦截“右 ⌘ + 单个字母”；右 ⌘ 同时按 ⇧⌥⌃ 时照常放行，左 ⌘ 的 ⌘C、⌘V 等完全不受影响。
- **双击左 ⌘，再按字母**：屏幕中间弹出字母面板，不抢当前窗口焦点；Esc 或 4 秒不按键自动关闭。两下之间按了别的键、点了鼠标或按住太久都不算双击。
- 左右各有一张字母表；默认左边沿用右边的表，可以在设置里分开。
- **设置**（菜单栏 ⌘ 图标 → 设置）：⌘1/⌘2 切换左右，⌘N 添加，⌫ 移除，↩ 换 app，⌘W 关闭。可一键“从 Hammerspoon 导入”已有的 rcmd 映射，确认可用后一键“关闭 Hammerspoon rcmd”。

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
initials enable|disable [right|left|all]
initials status [--json]           # 运行、授权、拦截状态
initials hammerspoon rcmd on|off   # 切换 MacKit 的 Hammerspoon rcmd
```

退出码：0 成功，1 没找到，2 用法错误，3 Initials 没在运行（status）。配置在 `~/Library/Application Support/cyou.tianli.initials/config.json`，app 会监视文件，改动即时生效。装有 [MacKit](https://github.com/zengtianli/mackit) 时，当前字母会写入 `~/.config/mackit/keys.d/initials.json`，`mackit keys` / `mackit doctor` 可查到并检查冲突。

## 实测

- 内存：约 15 MB（`footprint`，菜单栏常驻、空闲）。
- CPU：空闲 1 分钟约 0.04 秒；按键判断在拦截回调里约 4 ns/次（`build.sh` 内置基准），切换动作放到回调外执行。
- 安装包：约 1.8 MB。

## 构建

```bash
bash build.sh               # 先跑单元测试，再编译 app 与 CLI、签名 → build/Initials.app
bash scripts/install.sh     # 退出 Initials 后安装到 /Applications，CLI 链到 ~/.local/bin
python3 scripts/release.py  # 公证 app 与 DMG 并装订，写 build/release.json
python3 scripts/build-site.py  # 用 release.json 生成 build/site（主页 + 下载）
```

界面验证不抢焦点：`Initials --snapshot out.png --settings right|left [--dark]`、`--snapshot out.png --picker` 离屏渲染；`Initials --simulate right:m,left:s` 只打印每个字母此刻会做什么，不执行。测试隔离用 `INITIALS_SUPPORT_DIR=<目录>`。

## 许可

MIT。
