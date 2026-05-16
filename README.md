# Session Bridge

Windows 桌面工具，用于集中查看本机 Codex / Claude 会话，按需生成 AI 摘要，并通过 PowerShell 一键恢复会话。

## 运行

Release 程序位于：

```text
build\windows\x64\runner\Release\session_bridge.exe
```

## 功能

- 自动扫描 `%USERPROFILE%\.codex\sessions` 和 `%USERPROFILE%\.claude\projects`。
- 列表展示会话来源、更新时间、工作目录、主要内容和关键消息。
- 点击“恢复”会打开 PowerShell 并执行对应恢复命令。
- 点击“全部 AI 分析”会顺序分析全部会话，并把结果保存到本地设置。
- 支持分类管理、按分类筛选、给单个会话归类。
- 支持删除会话；删除时会把原始 JSONL 移到 `%APPDATA%\SessionBridge\deleted-sessions`。
- 设置中可修改会话目录、OpenAI 兼容 Base URL、API Key 和模型名。
- 设置中可选择恢复参数：Codex 追加 `--ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=xhigh`，Claude 追加 `--dangerously-skip-permissions`。
- 默认预配置本机 OpenAI 兼容服务地址，不预设 API Key；首次使用 AI 分析前需要在设置中填写。

## 开发命令

```powershell
C:\Users\Administrator\develop\flutter\bin\flutter.bat analyze
C:\Users\Administrator\develop\flutter\bin\flutter.bat test
C:\Users\Administrator\develop\flutter\bin\flutter.bat build windows --release
```
