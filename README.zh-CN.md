# 用量胶囊 · Usage Capsule

**简体中文** · [English](README.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

一个小巧的原生 macOS 桌面胶囊，随时查看 Codex 的五小时与本周额度。深色光泽玻璃、暖金属边缘、五档清晰颜色，常驻可见尺寸 **184 × 60 pt**。

![用量胶囊与展开概览，均为示例数据](docs/preview.png)

## 功能

- 常驻显示日额（五小时窗口）与周额；展开后查看重置时间、倒计时和已用比例。
- 悬停呼出概览，点击固定，按 × 或 Escape 关闭。
- 近七天每日 Token 小格子，选择日期查看当天准确消耗。
- 浅金、琥珀、橙、朱橙、珊瑚红五档颜色，50% 附近仍清晰明亮。
- 整个胶囊窗口范围均可拖动；支持菜单栏找回、100–150% 缩放和置顶。
- 简体中文、英语、日语、韩语，可跟随系统或手动切换。
- 查询可用重置卡，长按 0.8 秒先打开确认框，客户明确点击“确认使用”后才提交；取消或按 Escape 不会消费。演示模式禁止兑换。
- 登录过期时自动重建连接并重试一次；仍无法读取时隐藏旧额度，提示重新登录，避免把过期数据当成实时额度。

## 使用条件

需要 **Apple Silicon Mac、macOS 13 或更高版本、Xcode 命令行工具**。查询真实用量还需要本机已登录的 Codex CLI。应用使用 SwiftUI 与 AppKit，无需 Electron 或 Node。

这是社区作品，并非 OpenAI 官方产品。每日消耗和重置卡功能取决于本机 Codex CLI 与账号支持；没有返回的数据会显示为不可用。

## 通过 Skill 安装

把下面这段话发给 Codex：

> 使用 $skill-installer 从 https://github.com/guihaoyegui-ctrl/usage-capsule 安装 skills/usage-capsule，然后使用 $usage-capsule 在我的 Mac 上构建、安装并启动用量胶囊。

Skill 自带完整应用源码和玻璃素材。安装 Skill 后还需构建并启动应用；只有云端的会话无法在你的桌面显示原生窗口。

## 手动安装

下载仓库，在终端进入仓库文件夹后依次执行：

```sh
zsh skills/usage-capsule/scripts/capsule.sh doctor
zsh skills/usage-capsule/scripts/capsule.sh install
zsh skills/usage-capsule/scripts/capsule.sh start
```

安装位置为 `~/Applications/Usage Capsule.app`。应用在本机编译并临时签名，当前预览版尚未经过 Developer ID 公证。请审阅源码后本机构建，保持 Gatekeeper 启用。缺少编译工具时，使用 `xcode-select --install` 安装 Apple 命令行工具。

右键胶囊或点击菜单栏图标，即可设置语言、刷新、隐藏和退出。也可用 `language zh-Hans` 切换语言；支持 `system`、`zh-Hans`、`en`、`ja`、`ko`。

`preview` 输出离线示例 PNG；`demo` 在已安装的胶囊停止运行时打开演示窗口。`status` 仅检查安装的进程，账号是否连通请以概览内同步结果为准。

## 刷新与隐私

每 60 秒通过本机 Codex app-server 查询账号用量，不创建模型生成任务，因此刷新本身不会调用模型生成 Token。安装和交谈过程仍有正常的模型用量。应用复用本机 Codex 登录，无需 API Key，没有开发者服务器或统计上报。详见[数据与隐私](docs/PRIVACY.md)、[常见问题](docs/TROUBLESHOOTING.md)。

## 验证与源码

```sh
zsh skills/usage-capsule/assets/app/test.sh
zsh skills/usage-capsule/assets/app/test.sh --ui
```

包含额度计算、重置幂等保护、交互状态及四种翻译的检查；`--ui` 增加原生点击范围验证，需要桌面环境。测试不会消费重置卡。详见[验证范围](docs/VALIDATION.md)及[版本记录](CHANGELOG.md)。

源码位于 [`skills/usage-capsule/assets/app`](skills/usage-capsule/assets/app)。公开 GitHub 仓库与上架官方插件目录是不同步骤，当前发布为 GitHub 项目与可安装 Skill。

当前预览版尚未选择开源许可证。
