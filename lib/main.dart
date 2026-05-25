import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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
            onPressed: _loading || _analyzingAll ? null : _analyzeAllVisible,
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 360,
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
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('全部 ${widget.totalCount}'),
                  selected: widget.filter == null,
                  onSelected: (_) => widget.onFilterChanged(null),
                ),
                ChoiceChip(
                  label: Text('Codex ${widget.codexCount}'),
                  selected: widget.filter == SessionSource.codex,
                  onSelected: (_) =>
                      widget.onFilterChanged(SessionSource.codex),
                ),
                ChoiceChip(
                  label: Text('Claude ${widget.claudeCount}'),
                  selected: widget.filter == SessionSource.claude,
                  onSelected: (_) =>
                      widget.onFilterChanged(SessionSource.claude),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Wrap(
              spacing: 8,
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
            ),
            const SizedBox(width: 24),
            const Icon(Icons.bolt_outlined, size: 18),
            const SizedBox(width: 6),
            Text(
              'AI 摘要可在详情页按需生成',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w700,
          fontSize: 12,
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
  late bool _codexDangerousResume;
  late bool _claudeSkipPermissions;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _codexRoot = TextEditingController(text: widget.settings.codexRoot);
    _claudeRoot = TextEditingController(text: widget.settings.claudeRoot);
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _model = TextEditingController(text: widget.settings.model);
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
      codexDangerousResume: false,
      claudeSkipPermissions: false,
      categories: const ['待处理', '开发', '运维', '资料'],
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

class OpenAiCompatibleAnalyzer {
  const OpenAiCompatibleAnalyzer(this.settings);

  final AppSettings settings;

  Future<AiAnalysis> analyze(AgentSession session) async {
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
          'temperature': 0.2,
          'max_tokens': 700,
          'messages': [
            {
              'role': 'system',
              'content':
                  '你是会话整理助手。请用简体中文总结 Codex/Claude 会话，返回严格 JSON：'
                  '{"title":"短标题","projectDescription":"项目描述，用一小段说明目标和背景",'
                  '"mainFeatures":["主要功能1","主要功能2"],'
                  '"progressOverview":"进度概览，用一小段说明已完成、当前状态和待办",'
                  '"tags":["标签"]}。'
                  '内容要简明清晰。不要返回 Markdown 表格。mainFeatures 最多 5 条。',
            },
            {'role': 'user', 'content': session.promptContext},
          ],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${_clip(body, 240)}');
      }
      final content = _extractAiMessage(jsonDecode(body));
      return _parseAiAnalysis(content, session);
    } finally {
      client.close(force: true);
    }
  }

  static String _extractAiMessage(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 响应不是 JSON 对象');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('AI 响应缺少 choices');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('AI 响应 choices 格式异常');
    }
    final message = first['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
    }
    final text = first['text'];
    if (text is String && text.trim().isNotEmpty) {
      return text.trim();
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
    final progress = _stringOrNull(decoded['progressOverview']);
    if (description == null && features.isEmpty && progress == null) {
      return null;
    }

    final parts = <String>[];
    if (description != null) {
      parts.add('项目描述：\n$description');
    }
    if (features.isNotEmpty) {
      parts.add('主要功能：\n${features.map((feature) => '- $feature').join('\n')}');
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
