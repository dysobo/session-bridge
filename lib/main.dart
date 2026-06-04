import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const List<String> kAiSessionCategories = [
  '会话管理与 AI 助手工具',
  'AI 网关、模型与接口服务',
  '客户端应用开发',
  'Web 工具与前端页面',
  '业务系统与内容产品',
  '服务器部署与容器运维',
  '家庭网络、代理与影音服务',
  'Windows 本机维护与系统修复',
  '内容创作、图像/语音生成与写作',
  '硬件、Android 调试与设备接入',
  '咨询、方案与资料整理',
  '测试/无效/其它',
];

const String kFallbackAiCategory = '测试/无效/其它';

const Map<String, String> kAiSessionCategoryDescriptions = {
  '会话管理与 AI 助手工具': 'Session Bridge、Codex/Claude 配置、CLI 能力、会话恢复和本地 AI 助手工作流。',
  'AI 网关、模型与接口服务': 'new-api、CLIProxyAPI、OpenClaw、模型接入、API Key、模型可用性和接口配置。',
  '客户端应用开发': 'Flutter、Android、Windows 托盘、WinForms、桌面/移动客户端和播放器应用。',
  'Web 工具与前端页面': '单页工具、静态站点、前端页面、WebView 壳、项目展示页和浏览器插件。',
  '业务系统与内容产品': '考勤、StarKids、MoonTV/LunaTV、书签导航、项目产品化和业务功能迭代。',
  '服务器部署与容器运维': 'SSH、Docker、1Panel、Nginx、OpenResty、数据库、备份、迁移和远程部署。',
  '家庭网络、代理与影音服务': 'mihomo、Clash、DNS、PT/BT、NAS、Emby、Open WebUI、内网服务和影音链路。',
  'Windows 本机维护与系统修复': '磁盘清理、Microsoft Store、winget、环境变量、开发环境、系统组件修复。',
  '内容创作、图像/语音生成与写作': '小红书、小说编辑器、儿童漫画、AI 生图、语音识别、TTS 和创作流程。',
  '硬件、Android 调试与设备接入': 'ESP32、墨水屏、ADB、USB/OTG、手机调试、硬件驱动和设备连接。',
  '咨询、方案与资料整理': '副业建议、方案调研、文档整理、项目记录、知识迁移和非执行型咨询。',
  '测试/无效/其它': '初始问候、模型不可用、登录/访问测试、占位会话、中断会话，以及暂不适合其它分类的内容。',
};

typedef SyncUploadProgress =
    void Function(
      int done,
      int total,
      AgentSession session, {
      int? chunkIndex,
      int? chunkTotal,
    });

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SessionBridgeApp());
}

class SessionBridgeApp extends StatelessWidget {
  const SessionBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Session Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F8),
        visualDensity: VisualDensity.compact,
      ),
      home: const SessionHomePage(),
    );
  }
}

class SessionHomePage extends StatefulWidget {
  const SessionHomePage({super.key});

  @override
  State<SessionHomePage> createState() => _SessionHomePageState();
}

class _SessionHomePageState extends State<SessionHomePage> {
  AppSettings _settings = AppSettings.defaults();
  List<AgentSession> _sessions = const [];
  AgentSession? _selected;
  SessionSource? _filter;
  String? _categoryFilter;
  String _query = '';
  bool _loading = true;
  bool _analyzing = false;
  bool _analyzingAll = false;
  bool _syncing = false;
  int _analysisDone = 0;
  int _analysisTotal = 0;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<AgentSession> get _visibleSessions {
    final needle = _query.trim().toLowerCase();
    return _sessions.where((session) {
      if (_filter != null && session.source != _filter) {
        return false;
      }
      if (_categoryFilter != null && session.category != _categoryFilter) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      final haystack = [
        session.displayTitle,
        session.displaySummary,
        session.cwd,
        session.id,
        session.source.label,
        session.category,
        session.filePath,
      ].join('\n').toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      final settings = await AppSettings.load();
      final sessions = await SessionRepository(settings).scan();
      setState(() {
        _settings = settings;
        _sessions = sessions;
        _selected = _pickSelected(sessions);
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  AgentSession? _pickSelected(List<AgentSession> sessions) {
    if (sessions.isEmpty) {
      return null;
    }
    final currentKey = _selected?.key;
    if (currentKey != null) {
      for (final session in sessions) {
        if (session.key == currentKey) {
          return session;
        }
      }
    }
    return sessions.first;
  }

  Future<void> _showSettings() async {
    final updated = await showDialog<AppSettings>(
      context: context,
      builder: (context) => SettingsDialog(settings: _settings),
    );
    if (updated == null) {
      return;
    }
    await updated.save();
    await _load();
  }

  Future<void> _showAiCategoryOrganizer() async {
    if (_settings.apiKey.trim().isEmpty || _settings.baseUrl.trim().isEmpty) {
      setState(() {
        _status = '请先在设置中填写 Base URL 和 API Key。';
      });
      await _showSettings();
      return;
    }
    if (_sessions.isEmpty) {
      setState(() {
        _status = '没有可分类的会话。';
      });
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AiCategoryOrganizerPage(
          settings: _settings,
          sessions: _sessions,
          onApply: _applyAiCategoryPlan,
        ),
      ),
    );
  }

  Future<void> _applyAiCategoryPlan(
    AiCategoryPlan plan, {
    required bool replaceAll,
  }) async {
    final sessionKeys = _sessions.map((session) => session.key).toSet();
    final assignments = replaceAll
        ? <String, String>{}
        : Map<String, String>.from(_settings.categoryBySession);
    for (final assignment in plan.assignments) {
      if (!sessionKeys.contains(assignment.sessionKey)) {
        continue;
      }
      assignments[assignment.sessionKey] = assignment.category;
    }
    final updatedSettings = _settings.copyWith(
      categories: kAiSessionCategories,
      categoryBySession: assignments,
    );
    await updatedSettings.save();
    final updatedSessions = _sessions
        .map(
          (session) =>
              session.copyWith(category: assignments[session.key] ?? ''),
        )
        .toList();
    setState(() {
      _settings = updatedSettings;
      _sessions = updatedSessions;
      _selected = _pickSelected(updatedSessions);
      if (_categoryFilter != null &&
          !updatedSettings.categories.contains(_categoryFilter)) {
        _categoryFilter = null;
      }
      _status = replaceAll
          ? 'AI 分类已覆盖全部 ${plan.assignments.length} 个会话。'
          : 'AI 增量分类已应用 ${plan.assignments.length} 个会话。';
    });
  }

  Future<void> _restore(AgentSession session) async {
    final command = await showDialog<String>(
      context: context,
      builder: (context) => RestoreCommandDialog(session: session),
    );
    if (command == null) {
      return;
    }
    if (command.trim().isEmpty) {
      setState(() {
        _status = '恢复命令为空，已取消。';
      });
      return;
    }

    try {
      await SessionLauncher.restore(session, command.trim());
      setState(() {
        _status = '已打开 PowerShell 恢复窗口：${command.trim()}';
      });
    } catch (error) {
      setState(() {
        _status = '恢复失败：$error';
      });
    }
  }

  Future<void> _analyzeSelected() async {
    final session = _selected;
    if (session == null || _analyzing) {
      return;
    }
    if (_settings.apiKey.trim().isEmpty || _settings.baseUrl.trim().isEmpty) {
      setState(() {
        _status = '请先在设置中填写 Base URL 和 API Key。';
      });
      return;
    }

    setState(() {
      _analyzing = true;
      _status = '正在请求 AI 分析当前会话...';
    });

    try {
      final analysis = await OpenAiCompatibleAnalyzer(
        _settings,
      ).analyze(session);
      final updated = session.copyWith(
        aiTitle: analysis.title,
        aiSummary: analysis.summary,
        aiTags: analysis.tags,
      );
      final updatedSettings = _settings.withAnalysis(
        updated.key,
        StoredAnalysis(
          title: analysis.title,
          summary: analysis.summary,
          tags: analysis.tags,
        ),
      );
      await updatedSettings.save();
      setState(() {
        _settings = updatedSettings;
        _sessions = _sessions
            .map((item) => item.key == updated.key ? updated : item)
            .toList();
        _selected = updated;
        _analyzing = false;
        _status = 'AI 分析已更新当前会话摘要。';
      });
    } catch (error) {
      setState(() {
        _analyzing = false;
        _status = 'AI 分析失败：$error';
      });
    }
  }

  Future<void> _analyzeAllVisible() async {
    if (_analyzing || _analyzingAll) {
      return;
    }
    if (_settings.apiKey.trim().isEmpty || _settings.baseUrl.trim().isEmpty) {
      setState(() {
        _status = '请先在设置中填写 Base URL 和 API Key。';
      });
      return;
    }

    final targets = _sessions;
    if (targets.isEmpty) {
      setState(() {
        _status = '没有可分析的会话。';
      });
      return;
    }

    setState(() {
      _analyzingAll = true;
      _analysisDone = 0;
      _analysisTotal = targets.length;
      _status = '正在批量 AI 分析：0/${targets.length}';
    });

    var settings = _settings;
    var failures = 0;
    final analyzer = OpenAiCompatibleAnalyzer(_settings);
    for (final session in targets) {
      try {
        final analysis = await analyzer.analyze(session);
        final updated = session.copyWith(
          aiTitle: analysis.title,
          aiSummary: analysis.summary,
          aiTags: analysis.tags,
        );
        settings = settings.withAnalysis(
          updated.key,
          StoredAnalysis(
            title: analysis.title,
            summary: analysis.summary,
            tags: analysis.tags,
          ),
        );
        await settings.save();
        if (!mounted) {
          return;
        }
        setState(() {
          _settings = settings;
          _sessions = _sessions
              .map((item) => item.key == updated.key ? updated : item)
              .toList();
          if (_selected?.key == updated.key) {
            _selected = updated;
          }
          _analysisDone++;
          _status = '正在批量 AI 分析：$_analysisDone/$_analysisTotal';
        });
      } catch (_) {
        failures++;
        if (!mounted) {
          return;
        }
        setState(() {
          _analysisDone++;
          _status = '正在批量 AI 分析：$_analysisDone/$_analysisTotal，失败 $failures 个';
        });
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _analyzingAll = false;
      _status = failures == 0
          ? '批量 AI 分析完成：$_analysisTotal/$_analysisTotal。'
          : '批量 AI 分析完成：成功 ${_analysisTotal - failures} 个，失败 $failures 个。';
    });
  }

  Future<void> _showCategoryManager() async {
    final updated = await showDialog<AppSettings>(
      context: context,
      builder: (context) => CategoryDialog(settings: _settings),
    );
    if (updated == null) {
      return;
    }
    await updated.save();
    setState(() {
      _settings = updated;
      _sessions = _sessions
          .map(
            (session) => session.copyWith(
              category: updated.categoryBySession[session.key] ?? '',
            ),
          )
          .toList();
      _selected = _pickSelected(_sessions);
      if (_categoryFilter != null &&
          !updated.categories.contains(_categoryFilter)) {
        _categoryFilter = null;
      }
    });
  }

  Future<void> _setCategory(AgentSession session, String category) async {
    final updatedSettings = _settings.withCategory(session.key, category);
    await updatedSettings.save();
    final updated = session.copyWith(category: category);
    setState(() {
      _settings = updatedSettings;
      _sessions = _sessions
          .map((item) => item.key == updated.key ? updated : item)
          .toList();
      _selected = updated;
      _status = category.isEmpty ? '已取消分类。' : '已归类到：$category';
    });
  }

  Future<void> _deleteSession(AgentSession session) async {
    final confirmed = await _confirmDelete(session);
    if (confirmed != true) {
      return;
    }
    try {
      final deletedPath = await SessionTrash.moveToTrash(session);
      final updatedSettings = _settings.withoutSession(session.key);
      await updatedSettings.save();
      final remaining = _sessions
          .where((item) => item.key != session.key)
          .toList(growable: false);
      setState(() {
        _settings = updatedSettings;
        _sessions = remaining;
        _selected = _pickSelected(remaining);
        _status = '已删除会话，文件已移到：$deletedPath';
      });
    } catch (error) {
      setState(() {
        _status = '删除失败：$error';
      });
    }
  }

  bool get _hasSyncConfig {
    return _settings.syncServerUrl.trim().isNotEmpty &&
        _settings.syncAccount.trim().isNotEmpty &&
        _settings.syncKey.trim().isNotEmpty;
  }

  Future<void> _uploadSync() async {
    if (_syncing) {
      return;
    }
    if (!_hasSyncConfig) {
      setState(() {
        _status = '请先在设置中填写同步服务器、账号和同步密钥。';
      });
      await _showSettings();
      return;
    }
    setState(() {
      _syncing = true;
      _status = '正在上传同步数据...';
    });
    try {
      final result = await SessionSyncClient(_settings).upload(
        _sessions,
        onProgress: (done, total, session, {chunkIndex, chunkTotal}) {
          if (!mounted) {
            return;
          }
          setState(() {
            if (chunkIndex != null && chunkTotal != null) {
              _status =
                  '正在上传同步数据：${done + 1}/$total ${session.displayTitle}（分块 $chunkIndex/$chunkTotal）';
            } else {
              _status = '正在上传同步数据：$done/$total ${session.displayTitle}';
            }
          });
        },
      );
      setState(() {
        _syncing = false;
        _status =
            '上传同步完成：发送 ${result.sent} 个，服务端更新 ${result.updated} 个，跳过 ${result.skipped} 个。';
      });
    } catch (error) {
      setState(() {
        _syncing = false;
        _status = '上传同步失败：$error';
      });
    }
  }

  Future<void> _downloadSync() async {
    if (_syncing) {
      return;
    }
    if (!_hasSyncConfig) {
      setState(() {
        _status = '请先在设置中填写同步服务器、账号和同步密钥。';
      });
      await _showSettings();
      return;
    }
    setState(() {
      _syncing = true;
      _status = '正在下载同步数据...';
    });
    try {
      final result = await SessionSyncClient(_settings).download();
      final applyResult = await _applyDownloadedSessions(result.sessions);
      final status =
          '下载同步完成：远端 ${result.sessions.length} 个，写入 ${applyResult.written} 个，跳过 ${applyResult.skipped} 个。';
      await _load();
      setState(() {
        _syncing = false;
        _status = status;
      });
    } catch (error) {
      setState(() {
        _syncing = false;
        _status = '下载同步失败：$error';
      });
    }
  }

  Future<SyncApplyResult> _applyDownloadedSessions(
    List<SyncedSession> sessions,
  ) async {
    var written = 0;
    var skipped = 0;
    var settings = _settings;
    for (final session in sessions) {
      final relativePath = _safeRelativePath(session.relativePath);
      if (relativePath == null) {
        skipped++;
        continue;
      }
      final root = session.source == SessionSource.codex
          ? settings.codexRoot
          : settings.claudeRoot;
      final target = File(_joinPath(root, relativePath));
      final remoteBytes = base64Decode(session.fileContentBase64);
      if (await target.exists()) {
        final localBytes = await target.readAsBytes();
        if (base64Encode(localBytes) == session.fileContentBase64) {
          skipped++;
        } else {
          await _backupBeforeOverwrite(target);
          await target.writeAsBytes(remoteBytes, flush: true);
          written++;
        }
      } else {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(remoteBytes, flush: true);
        written++;
      }

      final localKey = '${session.source.name}:${session.id}:${target.path}';
      if (session.category.isNotEmpty) {
        settings = settings.withCategory(localKey, session.category);
      }
      if (session.aiTitle.isNotEmpty || session.aiSummary.isNotEmpty) {
        settings = settings.withAnalysis(
          localKey,
          StoredAnalysis(
            title: session.aiTitle,
            summary: session.aiSummary,
            tags: session.aiTags,
          ),
        );
      }
    }
    await settings.save();
    _settings = settings;
    return SyncApplyResult(written: written, skipped: skipped);
  }

  Future<void> _backupBeforeOverwrite(File file) async {
    final backupDir = Directory('${AppSettings.appDataDir}\\sync-backups');
    await backupDir.create(recursive: true);
    final backup = File(
      '${backupDir.path}\\${_timestampForFile(DateTime.now())}_${_basename(file.path)}',
    );
    await file.copy(backup.path);
  }

  Future<bool?> _confirmDelete(AgentSession session) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text(
          '确定删除这个 ${session.source.label} 会话？\n\n${session.displayTitle}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleSessions = _visibleSessions;
    final codexCount = _sessions
        .where((session) => session.source == SessionSource.codex)
        .length;
    final claudeCount = _sessions.length - codexCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Bridge'),
        actions: [
          TextButton.icon(
            onPressed: _loading || _analyzingAll || _syncing
                ? null
                : _analyzeAllVisible,
            icon: _analyzingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _analyzingAll ? '$_analysisDone/$_analysisTotal' : '全部 AI 分析',
            ),
          ),
          TextButton.icon(
            onPressed: _loading || _analyzingAll || _syncing
                ? null
                : _showAiCategoryOrganizer,
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('AI 分类整理'),
          ),
          TextButton.icon(
            onPressed: _loading || _syncing ? null : _uploadSync,
            icon: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: const Text('上传同步'),
          ),
          TextButton.icon(
            onPressed: _loading || _syncing ? null : _downloadSync,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('下载同步'),
          ),
          IconButton(
            tooltip: '分类管理',
            onPressed: _showCategoryManager,
            icon: const Icon(Icons.label_outline),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(
            query: _query,
            filter: _filter,
            totalCount: _sessions.length,
            codexCount: codexCount,
            claudeCount: claudeCount,
            categories: _settings.categories,
            categoryFilter: _categoryFilter,
            onQueryChanged: (value) => setState(() => _query = value),
            onFilterChanged: (value) => setState(() => _filter = value),
            onCategoryFilterChanged: (value) =>
                setState(() => _categoryFilter = value),
          ),
          if (_status != null)
            _StatusStrip(
              text: _status!,
              onClose: () => setState(() => _status = null),
            ),
          Expanded(
            child: _BodyLayout(
              loading: _loading,
              error: _error,
              sessions: visibleSessions,
              selected: _selected,
              analyzing: _analyzing || _analyzingAll,
              categories: _settings.categories,
              onSelect: (session) => setState(() => _selected = session),
              onRestore: _restore,
              onAnalyze: _analyzeSelected,
              onDelete: _deleteSession,
              onSetCategory: _setCategory,
              onManageCategories: _showCategoryManager,
              onRefresh: _load,
              onSettings: _showSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatefulWidget {
  const _Toolbar({
    required this.query,
    required this.filter,
    required this.totalCount,
    required this.codexCount,
    required this.claudeCount,
    required this.categories,
    required this.categoryFilter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onCategoryFilterChanged,
  });

  final String query;
  final SessionSource? filter;
  final int totalCount;
  final int codexCount;
  final int claudeCount;
  final List<String> categories;
  final String? categoryFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SessionSource?> onFilterChanged;
  final ValueChanged<String?> onCategoryFilterChanged;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _Toolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _queryController.text) {
      _queryController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final search = SizedBox(
            width: compact ? constraints.maxWidth : 360,
            child: TextField(
              controller: _queryController,
              onChanged: widget.onQueryChanged,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: '搜索会话、目录或内容',
                border: OutlineInputBorder(),
              ),
            ),
          );
          final sourceFilters = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('全部 ${widget.totalCount}'),
                selected: widget.filter == null,
                onSelected: (_) => widget.onFilterChanged(null),
              ),
              ChoiceChip(
                label: Text('Codex ${widget.codexCount}'),
                selected: widget.filter == SessionSource.codex,
                onSelected: (_) => widget.onFilterChanged(SessionSource.codex),
              ),
              ChoiceChip(
                label: Text('Claude ${widget.claudeCount}'),
                selected: widget.filter == SessionSource.claude,
                onSelected: (_) => widget.onFilterChanged(SessionSource.claude),
              ),
            ],
          );
          final categoryFilters = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部分类'),
                selected: widget.categoryFilter == null,
                onSelected: (_) => widget.onCategoryFilterChanged(null),
              ),
              ChoiceChip(
                label: const Text('未分类'),
                selected: widget.categoryFilter == '',
                onSelected: (_) => widget.onCategoryFilterChanged(''),
              ),
              ...widget.categories.map(
                (category) => ChoiceChip(
                  label: Text(category),
                  selected: widget.categoryFilter == category,
                  onSelected: (_) => widget.onCategoryFilterChanged(category),
                ),
              ),
            ],
          );
          final hint = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'AI 摘要可在详情页按需生成',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                search,
                const SizedBox(height: 10),
                sourceFilters,
                const SizedBox(height: 10),
                categoryFilters,
                const SizedBox(height: 8),
                hint,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  search,
                  const SizedBox(width: 16),
                  sourceFilters,
                  const Spacer(),
                  hint,
                ],
              ),
              const SizedBox(height: 10),
              categoryFilters,
            ],
          );
        },
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFEFF6FF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _BodyLayout extends StatelessWidget {
  const _BodyLayout({
    required this.loading,
    required this.error,
    required this.sessions,
    required this.selected,
    required this.analyzing,
    required this.categories,
    required this.onSelect,
    required this.onRestore,
    required this.onAnalyze,
    required this.onDelete,
    required this.onSetCategory,
    required this.onManageCategories,
    required this.onRefresh,
    required this.onSettings,
  });

  final bool loading;
  final String? error;
  final List<AgentSession> sessions;
  final AgentSession? selected;
  final bool analyzing;
  final List<String> categories;
  final ValueChanged<AgentSession> onSelect;
  final ValueChanged<AgentSession> onRestore;
  final VoidCallback onAnalyze;
  final ValueChanged<AgentSession> onDelete;
  final void Function(AgentSession session, String category) onSetCategory;
  final VoidCallback onManageCategories;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: '读取会话失败',
        detail: error!,
        actionLabel: '重试',
        onAction: onRefresh,
      );
    }
    if (sessions.isEmpty) {
      return _EmptyState(
        icon: Icons.folder_off_outlined,
        title: '没有找到会话',
        detail: '请检查设置中的 Codex 和 Claude 会话目录。',
        actionLabel: '打开设置',
        onAction: onSettings,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              SizedBox(
                height: 320,
                child: SessionList(
                  sessions: sessions,
                  selected: selected,
                  onSelect: onSelect,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SessionDetail(
                  session: selected,
                  analyzing: analyzing,
                  categories: categories,
                  onRestore: onRestore,
                  onAnalyze: onAnalyze,
                  onDelete: onDelete,
                  onSetCategory: onSetCategory,
                  onManageCategories: onManageCategories,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 430,
              child: SessionList(
                sessions: sessions,
                selected: selected,
                onSelect: onSelect,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: SessionDetail(
                session: selected,
                analyzing: analyzing,
                categories: categories,
                onRestore: onRestore,
                onAnalyze: onAnalyze,
                onDelete: onDelete,
                onSetCategory: onSetCategory,
                onManageCategories: onManageCategories,
              ),
            ),
          ],
        );
      },
    );
  }
}

class SessionList extends StatelessWidget {
  const SessionList({
    super.key,
    required this.sessions,
    required this.selected,
    required this.onSelect,
  });

  final List<AgentSession> sessions;
  final AgentSession? selected;
  final ValueChanged<AgentSession> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final selectedKey = selected?.key;
        return SessionListItem(
          session: session,
          selected: session.key == selectedKey,
          onTap: () => onSelect(session),
        );
      },
    );
  }
}

class SessionListItem extends StatelessWidget {
  const SessionListItem({
    super.key,
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final AgentSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : const Color(0xFFE5E7EB),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SourceChip(source: session.source),
                  if (session.category.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    CategoryChip(text: session.category),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.displayUpdatedAt,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                session.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                session.displaySummary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 15),
                  const SizedBox(width: 4),
                  Text('${session.messageCount} 条'),
                  const SizedBox(width: 12),
                  const Icon(Icons.folder_open_outlined, size: 15),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      session.cwd.isEmpty ? '-' : session.cwd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionDetail extends StatelessWidget {
  const SessionDetail({
    super.key,
    required this.session,
    required this.analyzing,
    required this.categories,
    required this.onRestore,
    required this.onAnalyze,
    required this.onDelete,
    required this.onSetCategory,
    required this.onManageCategories,
  });

  final AgentSession? session;
  final bool analyzing;
  final List<String> categories;
  final ValueChanged<AgentSession> onRestore;
  final VoidCallback onAnalyze;
  final ValueChanged<AgentSession> onDelete;
  final void Function(AgentSession session, String category) onSetCategory;
  final VoidCallback onManageCategories;

  @override
  Widget build(BuildContext context) {
    final current = session;
    if (current == null) {
      return const _EmptyState(
        icon: Icons.touch_app_outlined,
        title: '选择一个会话',
        detail: '左侧列表展示 Codex 和 Claude 的本机会话。',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SourceChip(source: current.source),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  current.displayTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => onRestore(current),
                icon: const Icon(Icons.terminal),
                label: const Text('恢复'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: analyzing ? null : onAnalyze,
                icon: analyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(analyzing ? '分析中' : 'AI 分析'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '删除会话',
                onPressed: () => onDelete(current),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              InfoPill(icon: Icons.fingerprint, text: current.id),
              InfoPill(icon: Icons.schedule, text: current.displayUpdatedAt),
              InfoPill(
                icon: Icons.message_outlined,
                text: '${current.messageCount} 条消息',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.label_outline, size: 18),
              const SizedBox(width: 8),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: current.category,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '分类',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未分类')),
                    ...categories.map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onSetCategory(current, value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onManageCategories,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('管理分类'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoLine(icon: Icons.folder_open_outlined, text: current.cwd),
          const SizedBox(height: 8),
          InfoLine(icon: Icons.description_outlined, text: current.filePath),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.summarize_outlined,
            text: current.aiSummary == null ? '内容概览' : 'AI 内容概览',
          ),
          const SizedBox(height: 8),
          SelectableText(
            current.displaySummary,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          if (current.aiTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: current.aiTags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 20),
          _SectionTitle(icon: Icons.history, text: '关键消息'),
          const SizedBox(height: 8),
          ...current.displayTurns.map(
            (turn) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TurnBlock(turn: turn),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(icon: Icons.terminal, text: '恢复命令'),
          const SizedBox(height: 8),
          SelectableText(
            current.restoreCommandPreview,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source});

  final SessionSource source;

  @override
  Widget build(BuildContext context) {
    final color = source == SessionSource.codex
        ? const Color(0xFF0F766E)
        : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(90)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          border: Border.all(color: const Color(0xFFBFDBFE)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            text.isEmpty ? '-' : text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _TurnBlock extends StatelessWidget {
  const _TurnBlock({required this.turn});

  final ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == 'user';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFFF0FDFA) : Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? '用户' : turn.roleLabel,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isUser ? const Color(0xFF0F766E) : const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            turn.text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF6B7280)),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class RestoreCommandDialog extends StatefulWidget {
  const RestoreCommandDialog({super.key, required this.session});

  final AgentSession session;

  @override
  State<RestoreCommandDialog> createState() => _RestoreCommandDialogState();
}

class _RestoreCommandDialogState extends State<RestoreCommandDialog> {
  late final TextEditingController _command;

  @override
  void initState() {
    super.initState();
    _command = TextEditingController(
      text: widget.session.restoreCommandPreview,
    );
  }

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认恢复命令'),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SourceChip(source: widget.session.source),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.session.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _command,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
              decoration: const InputDecoration(
                labelText: '即将在 PowerShell 中执行的命令',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_command.text),
          icon: const Icon(Icons.terminal),
          label: const Text('确认恢复'),
        ),
      ],
    );
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _codexRoot;
  late final TextEditingController _claudeRoot;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _syncServerUrl;
  late final TextEditingController _syncAccount;
  late final TextEditingController _syncKey;
  late bool _codexDangerousResume;
  late bool _claudeSkipPermissions;
  bool _obscureKey = true;
  bool _obscureSyncKey = true;

  @override
  void initState() {
    super.initState();
    _codexRoot = TextEditingController(text: widget.settings.codexRoot);
    _claudeRoot = TextEditingController(text: widget.settings.claudeRoot);
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _model = TextEditingController(text: widget.settings.model);
    _syncServerUrl = TextEditingController(text: widget.settings.syncServerUrl);
    _syncAccount = TextEditingController(text: widget.settings.syncAccount);
    _syncKey = TextEditingController(text: widget.settings.syncKey);
    _codexDangerousResume = widget.settings.codexDangerousResume;
    _claudeSkipPermissions = widget.settings.claudeSkipPermissions;
  }

  @override
  void dispose() {
    _codexRoot.dispose();
    _claudeRoot.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _syncServerUrl.dispose();
    _syncAccount.dispose();
    _syncKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_codexRoot, 'Codex 会话目录', Icons.folder_outlined),
              const SizedBox(height: 12),
              _field(_claudeRoot, 'Claude 会话目录', Icons.folder_outlined),
              const SizedBox(height: 20),
              _field(_baseUrl, 'OpenAI 兼容 Base URL', Icons.link),
              const SizedBox(height: 12),
              _field(_model, '模型', Icons.memory_outlined),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscureKey ? '显示' : '隐藏',
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    icon: Icon(
                      _obscureKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Codex 恢复使用高级权限参数'),
                subtitle: const Text(
                  '追加 --ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=xhigh',
                ),
                value: _codexDangerousResume,
                onChanged: (value) =>
                    setState(() => _codexDangerousResume = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Claude 恢复跳过权限确认'),
                subtitle: const Text('追加 --dangerously-skip-permissions'),
                value: _claudeSkipPermissions,
                onChanged: (value) =>
                    setState(() => _claudeSkipPermissions = value),
              ),
              const Divider(height: 28),
              _field(_syncServerUrl, '同步服务器 URL', Icons.cloud_outlined),
              const SizedBox(height: 12),
              _field(_syncAccount, '同步账号', Icons.person_outline),
              const SizedBox(height: 12),
              TextField(
                controller: _syncKey,
                obscureText: _obscureSyncKey,
                decoration: InputDecoration(
                  labelText: '同步密钥',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscureSyncKey ? '显示' : '隐藏',
                    onPressed: () =>
                        setState(() => _obscureSyncKey = !_obscureSyncKey),
                    icon: Icon(
                      _obscureSyncKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              AppSettings(
                codexRoot: _codexRoot.text.trim(),
                claudeRoot: _claudeRoot.text.trim(),
                baseUrl: _baseUrl.text.trim(),
                apiKey: _apiKey.text.trim(),
                model: _model.text.trim(),
                syncServerUrl: _syncServerUrl.text.trim(),
                syncAccount: _syncAccount.text.trim(),
                syncKey: _syncKey.text.trim(),
                codexDangerousResume: _codexDangerousResume,
                claudeSkipPermissions: _claudeSkipPermissions,
                categories: widget.settings.categories,
                categoryBySession: widget.settings.categoryBySession,
                analysisBySession: widget.settings.analysisBySession,
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class CategoryDialog extends StatefulWidget {
  const CategoryDialog({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<CategoryDialog> {
  late final TextEditingController _name;
  late List<String> _categories;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _categories = [...widget.settings.categories];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add() {
    final value = _name.text.trim();
    if (value.isEmpty || _categories.contains(value)) {
      return;
    }
    setState(() {
      _categories.add(value);
      _categories.sort();
      _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分类管理'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '新增分类',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: _categories.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无分类。'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.label_outline),
                          title: Text(category),
                          trailing: IconButton(
                            tooltip: '删除分类',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() {
                              _categories.removeAt(index);
                            }),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(
              context,
            ).pop(widget.settings.withCategories(_categories));
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
    );
  }
}

class AiCategoryOrganizerPage extends StatefulWidget {
  const AiCategoryOrganizerPage({
    super.key,
    required this.settings,
    required this.sessions,
    required this.onApply,
  });

  final AppSettings settings;
  final List<AgentSession> sessions;
  final Future<void> Function(AiCategoryPlan plan, {required bool replaceAll})
  onApply;

  @override
  State<AiCategoryOrganizerPage> createState() =>
      _AiCategoryOrganizerPageState();
}

class _AiCategoryOrganizerPageState extends State<AiCategoryOrganizerPage> {
  bool _loading = true;
  bool _applying = false;
  bool _applied = false;
  bool _fullRefresh = false;
  String? _error;
  AiCategoryPlan? _plan;

  @override
  void initState() {
    super.initState();
    _fullRefresh = !_hasStableAiCategories(widget.settings.categories);
    unawaited(_generate());
  }

  List<AgentSession> get _targets {
    if (_fullRefresh) {
      return widget.sessions;
    }
    return widget.sessions
        .where((session) => !kAiSessionCategories.contains(session.category))
        .toList(growable: false);
  }

  Future<void> _generate({bool? fullRefresh}) async {
    if (fullRefresh != null) {
      _fullRefresh = fullRefresh;
    }
    final targets = _targets;
    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
      _applied = false;
    });
    if (targets.isEmpty) {
      setState(() {
        _loading = false;
        _plan = AiCategoryPlan.fromExisting(widget.sessions);
        _applied = true;
      });
      return;
    }
    try {
      final plan = await OpenAiCompatibleAnalyzer(
        widget.settings,
      ).classifySessions(targets, fullRefresh: _fullRefresh);
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _plan = plan;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null || _applying || _applied) {
      return;
    }
    setState(() {
      _applying = true;
    });
    try {
      await widget.onApply(plan, replaceAll: _fullRefresh);
      if (!mounted) {
        return;
      }
      setState(() {
        _applying = false;
        _applied = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _applying = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final targets = _targets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 分类整理'),
        actions: [
          if (!_loading)
            TextButton.icon(
              onPressed: () => _generate(fullRefresh: true),
              icon: const Icon(Icons.replay_outlined),
              label: const Text('重新全量分类'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _fullRefresh
                        ? '正在基于全部 ${targets.length} 个会话生成分类页面...'
                        : '正在增量归类 ${targets.length} 个新会话...',
                  ),
                ],
              ),
            )
          : _error != null
          ? _EmptyState(
              icon: Icons.error_outline,
              title: 'AI 分类失败',
              detail: _error!,
              actionLabel: '重试',
              onAction: _generate,
            )
          : plan == null
          ? const _EmptyState(
              icon: Icons.category_outlined,
              title: '没有分类结果',
              detail: '当前没有需要展示的 AI 分类结果。',
            )
          : Column(
              children: [
                Expanded(
                  child: _AiCategoryPlanView(
                    plan: plan,
                    sessions: widget.sessions,
                    fullRefresh: _fullRefresh,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fullRefresh
                              ? '应用后会替换为新的 12 类，并覆盖全部会话分类。'
                              : '应用后只写入本次增量归类结果，既有分类保持不变。',
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _loading || _applying
                            ? null
                            : () => _generate(fullRefresh: false),
                        icon: const Icon(Icons.playlist_add_check_outlined),
                        label: const Text('只归类新增'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _applied || _applying ? null : _apply,
                        icon: _applying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt_outlined),
                        label: Text(_applied ? '已应用' : '一键应用'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _AiCategoryPlanView extends StatelessWidget {
  const _AiCategoryPlanView({
    required this.plan,
    required this.sessions,
    required this.fullRefresh,
  });

  final AiCategoryPlan plan;
  final List<AgentSession> sessions;
  final bool fullRefresh;

  @override
  Widget build(BuildContext context) {
    final sessionByKey = {for (final session in sessions) session.key: session};
    final counts = plan.countsByCategory;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fullRefresh
                    ? Icons.account_tree_outlined
                    : Icons.playlist_add_check_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fullRefresh ? '全量分类结果' : '增量分类结果',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text('共 ${plan.assignments.length} 个会话'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fullRefresh
                ? '这套分类用于替换旧的粗分类，后续新增会话会继续归入这些分类。'
                : '当前分类体系保持不变，本页只展示需要新增归类的会话。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: plan.categories.map((category) {
              return Container(
                width: 280,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        CategoryChip(text: '${counts[category] ?? 0}'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.categoryDescriptions[category] ??
                          kAiSessionCategoryDescriptions[category] ??
                          '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          ...plan.categories.map((category) {
            final items = plan.assignmentsFor(category);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ExpansionTile(
                initiallyExpanded: items.isNotEmpty,
                title: Text('$category (${items.length})'),
                subtitle: Text(
                  plan.categoryDescriptions[category] ??
                      kAiSessionCategoryDescriptions[category] ??
                      '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                children: items.map((assignment) {
                  final session = sessionByKey[assignment.sessionKey];
                  return ListTile(
                    dense: true,
                    leading: session == null
                        ? const Icon(Icons.help_outline)
                        : SourceChip(source: session.source),
                    title: Text(
                      session?.displayTitle ?? assignment.sessionKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      assignment.reason.isEmpty
                          ? 'AI 已归入此类。'
                          : assignment.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: session == null
                        ? null
                        : Text(
                            session.displayUpdatedAt,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                  );
                }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }
}

enum SessionSource { codex, claude }

extension SessionSourceLabel on SessionSource {
  String get label => switch (this) {
    SessionSource.codex => 'Codex',
    SessionSource.claude => 'Claude',
  };
}

class StoredAnalysis {
  const StoredAnalysis({
    required this.title,
    required this.summary,
    required this.tags,
  });

  final String title;
  final String summary;
  final List<String> tags;

  Map<String, Object> toJson() {
    return {'title': title, 'summary': summary, 'tags': tags};
  }

  static StoredAnalysis? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final title = _stringOrNull(value['title']);
    final summary = _stringOrNull(value['summary']);
    if (title == null && summary == null) {
      return null;
    }
    final tagsValue = value['tags'];
    final tags = tagsValue is List
        ? tagsValue
              .whereType<String>()
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .take(6)
              .toList()
        : <String>[];
    return StoredAnalysis(
      title: title ?? '',
      summary: summary ?? '',
      tags: tags,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.codexRoot,
    required this.claudeRoot,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.syncServerUrl,
    required this.syncAccount,
    required this.syncKey,
    required this.codexDangerousResume,
    required this.claudeSkipPermissions,
    required this.categories,
    required this.categoryBySession,
    required this.analysisBySession,
  });

  final String codexRoot;
  final String claudeRoot;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String syncServerUrl;
  final String syncAccount;
  final String syncKey;
  final bool codexDangerousResume;
  final bool claudeSkipPermissions;
  final List<String> categories;
  final Map<String, String> categoryBySession;
  final Map<String, StoredAnalysis> analysisBySession;

  factory AppSettings.defaults() {
    final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    return AppSettings(
      codexRoot: '$home\\.codex\\sessions',
      claudeRoot: '$home\\.claude\\projects',
      baseUrl: 'http://192.168.0.16:3001/',
      apiKey: '',
      model: 'deepseek-chat',
      syncServerUrl: '',
      syncAccount: '',
      syncKey: '',
      codexDangerousResume: false,
      claudeSkipPermissions: false,
      categories: kAiSessionCategories,
      categoryBySession: const {},
      analysisBySession: const {},
    );
  }

  static File get configFile {
    return File('$appDataDir\\settings.json');
  }

  static String get appDataDir {
    final appData =
        Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE'] ?? Directory.current.path}\\AppData\\Roaming';
    return '$appData\\SessionBridge';
  }

  static Future<AppSettings> load() async {
    final defaults = AppSettings.defaults();
    final file = configFile;
    if (!await file.exists()) {
      return defaults;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return defaults;
    }
    return AppSettings(
      codexRoot: _settingString(decoded['codexRoot'], defaults.codexRoot),
      claudeRoot: _settingString(decoded['claudeRoot'], defaults.claudeRoot),
      baseUrl: _settingString(decoded['baseUrl'], defaults.baseUrl),
      apiKey: _settingString(decoded['apiKey'], defaults.apiKey),
      model: _settingString(decoded['model'], defaults.model),
      syncServerUrl: _settingString(
        decoded['syncServerUrl'],
        defaults.syncServerUrl,
      ),
      syncAccount: _settingString(decoded['syncAccount'], defaults.syncAccount),
      syncKey: _settingString(decoded['syncKey'], defaults.syncKey),
      codexDangerousResume: _boolSetting(
        decoded['codexDangerousResume'],
        defaults.codexDangerousResume,
      ),
      claudeSkipPermissions: _boolSetting(
        decoded['claudeSkipPermissions'],
        defaults.claudeSkipPermissions,
      ),
      categories: _stringList(decoded['categories'], defaults.categories),
      categoryBySession: _stringMap(decoded['categoryBySession']),
      analysisBySession: _analysisMap(decoded['analysisBySession']),
    );
  }

  Future<void> save() async {
    final file = configFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'codexRoot': codexRoot,
        'claudeRoot': claudeRoot,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'syncServerUrl': syncServerUrl,
        'syncAccount': syncAccount,
        'syncKey': syncKey,
        'codexDangerousResume': codexDangerousResume,
        'claudeSkipPermissions': claudeSkipPermissions,
        'categories': categories,
        'categoryBySession': categoryBySession,
        'analysisBySession': analysisBySession.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      }),
    );
  }

  AppSettings copyWith({
    String? codexRoot,
    String? claudeRoot,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? syncServerUrl,
    String? syncAccount,
    String? syncKey,
    bool? codexDangerousResume,
    bool? claudeSkipPermissions,
    List<String>? categories,
    Map<String, String>? categoryBySession,
    Map<String, StoredAnalysis>? analysisBySession,
  }) {
    return AppSettings(
      codexRoot: codexRoot ?? this.codexRoot,
      claudeRoot: claudeRoot ?? this.claudeRoot,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      syncServerUrl: syncServerUrl ?? this.syncServerUrl,
      syncAccount: syncAccount ?? this.syncAccount,
      syncKey: syncKey ?? this.syncKey,
      codexDangerousResume: codexDangerousResume ?? this.codexDangerousResume,
      claudeSkipPermissions:
          claudeSkipPermissions ?? this.claudeSkipPermissions,
      categories: categories ?? this.categories,
      categoryBySession: categoryBySession ?? this.categoryBySession,
      analysisBySession: analysisBySession ?? this.analysisBySession,
    );
  }

  AppSettings withAnalysis(String key, StoredAnalysis analysis) {
    return copyWith(analysisBySession: {...analysisBySession, key: analysis});
  }

  AppSettings withCategory(String key, String category) {
    final updated = {...categoryBySession};
    if (category.trim().isEmpty) {
      updated.remove(key);
    } else {
      updated[key] = category.trim();
    }
    return copyWith(categoryBySession: updated);
  }

  AppSettings withCategories(List<String> values) {
    final normalized =
        values
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final allowed = normalized.toSet();
    final updatedAssignments = Map<String, String>.fromEntries(
      categoryBySession.entries.where((entry) => allowed.contains(entry.value)),
    );
    return copyWith(
      categories: normalized,
      categoryBySession: updatedAssignments,
    );
  }

  AppSettings withoutSession(String key) {
    final categories = {...categoryBySession}..remove(key);
    final analyses = {...analysisBySession}..remove(key);
    return copyWith(categoryBySession: categories, analysisBySession: analyses);
  }

  static String _settingString(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static bool _boolSetting(Object? value, bool fallback) {
    if (value is bool) {
      return value;
    }
    return fallback;
  }

  static List<String> _stringList(Object? value, List<String> fallback) {
    if (value is! List) {
      return fallback;
    }
    final result =
        value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return result;
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return value.map((key, value) {
      return MapEntry(key.toString(), value.toString().trim());
    })..removeWhere((key, value) => key.isEmpty || value.isEmpty);
  }

  static Map<String, StoredAnalysis> _analysisMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    final result = <String, StoredAnalysis>{};
    for (final entry in value.entries) {
      final analysis = StoredAnalysis.fromJson(entry.value);
      if (analysis != null) {
        result[entry.key.toString()] = analysis;
      }
    }
    return result;
  }
}

class AgentSession {
  const AgentSession({
    required this.source,
    required this.id,
    required this.filePath,
    this.relativePath = '',
    required this.cwd,
    required this.title,
    required this.summary,
    required this.updatedAt,
    required this.messageCount,
    required this.turns,
    this.createdAt,
    this.aiTitle,
    this.aiSummary,
    this.aiTags = const [],
    this.category = '',
    this.codexDangerousResume = false,
    this.claudeSkipPermissions = false,
  });

  final SessionSource source;
  final String id;
  final String filePath;
  final String relativePath;
  final String cwd;
  final String title;
  final String summary;
  final DateTime? createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final List<ChatTurn> turns;
  final String? aiTitle;
  final String? aiSummary;
  final List<String> aiTags;
  final String category;
  final bool codexDangerousResume;
  final bool claudeSkipPermissions;

  String get key => '${source.name}:$id:$filePath';
  String get displayTitle => _clip((aiTitle ?? title).trim(), 160);
  String get displaySummary => _clip((aiSummary ?? summary).trim(), 900);
  String get displayUpdatedAt => _formatDateTime(updatedAt);

  List<ChatTurn> get displayTurns {
    if (turns.length <= 10) {
      return turns;
    }
    return [...turns.take(5), ...turns.skip(turns.length - 5)];
  }

  String get restoreCommandPreview {
    final quotedCwd = _quotePowerShell(cwd.isEmpty ? _homeDir : cwd);
    final quotedId = _quotePowerShell(id);
    final command = switch (source) {
      SessionSource.codex =>
        codexDangerousResume
            ? 'codex resume --ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=xhigh $quotedId'
            : 'codex resume $quotedId',
      SessionSource.claude =>
        claudeSkipPermissions
            ? 'claude --dangerously-skip-permissions --resume $quotedId'
            : 'claude --resume $quotedId',
    };
    return 'Set-Location -LiteralPath $quotedCwd; $command';
  }

  String get promptContext {
    final buffer = StringBuffer()
      ..writeln('Source: ${source.label}')
      ..writeln('Session ID: $id')
      ..writeln('CWD: $cwd')
      ..writeln('Updated: $displayUpdatedAt')
      ..writeln();
    for (final turn in turns.take(24)) {
      buffer
        ..writeln('${turn.roleLabel}:')
        ..writeln(_clip(turn.text, 1200))
        ..writeln();
    }
    return _clip(buffer.toString(), 12000);
  }

  String categoryContext(String ref) {
    final firstUser = turns
        .where((turn) => turn.role != 'assistant')
        .firstOrNull;
    final lastUser = turns.where((turn) => turn.role != 'assistant').lastOrNull;
    final lastAssistant = turns
        .where((turn) => turn.role == 'assistant')
        .lastOrNull;
    final buffer = StringBuffer()
      ..writeln('Ref: $ref')
      ..writeln('Source: ${source.label}')
      ..writeln('Title: $displayTitle')
      ..writeln('Category: ${category.isEmpty ? '未分类' : category}')
      ..writeln('CWD: $cwd')
      ..writeln('Updated: $displayUpdatedAt')
      ..writeln('Messages: $messageCount')
      ..writeln('Tags: ${aiTags.join(', ')}')
      ..writeln('Summary: ${_clip(displaySummary, 520)}');
    if (firstUser != null) {
      buffer.writeln('FirstUser: ${_clip(firstUser.text, 220)}');
    }
    if (lastUser != null && lastUser != firstUser) {
      buffer.writeln('LastUser: ${_clip(lastUser.text, 220)}');
    }
    if (lastAssistant != null) {
      buffer.writeln('LastAssistant: ${_clip(lastAssistant.text, 220)}');
    }
    return _clip(buffer.toString(), 1400);
  }

  AgentSession copyWith({
    String? aiTitle,
    String? aiSummary,
    List<String>? aiTags,
    String? category,
    bool? codexDangerousResume,
    bool? claudeSkipPermissions,
  }) {
    return AgentSession(
      source: source,
      id: id,
      filePath: filePath,
      relativePath: relativePath,
      cwd: cwd,
      title: title,
      summary: summary,
      createdAt: createdAt,
      updatedAt: updatedAt,
      messageCount: messageCount,
      turns: turns,
      aiTitle: aiTitle ?? this.aiTitle,
      aiSummary: aiSummary ?? this.aiSummary,
      aiTags: aiTags ?? this.aiTags,
      category: category ?? this.category,
      codexDangerousResume: codexDangerousResume ?? this.codexDangerousResume,
      claudeSkipPermissions:
          claudeSkipPermissions ?? this.claudeSkipPermissions,
    );
  }
}

class ChatTurn {
  const ChatTurn({required this.role, required this.text, this.timestamp});

  final String role;
  final String text;
  final DateTime? timestamp;

  String get roleLabel {
    return switch (role) {
      'user' => '用户',
      'assistant' => '助手',
      'developer' => '目标',
      _ => role,
    };
  }
}

class SessionRepository {
  const SessionRepository(this.settings);

  final AppSettings settings;

  Future<List<AgentSession>> scan() async {
    final sessions = <AgentSession>[
      ...await _scanCodex(),
      ...await _scanClaude(),
    ];
    final enriched = sessions.map(_applyStoredData).toList();
    enriched.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return enriched;
  }

  AgentSession _applyStoredData(AgentSession session) {
    final analysis = settings.analysisBySession[session.key];
    return session.copyWith(
      aiTitle: _stringOrNull(analysis?.title),
      aiSummary: _stringOrNull(analysis?.summary),
      aiTags: analysis?.tags,
      category: settings.categoryBySession[session.key] ?? '',
      codexDangerousResume: settings.codexDangerousResume,
      claudeSkipPermissions: settings.claudeSkipPermissions,
    );
  }

  Future<List<AgentSession>> _scanCodex() async {
    final root = Directory(settings.codexRoot);
    if (!await root.exists()) {
      return const [];
    }
    final sessions = <AgentSession>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !_isJsonl(entity.path)) {
        continue;
      }
      final session = await _parseCodexFile(entity);
      if (session != null) {
        sessions.add(session);
      }
    }
    return sessions;
  }

  Future<List<AgentSession>> _scanClaude() async {
    final root = Directory(settings.claudeRoot);
    if (!await root.exists()) {
      return const [];
    }
    final sessions = <AgentSession>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !_isJsonl(entity.path)) {
        continue;
      }
      final session = await _parseClaudeFile(entity);
      if (session != null) {
        sessions.add(session);
      }
    }
    return sessions;
  }

  Future<AgentSession?> _parseCodexFile(File file) async {
    String? id;
    String cwd = '';
    DateTime? createdAt;
    final turns = <ChatTurn>[];
    var messageCount = 0;

    try {
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) {
          continue;
        }
        final record = jsonDecode(line);
        if (record is! Map<String, dynamic>) {
          continue;
        }
        final timestamp = _parseTimestamp(record['timestamp']);
        final type = record['type'];
        if (type == 'session_meta') {
          final payload = record['payload'];
          if (payload is Map<String, dynamic>) {
            id ??= _stringOrNull(payload['id']);
            cwd = _stringOrNull(payload['cwd']) ?? cwd;
            createdAt ??= _parseTimestamp(payload['timestamp']);
          }
          continue;
        }
        if (type != 'response_item') {
          continue;
        }
        final payload = record['payload'];
        if (payload is! Map<String, dynamic> || payload['type'] != 'message') {
          continue;
        }
        final role = _stringOrNull(payload['role']) ?? '';
        if (role != 'user' && role != 'assistant' && role != 'developer') {
          continue;
        }
        var text = _extractContentText(payload['content']);
        text = _meaningfulCodexText(text);
        if (text.isEmpty) {
          continue;
        }
        messageCount++;
        turns.add(
          ChatTurn(role: role, text: _clip(text, 2200), timestamp: timestamp),
        );
      }
    } catch (_) {
      return null;
    }

    final stat = await file.stat();
    id ??= _uuidFromPath(file.path) ?? _basenameWithoutExtension(file.path);
    final cleanTurns = _dedupeTurns(turns);
    return AgentSession(
      source: SessionSource.codex,
      id: id,
      filePath: file.path,
      relativePath: _relativePath(settings.codexRoot, file.path),
      cwd: cwd,
      title: _buildTitle(cleanTurns, id),
      summary: _buildSummary(cleanTurns),
      createdAt: createdAt,
      updatedAt: stat.modified,
      messageCount: messageCount,
      turns: cleanTurns,
    );
  }

  Future<AgentSession?> _parseClaudeFile(File file) async {
    String? id;
    String cwd = '';
    DateTime? createdAt;
    final turns = <ChatTurn>[];
    var messageCount = 0;

    try {
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) {
          continue;
        }
        final record = jsonDecode(line);
        if (record is! Map<String, dynamic>) {
          continue;
        }
        id ??= _stringOrNull(record['sessionId']);
        cwd = _stringOrNull(record['cwd']) ?? cwd;
        final timestamp = _parseTimestamp(record['timestamp']);
        createdAt ??= timestamp;
        final type = _stringOrNull(record['type']) ?? '';
        if (type != 'user' && type != 'assistant') {
          continue;
        }
        final message = record['message'];
        if (message is! Map<String, dynamic>) {
          continue;
        }
        final role = _stringOrNull(message['role']) ?? type;
        final text = _meaningfulClaudeText(
          _extractContentText(message['content']),
        );
        if (text.isEmpty) {
          continue;
        }
        messageCount++;
        turns.add(
          ChatTurn(role: role, text: _clip(text, 2200), timestamp: timestamp),
        );
      }
    } catch (_) {
      return null;
    }

    final stat = await file.stat();
    id ??= _uuidFromPath(file.path) ?? _basenameWithoutExtension(file.path);
    final cleanTurns = _dedupeTurns(turns);
    return AgentSession(
      source: SessionSource.claude,
      id: id,
      filePath: file.path,
      relativePath: _relativePath(settings.claudeRoot, file.path),
      cwd: cwd,
      title: _buildTitle(cleanTurns, id),
      summary: _buildSummary(cleanTurns),
      createdAt: createdAt,
      updatedAt: stat.modified,
      messageCount: messageCount,
      turns: cleanTurns,
    );
  }
}

class SessionLauncher {
  const SessionLauncher._();

  static Future<void> restore(AgentSession session, String command) async {
    final cwd = session.cwd.isEmpty ? _homeDir : session.cwd;
    await Process.start(
      'cmd.exe',
      [
        '/c',
        'start',
        'Session Bridge',
        'powershell.exe',
        '-NoExit',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
      workingDirectory: Directory(cwd).existsSync() ? cwd : _homeDir,
      mode: ProcessStartMode.detached,
    );
  }
}

class SessionTrash {
  const SessionTrash._();

  static Future<String> moveToTrash(AgentSession session) async {
    final source = File(session.filePath);
    if (!await source.exists()) {
      throw Exception('源文件不存在：${session.filePath}');
    }
    final root = Directory('${AppSettings.appDataDir}\\deleted-sessions');
    final targetDir = Directory('${root.path}\\${session.source.name}');
    await targetDir.create(recursive: true);
    final target = File(
      '${targetDir.path}\\${_timestampForFile(DateTime.now())}_${_basename(session.filePath)}',
    );
    try {
      await source.rename(target.path);
    } catch (_) {
      await source.copy(target.path);
      await source.delete();
    }
    return target.path;
  }
}

class SessionSyncClient {
  const SessionSyncClient(this.settings);

  final AppSettings settings;
  static const int _chunkUploadThreshold = 512 * 1024;
  static const int _chunkSize = 256 * 1024;

  Future<SyncUploadResult> upload(
    List<AgentSession> sessions, {
    SyncUploadProgress? onProgress,
  }) async {
    var sent = 0;
    var updated = 0;
    var skipped = 0;
    var done = 0;
    final total = sessions.length;
    for (final session in sessions) {
      final file = File(session.filePath);
      if (!await file.exists()) {
        skipped++;
        done++;
        onProgress?.call(done, total, session);
        continue;
      }
      final bytes = await file.readAsBytes();
      final decoded = await _uploadSession(
        session,
        bytes,
        done,
        total,
        onProgress,
      );
      sent += _intValue(decoded['sent']);
      updated += _intValue(decoded['updated']);
      skipped += _intValue(decoded['skipped']);
      done++;
      onProgress?.call(done, total, session);
    }
    return SyncUploadResult(sent: sent, updated: updated, skipped: skipped);
  }

  Future<Map<String, dynamic>> _uploadSession(
    AgentSession session,
    List<int> bytes,
    int done,
    int total,
    SyncUploadProgress? onProgress,
  ) async {
    final compressed = gzip.encode(bytes);
    if (compressed.length <= _chunkUploadThreshold) {
      onProgress?.call(done, total, session, chunkIndex: 1, chunkTotal: 1);
      return _postJson('/api/upload', {
        'sessions': [
          {
            ..._sessionPayload(session),
            'fileContentGzipBase64': base64Encode(compressed),
          },
        ],
      });
    }

    final uploadId =
        '${session.source.name}-${session.id}-${session.updatedAt.microsecondsSinceEpoch}-${session.relativePath.hashCode}'
            .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    final totalChunks = (compressed.length / _chunkSize).ceil();
    Map<String, dynamic> decoded = const {};
    for (var index = 0; index < totalChunks; index++) {
      onProgress?.call(
        done,
        total,
        session,
        chunkIndex: index + 1,
        chunkTotal: totalChunks,
      );
      final start = index * _chunkSize;
      final end = (start + _chunkSize) > compressed.length
          ? compressed.length
          : start + _chunkSize;
      decoded = await _postJson('/api/upload-chunk', {
        'session': {
          ..._sessionPayload(session),
          'uploadId': uploadId,
          'chunkIndex': index,
          'chunkTotal': totalChunks,
          'chunkDataBase64': base64Encode(compressed.sublist(start, end)),
        },
      });
    }
    return decoded;
  }

  Map<String, Object?> _sessionPayload(AgentSession session) {
    return {
      'source': session.source.name,
      'sessionId': session.id,
      'relativePath': session.relativePath,
      'cwd': session.cwd,
      'title': session.title,
      'summary': session.summary,
      'aiTitle': session.aiTitle ?? '',
      'aiSummary': session.aiSummary ?? '',
      'aiTags': session.aiTags,
      'category': session.category,
      'updatedAt': session.updatedAt.toUtc().toIso8601String(),
      'messageCount': session.messageCount,
    };
  }

  Future<SyncDownloadResult> download() async {
    final decoded = await _postJson('/api/download', const {});
    final rawSessions = decoded['sessions'];
    final sessions = rawSessions is List
        ? rawSessions
              .map(SyncedSession.fromJson)
              .whereType<SyncedSession>()
              .toList()
        : <SyncedSession>[];
    return SyncDownloadResult(sessions: sessions);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await _postJsonOnce(path, body);
      } on SocketException {
        if (attempt == 3) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on TimeoutException {
        if (attempt == 3) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw const SocketException('同步请求失败');
  }

  Future<Map<String, dynamic>> _postJsonOnce(
    String path,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final data = utf8.encode(
        jsonEncode({
          'account': settings.syncAccount.trim(),
          'syncKey': settings.syncKey.trim(),
          'deviceName': Platform.localHostname,
          ...body,
        }),
      );
      final request = await client
          .postUrl(_syncUri(settings.syncServerUrl, path))
          .timeout(const Duration(seconds: 20));
      request.persistentConnection = false;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.contentLengthHeader, data.length);
      request.add(data);
      final response = await request.close().timeout(
        const Duration(seconds: 120),
      );
      final responseBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'HTTP ${response.statusCode}: ${_clip(responseBody, 260)}',
        );
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const FormatException('同步服务响应不是 JSON 对象');
    } finally {
      client.close(force: true);
    }
  }
}

class SyncUploadResult {
  const SyncUploadResult({
    required this.sent,
    required this.updated,
    required this.skipped,
  });

  final int sent;
  final int updated;
  final int skipped;
}

class SyncDownloadResult {
  const SyncDownloadResult({required this.sessions});

  final List<SyncedSession> sessions;
}

class SyncApplyResult {
  const SyncApplyResult({required this.written, required this.skipped});

  final int written;
  final int skipped;
}

class SyncedSession {
  const SyncedSession({
    required this.source,
    required this.id,
    required this.relativePath,
    required this.fileContentBase64,
    required this.title,
    required this.summary,
    required this.aiTitle,
    required this.aiSummary,
    required this.aiTags,
    required this.category,
  });

  final SessionSource source;
  final String id;
  final String relativePath;
  final String fileContentBase64;
  final String title;
  final String summary;
  final String aiTitle;
  final String aiSummary;
  final List<String> aiTags;
  final String category;

  String get key => '${source.name}:$id:${_joinPath('', relativePath)}';

  static SyncedSession? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final sourceName = _stringOrNull(value['source']);
    final source = switch (sourceName) {
      'codex' => SessionSource.codex,
      'claude' => SessionSource.claude,
      _ => null,
    };
    final id = _stringOrNull(value['sessionId']);
    final relativePath = _stringOrNull(value['relativePath']);
    final content = _stringOrNull(value['fileContentBase64']);
    if (source == null ||
        id == null ||
        relativePath == null ||
        content == null) {
      return null;
    }
    final tagsValue = value['aiTags'];
    final tags = tagsValue is List
        ? tagsValue
              .whereType<String>()
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .take(8)
              .toList()
        : <String>[];
    return SyncedSession(
      source: source,
      id: id,
      relativePath: relativePath,
      fileContentBase64: content,
      title: _stringOrNull(value['title']) ?? '',
      summary: _stringOrNull(value['summary']) ?? '',
      aiTitle: _stringOrNull(value['aiTitle']) ?? '',
      aiSummary: _stringOrNull(value['aiSummary']) ?? '',
      aiTags: tags,
      category: _stringOrNull(value['category']) ?? '',
    );
  }
}

class AiCategoryPlan {
  const AiCategoryPlan({
    required this.categories,
    required this.categoryDescriptions,
    required this.assignments,
  });

  final List<String> categories;
  final Map<String, String> categoryDescriptions;
  final List<AiCategoryAssignment> assignments;

  Map<String, int> get countsByCategory {
    final result = {for (final category in categories) category: 0};
    for (final assignment in assignments) {
      result[assignment.category] = (result[assignment.category] ?? 0) + 1;
    }
    return result;
  }

  List<AiCategoryAssignment> assignmentsFor(String category) {
    return assignments
        .where((assignment) => assignment.category == category)
        .toList(growable: false);
  }

  static AiCategoryPlan fromExisting(List<AgentSession> sessions) {
    return AiCategoryPlan(
      categories: kAiSessionCategories,
      categoryDescriptions: kAiSessionCategoryDescriptions,
      assignments: sessions
          .map(
            (session) => AiCategoryAssignment(
              sessionKey: session.key,
              category: _normalizeAiCategory(session.category),
              reason: session.category.isEmpty ? '尚未分类，暂放兜底分类。' : '已有分类。',
            ),
          )
          .toList(growable: false),
    );
  }

  static AiCategoryPlan fromAiContent(
    String content,
    List<AgentSession> sessions, {
    bool includeMissing = true,
  }) {
    final stripped = _stripCodeFence(content);
    Object? decoded;
    try {
      decoded = jsonDecode(stripped);
    } catch (_) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(stripped);
      if (match != null) {
        decoded = jsonDecode(match.group(0)!);
      }
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 分类响应不是 JSON 对象');
    }

    final descriptions = Map<String, String>.from(
      kAiSessionCategoryDescriptions,
    );
    final rawCategories = decoded['categories'];
    if (rawCategories is List) {
      for (final raw in rawCategories) {
        if (raw is String) {
          final category = _normalizeAiCategory(raw);
          descriptions.putIfAbsent(category, () => '');
        } else if (raw is Map) {
          final category = _normalizeAiCategory(
            _stringOrNull(raw['name']) ?? _stringOrNull(raw['category']) ?? '',
          );
          final description =
              _stringOrNull(raw['description']) ??
              _stringOrNull(raw['overview']) ??
              _stringOrNull(raw['summary']);
          if (description != null) {
            descriptions[category] = _clip(description, 120);
          }
        }
      }
    }

    final sessionsByRef = <String, AgentSession>{};
    for (var index = 0; index < sessions.length; index++) {
      sessionsByRef[_sessionRef(index)] = sessions[index];
    }

    final bySessionKey = <String, AiCategoryAssignment>{};
    final rawAssignments = decoded['assignments'];
    if (rawAssignments is List) {
      for (final raw in rawAssignments) {
        if (raw is! Map) {
          continue;
        }
        final ref =
            _stringOrNull(raw['ref']) ??
            _stringOrNull(raw['sessionRef']) ??
            _stringOrNull(raw['id']);
        if (ref == null) {
          continue;
        }
        final session = sessionsByRef[ref];
        if (session == null) {
          continue;
        }
        final category = _normalizeAiCategory(
          _stringOrNull(raw['category']) ?? '',
        );
        bySessionKey[session.key] = AiCategoryAssignment(
          sessionKey: session.key,
          category: category,
          reason: _clip(_stringOrNull(raw['reason']) ?? 'AI 自动归类。', 90),
        );
      }
    }

    if (includeMissing) {
      for (final session in sessions) {
        bySessionKey.putIfAbsent(
          session.key,
          () => AiCategoryAssignment(
            sessionKey: session.key,
            category: kFallbackAiCategory,
            reason: 'AI 未返回分类，已放入兜底分类。',
          ),
        );
      }
    }

    final assignments = bySessionKey.values.toList(growable: false)
      ..sort((a, b) {
        final categoryOrder =
            kAiSessionCategories.indexOf(a.category) -
            kAiSessionCategories.indexOf(b.category);
        if (categoryOrder != 0) {
          return categoryOrder;
        }
        return a.sessionKey.compareTo(b.sessionKey);
      });

    return AiCategoryPlan(
      categories: kAiSessionCategories,
      categoryDescriptions: descriptions,
      assignments: assignments,
    );
  }
}

class AiCategoryAssignment {
  const AiCategoryAssignment({
    required this.sessionKey,
    required this.category,
    required this.reason,
  });

  final String sessionKey;
  final String category;
  final String reason;
}

class OpenAiCompatibleAnalyzer {
  const OpenAiCompatibleAnalyzer(this.settings);

  final AppSettings settings;

  Future<AiAnalysis> analyze(AgentSession session) async {
    final content = await _complete(
      [
        {
          'role': 'system',
          'content':
              '你是会话整理助手。请用简体中文总结 Codex/Claude 会话，返回严格 JSON：'
              '{"title":"短标题","projectDescription":"项目/任务是什么，用一句话说明目标和背景",'
              '"mainFeatures":["功能或需求1","功能或需求2"],'
              '"contentOverview":"本次会话涉及的核心内容、文件、服务或关键对象，用2到3句概括",'
              '"conversationHighlights":["用户主要要求或关键对话1","用户主要要求或关键对话2"],'
              '"progressOverview":"当前完成度、已完成事项、阻塞或下一步，用2到3句概括",'
              '"tags":["标签"]}。'
              '内容要简明、直观、偏项目管理视角。不要返回 Markdown 表格。'
              'mainFeatures 和 conversationHighlights 各最多 5 条。',
        },
        {'role': 'user', 'content': session.promptContext},
      ],
      maxTokens: 700,
      timeout: const Duration(seconds: 90),
    );
    return _parseAiAnalysis(content, session);
  }

  Future<AiCategoryPlan> classifySessions(
    List<AgentSession> sessions, {
    required bool fullRefresh,
  }) async {
    if (sessions.isEmpty) {
      return const AiCategoryPlan(
        categories: kAiSessionCategories,
        categoryDescriptions: kAiSessionCategoryDescriptions,
        assignments: [],
      );
    }
    final content = await _complete(
      [
        {
          'role': 'system',
          'content':
              '你是会话分类架构师。请把 Codex/Claude 会话归入固定分类，返回严格 JSON。'
              '只能使用给定分类，不要新增、改名或删除分类。'
              '返回格式：{"categories":[{"name":"分类名","description":"分类说明"}],'
              '"assignments":[{"ref":"S001","category":"分类名","reason":"不超过30字的归类理由"}]}。'
              '必须为用户提供的每个 ref 返回一条 assignments。'
              '初始问候、模型不可用、登录测试、占位、中断、无明确任务的会话归入“测试/无效/其它”。'
              '如果不确定，也归入“测试/无效/其它”。不要返回 Markdown。',
        },
        {
          'role': 'user',
          'content': _categoryPrompt(sessions, fullRefresh: fullRefresh),
        },
      ],
      maxTokens: 6000,
      timeout: const Duration(seconds: 180),
    );
    return AiCategoryPlan.fromAiContent(content, sessions);
  }

  Future<String> _complete(
    List<Map<String, String>> messages, {
    required int maxTokens,
    required Duration timeout,
  }) async {
    final uri = _chatCompletionsUri(settings.baseUrl);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${settings.apiKey.trim()}',
      );
      request.write(
        jsonEncode({
          'model': settings.model.trim().isEmpty
              ? 'deepseek-chat'
              : settings.model.trim(),
          'temperature': 0.1,
          'max_tokens': maxTokens,
          'messages': messages,
        }),
      );
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${_clip(body, 240)}');
      }
      return extractAiMessage(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }

  String _categoryPrompt(
    List<AgentSession> sessions, {
    required bool fullRefresh,
  }) {
    final buffer = StringBuffer()
      ..writeln(fullRefresh ? '模式：首次全量分类' : '模式：增量分类')
      ..writeln('会话数量：${sessions.length}')
      ..writeln()
      ..writeln('固定分类：');
    for (final category in kAiSessionCategories) {
      buffer.writeln(
        '- $category：${kAiSessionCategoryDescriptions[category] ?? ''}',
      );
    }
    buffer
      ..writeln()
      ..writeln('会话清单：');
    for (var index = 0; index < sessions.length; index++) {
      buffer
        ..writeln()
        ..writeln(sessions[index].categoryContext(_sessionRef(index)));
    }
    return _clip(buffer.toString(), 90000);
  }

  static String extractAiMessage(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 响应不是 JSON 对象');
    }
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw const FormatException('AI 响应 choices 格式异常');
      }
      final message = first['message'];
      if (message is Map<String, dynamic>) {
        final content = _extractContentText(message['content']);
        if (content.isNotEmpty) {
          return content;
        }
        final reasoningContent = _extractContentText(
          message['reasoning_content'],
        );
        if (reasoningContent.isNotEmpty) {
          return reasoningContent;
        }
      }
      final text = _extractContentText(first['text']);
      if (text.isNotEmpty) {
        return text;
      }
      final delta = first['delta'];
      if (delta is Map<String, dynamic>) {
        final content = _extractContentText(delta['content']);
        if (content.isNotEmpty) {
          return content;
        }
      }
    }

    final outputText = _extractContentText(decoded['output_text']);
    if (outputText.isNotEmpty) {
      return outputText;
    }
    final output = decoded['output'];
    if (output is List) {
      final content = _extractContentText(output);
      if (content.isNotEmpty) {
        return content;
      }
    }
    final anthropicContent = _extractContentText(decoded['content']);
    if (anthropicContent.isNotEmpty) {
      return anthropicContent;
    }
    throw const FormatException('AI 响应缺少正文');
  }

  static AiAnalysis _parseAiAnalysis(String content, AgentSession fallback) {
    final stripped = _stripCodeFence(content);
    Object? decoded;
    try {
      decoded = jsonDecode(stripped);
    } catch (_) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(stripped);
      if (match != null) {
        decoded = jsonDecode(match.group(0)!);
      }
    }
    if (decoded is Map<String, dynamic>) {
      final tagsValue = decoded['tags'];
      final tags = tagsValue is List
          ? tagsValue
                .whereType<String>()
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .take(6)
                .toList()
          : <String>[];
      final summary =
          _structuredAiSummary(decoded) ??
          _stringOrNull(decoded['summary']) ??
          stripped;
      return AiAnalysis(
        title: _stringOrNull(decoded['title']) ?? fallback.displayTitle,
        summary: summary,
        tags: tags,
      );
    }
    return AiAnalysis(
      title: fallback.displayTitle,
      summary: stripped,
      tags: const [],
    );
  }

  static String? _structuredAiSummary(Map<String, dynamic> decoded) {
    final description = _stringOrNull(decoded['projectDescription']);
    final featuresValue = decoded['mainFeatures'];
    final features = featuresValue is List
        ? featuresValue
              .whereType<String>()
              .map((feature) => feature.trim())
              .where((feature) => feature.isNotEmpty)
              .take(5)
              .toList()
        : <String>[];
    final contentOverview = _stringOrNull(decoded['contentOverview']);
    final highlightsValue = decoded['conversationHighlights'];
    final highlights = highlightsValue is List
        ? highlightsValue
              .whereType<String>()
              .map((highlight) => highlight.trim())
              .where((highlight) => highlight.isNotEmpty)
              .take(5)
              .toList()
        : <String>[];
    final progress = _stringOrNull(decoded['progressOverview']);
    if (description == null &&
        features.isEmpty &&
        contentOverview == null &&
        highlights.isEmpty &&
        progress == null) {
      return null;
    }

    final parts = <String>[];
    if (description != null) {
      parts.add('项目描述：\n$description');
    }
    if (features.isNotEmpty) {
      parts.add('主要功能：\n${features.map((feature) => '- $feature').join('\n')}');
    }
    if (contentOverview != null) {
      parts.add('内容概要：\n$contentOverview');
    }
    if (highlights.isNotEmpty) {
      parts.add(
        '主要对话摘要：\n${highlights.map((highlight) => '- $highlight').join('\n')}',
      );
    }
    if (progress != null) {
      parts.add('进度概览：\n$progress');
    }
    return parts.join('\n\n');
  }
}

class AiAnalysis {
  const AiAnalysis({
    required this.title,
    required this.summary,
    required this.tags,
  });

  final String title;
  final String summary;
  final List<String> tags;
}

Uri _chatCompletionsUri(String rawBaseUrl) {
  final clean = rawBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final base = Uri.parse(clean.isEmpty ? 'http://127.0.0.1:3001' : clean);
  final path = base.path.endsWith('/v1')
      ? '${base.path}/chat/completions'
      : '${base.path}/v1/chat/completions';
  return base.replace(path: path);
}

Uri _syncUri(String rawBaseUrl, String apiPath) {
  final clean = rawBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final base = Uri.parse(clean.isEmpty ? 'http://127.0.0.1:18080' : clean);
  final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
  return base.replace(path: '$basePath$apiPath');
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

bool _hasStableAiCategories(List<String> categories) {
  final current = categories.map((category) => category.trim()).toSet();
  return kAiSessionCategories.every(current.contains);
}

String _sessionRef(int index) {
  return 'S${(index + 1).toString().padLeft(3, '0')}';
}

String _normalizeAiCategory(String category) {
  final clean = category.trim();
  if (kAiSessionCategories.contains(clean)) {
    return clean;
  }
  return kFallbackAiCategory;
}

List<ChatTurn> _dedupeTurns(List<ChatTurn> turns) {
  final result = <ChatTurn>[];
  String? previous;
  for (final turn in turns) {
    final normalized = '${turn.role}:${turn.text}';
    if (normalized == previous) {
      continue;
    }
    result.add(turn);
    previous = normalized;
  }
  return result;
}

String _buildTitle(List<ChatTurn> turns, String fallback) {
  for (final turn in turns) {
    if (turn.role != 'assistant' && turn.text.trim().isNotEmpty) {
      return _clip(_firstMeaningfulLine(turn.text), 90);
    }
  }
  for (final turn in turns) {
    if (turn.text.trim().isNotEmpty) {
      return _clip(_firstMeaningfulLine(turn.text), 90);
    }
  }
  return fallback;
}

String _buildSummary(List<ChatTurn> turns) {
  if (turns.isEmpty) {
    return '未解析到可展示的用户或助手消息。';
  }
  final firstUser = turns.where((turn) => turn.role != 'assistant').firstOrNull;
  final lastUser = turns.where((turn) => turn.role != 'assistant').lastOrNull;
  final lastAssistant = turns
      .where((turn) => turn.role == 'assistant')
      .lastOrNull;
  final parts = <String>[];
  if (firstUser != null) {
    parts.add('起始：${_clip(firstUser.text, 220)}');
  }
  if (lastUser != null && lastUser != firstUser) {
    parts.add('最近目标：${_clip(lastUser.text, 220)}');
  }
  if (lastAssistant != null) {
    parts.add('最近进展：${_clip(lastAssistant.text, 260)}');
  }
  return parts.join('\n');
}

String _extractContentText(Object? content) {
  if (content == null) {
    return '';
  }
  if (content is String) {
    return _cleanText(content);
  }
  if (content is List) {
    return content
        .map(_extractContentText)
        .where((text) => text.isNotEmpty)
        .join('\n');
  }
  if (content is Map<String, dynamic>) {
    final type = _stringOrNull(content['type']);
    if (type == 'thinking' || type == 'tool_use' || type == 'image') {
      return '';
    }
    final text =
        _stringOrNull(content['text']) ??
        _stringOrNull(content['input_text']) ??
        _stringOrNull(content['output_text']);
    if (text != null) {
      return _cleanText(text);
    }
    return _extractContentText(content['content']);
  }
  return '';
}

String _meaningfulCodexText(String text) {
  final clean = _cleanText(text);
  if (clean.isEmpty) {
    return '';
  }
  final objective = RegExp(
    r'<untrusted_objective>\s*([\s\S]*?)\s*</untrusted_objective>',
    multiLine: true,
  ).firstMatch(text);
  if (objective != null) {
    return _cleanText(objective.group(1)!);
  }
  if (clean.contains('# AGENTS.md instructions') ||
      clean.contains('<environment_context>') ||
      clean.contains('<permissions instructions>') ||
      clean.contains('<skills_instructions>') ||
      clean.contains('You are Codex, a coding agent')) {
    return '';
  }
  return clean;
}

String _meaningfulClaudeText(String text) {
  final clean = _cleanText(text);
  if (clean.isEmpty) {
    return '';
  }
  if (clean.contains('skill_listing') || clean.contains('Use this skill to')) {
    return '';
  }
  return clean;
}

String _firstMeaningfulLine(String text) {
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final clean = line.trim();
    if (clean.isNotEmpty && !clean.startsWith('#')) {
      return clean;
    }
  }
  return _cleanText(text);
}

String _cleanText(String text) {
  return text
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _clip(String text, int maxLength) {
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength).trimRight()}...';
}

DateTime? _parseTimestamp(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

String? _stringOrNull(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

bool _isJsonl(String path) => path.toLowerCase().endsWith('.jsonl');

String _basenameWithoutExtension(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

String _relativePath(String root, String path) {
  final normalizedRoot = root
      .replaceAll('/', '\\')
      .replaceFirst(RegExp(r'\\+$'), '');
  final normalizedPath = path.replaceAll('/', '\\');
  final rootLower = normalizedRoot.toLowerCase();
  final pathLower = normalizedPath.toLowerCase();
  if (pathLower == rootLower) {
    return _basename(normalizedPath);
  }
  if (pathLower.startsWith('$rootLower\\')) {
    return normalizedPath.substring(normalizedRoot.length + 1);
  }
  return _basename(normalizedPath);
}

String _joinPath(String root, String relativePath) {
  final cleanRoot = root
      .replaceAll('/', '\\')
      .replaceFirst(RegExp(r'\\+$'), '');
  final cleanRelative = relativePath
      .replaceAll('/', '\\')
      .replaceFirst(RegExp(r'^\\+'), '');
  if (cleanRoot.isEmpty) {
    return cleanRelative;
  }
  return '$cleanRoot\\$cleanRelative';
}

String? _safeRelativePath(String relativePath) {
  final normalized = relativePath.replaceAll('/', '\\').trim();
  if (normalized.isEmpty ||
      normalized.startsWith('\\') ||
      RegExp(r'^[a-zA-Z]:\\').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized.split('\\');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return normalized;
}

String _timestampForFile(DateTime dateTime) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}${two(dateTime.month)}${two(dateTime.day)}_'
      '${two(dateTime.hour)}${two(dateTime.minute)}${two(dateTime.second)}';
}

String? _uuidFromPath(String path) {
  final match = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  ).firstMatch(path);
  return match?.group(0);
}

String _formatDateTime(DateTime dateTime) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} '
      '${two(dateTime.hour)}:${two(dateTime.minute)}';
}

String _quotePowerShell(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _stripCodeFence(String content) {
  var text = content.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }
  return text.trim();
}

String get _homeDir =>
    Platform.environment['USERPROFILE'] ?? Directory.current.path;

extension FirstLastOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }

  T? get lastOrNull {
    T? value;
    var found = false;
    for (final item in this) {
      value = item;
      found = true;
    }
    return found ? value : null;
  }
}
