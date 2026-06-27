# Session Bridge

Windows 桌面工具，用于集中查看本机 Codex / Claude 会话，按需生成 AI 摘要，并通过 PowerShell 或 Codex Win 一键恢复会话。

## 运行

Release 程序位于：

```text
build\windows\x64\runner\Release\session_bridge.exe
```

## 功能

- 自动扫描 `%USERPROFILE%\.codex\sessions` 和 `%USERPROFILE%\.claude\projects`。
- Qmby 风格工作台界面，左侧集中放置常用操作，主区展示搜索、筛选、列表和详情。
- 列表展示会话来源、更新时间、工作目录、主要内容和关键消息。
- 点击“恢复”可选择 PowerShell 或 Codex Win；PowerShell 保留可编辑命令，Codex Win 使用 `codex://threads/<session-id>` 打开本地线程，不修改 Codex Win 配置。
- 点击“全部 AI 分析”会顺序分析全部会话，并把结果保存到本地设置。
- AI 内容概览按“项目描述 / 主要功能 / 内容概要 / 主要对话摘要 / 进度概览”整理。
- 点击“AI 分类整理”会基于全部会话生成分类结果页，首轮覆盖旧分类；后续可只把新增会话增量归入现有分类。
- AI 响应解析兼容 OpenAI 字符串正文、OpenAI content blocks 和 Anthropic 风格 content blocks。
- 支持分类管理、按分类筛选、给单个会话归类。
- 支持删除会话；删除时会把原始 JSONL 移到 `%APPDATA%\SessionBridge\deleted-sessions`。
- 支持配置同步服务器、账号和同步密钥，手动上传/下载同步 Codex/Claude 原始会话文件、AI 摘要和分类。
- 上传同步会按会话分块上传，并压缩原始 JSONL，避免大量历史会话一次性上传失败。
- 下载同步会先拉取轻量列表，可选择全量同步，也可在清单中单独恢复指定会话；实际内容仍按会话分块下载。
- 设置中可修改会话目录、OpenAI 兼容 Base URL、API Key 和模型名。
- 设置中可选择恢复参数：Codex 追加 `--ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=xhigh`，Claude 追加 `--dangerously-skip-permissions`。
- 默认使用本机 OpenAI 兼容服务地址，不预设 API Key；首次使用 AI 分析前需要在设置中填写。

## 同步服务

同步服务器是一个 HTTP JSON API 服务，不是数据库直连地址。客户端只访问这个 HTTP 服务；SQLite 数据库文件由服务端程序在服务器内部读写。

内置的 `sync_server/session_bridge_sync_server.py` 可部署到自有服务器，默认监听 `18080`，使用 SQLite 保存结构化会话数据。服务端只依赖 Python 标准库。

客户端不预设同步服务器地址。同步服务器、账号和同步密钥需要在设置中手动填写。

服务端默认不开放自助注册；账号需要先在服务端创建，同一个账号后续必须使用相同同步密钥。

### 服务端搭建

本机测试：

```powershell
python sync_server\session_bridge_sync_server.py --host 127.0.0.1 --port 18080 --db .\session_bridge_sync.sqlite
```

Linux 服务器示例：

```bash
sudo mkdir -p /opt/session-bridge-sync
sudo cp sync_server/session_bridge_sync_server.py /opt/session-bridge-sync/
python3 /opt/session-bridge-sync/session_bridge_sync_server.py \
  --db /opt/session-bridge-sync/session_bridge_sync.sqlite \
  --provision-account your-account \
  --provision-key 'replace-with-a-long-random-sync-key'
python3 /opt/session-bridge-sync/session_bridge_sync_server.py \
  --host 0.0.0.0 \
  --port 18080 \
  --db /opt/session-bridge-sync/session_bridge_sync.sqlite
```

生产环境建议放到 systemd、Docker 或进程守护工具中运行，并通过 Nginx/Caddy/OpenResty 反向代理到 HTTPS。默认不要设置 `SESSION_BRIDGE_ALLOW_SIGNUP`，这样未预置账号会返回 `403`。

健康检查：

```text
GET http://your-host:18080/api/health
```

返回 `{"ok": true, "service": "session-bridge-sync"}` 即表示服务可用。

### 客户端填写

打开设置后填写：

- 同步服务器 URL：同步服务 HTTP 根地址，例如 `http://your-host:18080` 或反代后的 `https://sync.example.com`。不要填写 SQLite 路径，也通常不要在末尾加 `/api`。
- 同步账号：服务端 `--provision-account` 预置的账号。
- 同步密钥：服务端 `--provision-key` 预置的密钥。

使用步骤：

1. 打开设置，填写同步服务器 URL、同步账号和同步密钥。
2. 点击“上传同步”把当前机器的 Codex/Claude 会话、AI 摘要和分类上传到服务器。
3. 在另一台机器填入同一账号和密钥后点击“下载同步”，可选择全量同步或单独恢复指定会话。远端 JSONL 会写回对应会话目录；覆盖前会备份到 `%APPDATA%\SessionBridge\sync-backups`。

服务端接口：

- `GET /api/health`
- `POST /api/upload`
- `POST /api/upload-chunk`
- `POST /api/download`
- `POST /api/download-list`
- `POST /api/download-chunk`

## 开发命令

```powershell
C:\Users\Administrator\develop\flutter\bin\flutter.bat analyze
C:\Users\Administrator\develop\flutter\bin\flutter.bat test
C:\Users\Administrator\develop\flutter\bin\flutter.bat build windows --release
```
