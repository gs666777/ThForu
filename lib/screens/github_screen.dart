import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/provider_config.dart';
import '../state/providers.dart';
import '../services/ai_service.dart';

class _RepoFile {
  final String path;
  final String? content;
  final String language;
  final int size;
  _RepoFile({required this.path, this.content, required this.language, required this.size});
}

class _ChatMsg {
  final String role;
  final String content;
  _ChatMsg({required this.role, required this.content});
}

class _ScoredFile {
  final String repo;
  final Map<String, dynamic> file;
  final int score;
  _ScoredFile({required this.repo, required this.file, required this.score});
}

class _TreeNode {
  final String name;
  final String fullPath;
  final bool isDir;
  Map<String, dynamic>? file;
  final Map<String, _TreeNode> children = {};
  _TreeNode({required this.name, required this.isDir, this.file, this.fullPath = ''});
  int get descendantFileCount {
    int count = 0;
    for (final child in children.values) {
      if (!child.isDir) count++;
      else count += child.descendantFileCount;
    }
    return count;
  }
}

class GitHubScreen extends ConsumerStatefulWidget {
  const GitHubScreen({super.key});
  @override
  ConsumerState<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends ConsumerState<GitHubScreen> {
  List<Map<String, dynamic>> _repos = [];
  String? _activeRepoId;
  bool _loading = true;
  String? _connectingStatus;
  List<_RepoFile> _files = [];
  bool _showingTree = false;
  _RepoFile? _selectedFile;
  String _fileSearchQuery = '';
  String _selectedCodeText = '';
  bool _showChat = false;
  final _chatInputCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  final List<_ChatMsg> _chatMessages = [];
  bool _chatStreaming = false;
  AIProviderConfig? _chatProvider;
  final Set<String> _collapsedFolders = {};
  bool _showFileSearch = false;
  final _fileSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _fileSearchResults = [];

  static const _codeExtensions = {
    'dart','java','kt','py','js','ts','jsx','tsx','c','cpp','h','hpp',
    'cs','go','rs','swift','rb','php','html','css','scss','json','yaml','yml','xml','md','sql','sh',
  };

  String _detectLang(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'dart':'Dart','java':'Java','kt':'Kotlin','py':'Python','js':'JS','ts':'TS',
      'jsx':'JSX','tsx':'TSX','c':'C','cpp':'C++','h':'Header','cs':'C#','go':'Go',
      'rs':'Rust','swift':'Swift','rb':'Ruby','php':'PHP','html':'HTML','css':'CSS',
      'scss':'SCSS','json':'JSON','yaml':'YAML','yml':'YAML','xml':'XML','md':'MD',
      'sql':'SQL','sh':'Shell',
    };
    return map[ext] ?? ext.toUpperCase();
  }

  // ==================== Chat History Persistence ====================

  String get _chatHistoryKey {
    final ids = _repos.where((r) => r['status'] == 'done').map((r) => r['id'] as String).toList()..sort();
    return 'github_chat_${ids.join("_")}';
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_chatHistoryKey);
    if (json != null) {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      setState(() {
        _chatMessages.clear();
        _chatMessages.addAll(list.map((m) => _ChatMsg(role: m['role'] as String, content: m['content'] as String)));
      });
    }
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = _chatMessages.length > 50 ? _chatMessages.sublist(_chatMessages.length - 50) : _chatMessages;
    final json = jsonEncode(trimmed.map((m) => {'role': m.role, 'content': m.content}).toList());
    await prefs.setString(_chatHistoryKey, json);
  }

  // ==================== State ====================

  @override
  void initState() {
    super.initState();
    _loadRepos();
    _loadChatHistory();
  }

  @override
  void dispose() {
    _saveChatHistory();
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    _fileSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('github_repos');
    final activeId = prefs.getString('github_active_repo_id');
    if (json != null) {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      final valid = list.where((r) => r['files'] != null && (r['files'] as List).isNotEmpty && r['status'] == 'done').toList();
      final removedCount = list.length - valid.length;
      if (removedCount > 0) await prefs.setString('github_repos', jsonEncode(valid));
      String? validActiveId = activeId;
      if (validActiveId != null && !valid.any((r) => r['id'] == validActiveId)) {
        validActiveId = null;
        await prefs.remove('github_active_repo_id');
      }
      if (mounted) setState(() { _repos = valid; _activeRepoId = validActiveId; _loading = false; });
    } else if (mounted) setState(() { _loading = false; });
  }

  // ==================== Repo Management ====================

  Future<void> _connectRepo() async {
    final ownerCtrl = TextEditingController();
    final repoCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('连接 GitHub 仓库'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ownerCtrl, decoration: const InputDecoration(hintText: '用户名', labelText: 'Owner')),
          const SizedBox(height: 8),
          TextField(controller: repoCtrl, decoration: const InputDecoration(hintText: '仓库名', labelText: 'Repo')),
          const SizedBox(height: 8),
          TextField(controller: tokenCtrl, decoration: const InputDecoration(hintText: '公开仓库可不填', labelText: 'Token (可选)'), obscureText: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            if (ownerCtrl.text.isNotEmpty && repoCtrl.text.isNotEmpty) {
              Navigator.pop(ctx, {'owner': ownerCtrl.text.trim(), 'repo': repoCtrl.text.trim(), 'token': tokenCtrl.text.trim()});
            }
          }, child: const Text('连接')),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _connectingStatus = '正在连接...');
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 30)));
      final headers = <String, String>{'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'ThForu'};
      final token = result['token'] ?? '';
      if (token.isNotEmpty) headers['Authorization'] = 'token $token';
      final owner = result['owner']!;
      final repo = result['repo']!;
      String branch = 'main';
      Response mainResp;
      Response? masterResp;
      try {
        mainResp = await dio.get('https://api.github.com/repos/$owner/$repo/git/trees/main?recursive=1', options: Options(headers: headers));
      } catch (_) {
        mainResp = Response(requestOptions: RequestOptions(path: ''), statusCode: 0);
      }
      if (mainResp.statusCode != 200) {
        try {
          masterResp = await dio.get('https://api.github.com/repos/$owner/$repo/git/trees/master?recursive=1', options: Options(headers: headers));
        } catch (_) {
          masterResp = Response(requestOptions: RequestOptions(path: ''), statusCode: 0);
        }
        if (masterResp.statusCode == 200) branch = 'master';
      }
      final treeResp = branch == 'master' ? masterResp! : mainResp;
      if (treeResp.statusCode == 401) throw Exception('Token 无效，请检查后重试');
      if (treeResp.statusCode == 403) throw Exception('API 速率限制，请填写 Token');
      if (treeResp.statusCode == 404) throw Exception('仓库不存在或无访问权限');
      if (treeResp.statusCode == 0) throw Exception('网络连接失败，请检查网络');
      if (treeResp.statusCode != 200) throw Exception('HTTP ${treeResp.statusCode}');
      final blobs = (treeResp.data['tree'] as List).where((t) => t['type'] == 'blob' && _codeExtensions.contains(t['path'].split('.').last.toLowerCase())).toList();
      final files = <Map<String, dynamic>>[];
      for (final b in blobs.take(100)) {
        files.add({'path': b['path'], 'size': b['size'] ?? 0, 'sha': b['sha']});
      }
      final repoData = {
        'id': '$owner/$repo', 'owner': owner, 'repo': repo,
        'token': result['token']!.isNotEmpty ? result['token'] : null,
        'branch': branch, 'files': files, 'fileCount': files.length,
        'status': 'done', 'connectedAt': DateTime.now().toIso8601String(),
      };
      _repos.add(repoData);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('github_repos', jsonEncode(_repos));
      _activeRepoId = repoData['id'] as String;
      await prefs.setString('github_active_repo_id', _activeRepoId!);
      _loadChatHistory();
      if (mounted) { setState(() => _connectingStatus = null); _loadRepos(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已连接 ${repoData['id']} (${files.length} 个文件)'))); }
    } catch (e) {
      String msg = '连接失败: $e';
      if (e.toString().contains('SocketException')) msg = '网络连接失败';
      else if (e.toString().contains('timed out')) msg = '连接超时';
      if (mounted) { setState(() => _connectingStatus = null); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))); }
    }
  }

  Future<void> _refreshRepo(Map<String, dynamic> repo) async {
    setState(() => _connectingStatus = '正在刷新文件树...');
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 30)));
      final headers = <String, String>{'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'ThForu'};
      final token = repo['token'] as String?;
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'token $token';
      final branch = repo['branch'] ?? 'main';
      final resp = await dio.get('https://api.github.com/repos/${repo['owner']}/${repo['repo']}/git/trees/$branch?recursive=1', options: Options(headers: headers));
      if (resp.statusCode == 200) {
        final blobs = (resp.data['tree'] as List).where((t) => t['type'] == 'blob' && _codeExtensions.contains(t['path'].split('.').last.toLowerCase())).toList();
        final files = <Map<String, dynamic>>[];
        for (final b in blobs.take(100)) {
          files.add({'path': b['path'], 'size': b['size'] ?? 0, 'sha': b['sha']});
        }
        repo['files'] = files;
        repo['fileCount'] = files.length;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('github_repos', jsonEncode(_repos));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已刷新 ${files.length} 个文件')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
    }
    setState(() => _connectingStatus = null);
  }

  Future<void> _deleteRepo(Map<String, dynamic> repo) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除仓库'), content: Text('确定删除 ${repo['id']}？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('删除'))],
    ));
    if (confirm == true) {
      _repos.removeWhere((r) => r['id'] == repo['id']);
      if (_activeRepoId == repo['id']) _activeRepoId = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('github_repos', jsonEncode(_repos));
      await prefs.remove('github_active_repo_id');
      _loadRepos();
      _loadChatHistory();
    }
  }

  // ==================== File Loading ====================

  Future<void> _loadFileContent(Map<String, dynamic> file) async {
    final repo = _repos.firstWhere((r) => r['id'] == _activeRepoId);
    final token = repo['token'] as String?;
    final branch = repo['branch'] ?? 'main';
    final headers = <String, String>{'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'ThForu'};
    if (token != null) headers['Authorization'] = 'token $token';
    try {
      final resp = await Dio().get('https://api.github.com/repos/${repo['owner']}/${repo['repo']}/contents/${file['path']}?ref=$branch', options: Options(headers: headers));
      if (resp.statusCode == 200 && resp.data['content'] != null) {
        final content = utf8.decode(base64Decode(resp.data['content'].replaceAll('\n', '')));
        setState(() { _selectedFile = _RepoFile(path: file['path'], content: content, size: file['size'], language: _detectLang(file['path'])); _showingTree = true; });
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e'))); }
  }

  Future<void> _openFileByPath(String filePath) async {
    for (final repo in _repos.where((r) => r['status'] == 'done')) {
      final repoFiles = (repo['files'] as List).cast<Map<String, dynamic>>();
      final match = repoFiles.where((f) => (f['path'] as String) == filePath).toList();
      if (match.isNotEmpty) {
        _activeRepoId = repo['id'] as String;
        await _loadFileContent(match.first);
        return;
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件 $filePath 不在已缓存的仓库中')));
  }

  Future<String?> _fetchFileContent(String repoId, Map<String, dynamic> file) async {
    try {
      final repo = _repos.firstWhere((r) => r['id'] == repoId);
      final token = repo['token'] as String?;
      final branch = repo['branch'] ?? 'main';
      final headers = <String, String>{'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'ThForu'};
      if (token != null) headers['Authorization'] = 'token $token';
      final resp = await Dio().get(
        'https://api.github.com/repos/${repo['owner']}/${repo['repo']}/contents/${file['path']}?ref=$branch',
        options: Options(headers: headers, receiveTimeout: const Duration(seconds: 10)),
      );
      if (resp.statusCode == 200 && resp.data['content'] != null) {
        return utf8.decode(base64Decode(resp.data['content'].replaceAll('\n', '')));
      }
    } catch (_) {}
    return null;
  }

  // ==================== Chat Send (Multi-repo Agent) ====================

  Future<void> _chatSend() async {
    final text = _chatInputCtrl.text.trim();
    if (text.isEmpty) return;
    _chatInputCtrl.clear();
    setState(() { _chatMessages.add(_ChatMsg(role: 'user', content: text)); _chatStreaming = true; });
    _saveChatHistory();

    final providers = ref.read(providerListProvider);
    final provider = _chatProvider ?? (providers.isNotEmpty ? providers.first : null);
    if (provider == null) { setState(() { _chatMessages.add(_ChatMsg(role: 'assistant', content: '请先配置 AI 模型')); _chatStreaming = false; }); return; }

    final doneRepos = _repos.where((r) => r['status'] == 'done').toList();
    final aiService = AiService(provider);

    try {
      String fileTree = '';
      for (final repo in doneRepos) {
        final repoFiles = (repo['files'] as List).cast<Map<String, dynamic>>();
        final paths = repoFiles.map((f) => f['path'] as String).toList()..sort();
        fileTree += '\n仓库 [${repo['id']}] (${paths.length} 个文件):\n${paths.join('\n')}\n';
      }

      if (fileTree.isNotEmpty) {
        final planPrompt = '你是代码分析 Agent。用户有一个或多个 GitHub 仓库连接。你可以跨仓库引用文件。\n'
            '以下是所有仓库的完整文件目录树：\n$fileTree\n'
            '用户问题：$text\n\n'
            '请根据用户问题，列出你需要读取的文件路径（每行一个，格式: [仓库ID] 文件路径，如 [owner/repo] lib/main.dart）。'
            '最多选择 8 个最相关的文件。如果问题与代码无关，回复"无"。';

        String planResult = '';
        await for (final chunk in aiService.streamChat(history: [], newUserMessage: planPrompt)) {
          planResult += chunk;
        }

        final selectedPaths = <_ScoredFile>[];
        final lineRe = RegExp(r'\[(\S+)\]\s+(\S+)');
        for (final line in planResult.split('\n')) {
          final m = lineRe.firstMatch(line.trim());
          if (m != null) {
            final repoId = m.group(1)!;
            final filePath = m.group(2)!;
            for (final repo in doneRepos) {
              if (repo['id'] != repoId) continue;
              final repoFiles = (repo['files'] as List).cast<Map<String, dynamic>>();
              final match = repoFiles.where((f) => (f['path'] as String) == filePath).toList();
              if (match.isNotEmpty) selectedPaths.add(_ScoredFile(repo: repoId, file: match.first, score: 1));
              break;
            }
          }
        }

        final codeBuffer = StringBuffer();
        codeBuffer.writeln('[仓库代码]\n');
        for (final sf in selectedPaths.take(8)) {
          final content = await _fetchFileContent(sf.repo, sf.file);
          if (content != null) {
            codeBuffer.writeln('--- [${sf.repo}] ${sf.file['path']} ---');
            codeBuffer.writeln(content);
            codeBuffer.writeln();
          }
        }

        final systemPrompt = '你是代码助手，帮助用户理解 GitHub 仓库中的代码。你可以跨仓库引用代码。用中文回答。\n'
            '以下是与问题相关的代码：\n${codeBuffer.toString()}\n'
            '请基于以上代码回答。引用文件路径时使用 [仓库ID] 文件路径 格式，如 [owner/repo] lib/main.dart。';

        String fullContent = '';
        final history = <Message>[Message(conversationId: '', role: 'system', content: systemPrompt)];
        final recent = _chatMessages.where((m) => m != _chatMessages.last).toList();
        for (final m in recent) { history.add(Message(conversationId: '', role: m.role, content: m.content)); }

        await for (final chunk in aiService.streamChat(history: history, newUserMessage: text)) {
          fullContent += chunk;
          setState(() {
            if (_chatMessages.isNotEmpty && _chatMessages.last.role == 'assistant') _chatMessages.removeLast();
            _chatMessages.add(_ChatMsg(role: 'assistant', content: fullContent));
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_chatScrollCtrl.hasClients) _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
          });
        }
      } else {
        String fullContent = '';
        final history = <Message>[Message(conversationId: '', role: 'system', content: '你是代码助手。用中文回答。')];
        final recent = _chatMessages.where((m) => m != _chatMessages.last).toList();
        for (final m in recent) { history.add(Message(conversationId: '', role: m.role, content: m.content)); }

        await for (final chunk in aiService.streamChat(history: history, newUserMessage: text)) {
          fullContent += chunk;
          setState(() {
            if (_chatMessages.isNotEmpty && _chatMessages.last.role == 'assistant') _chatMessages.removeLast();
            _chatMessages.add(_ChatMsg(role: 'assistant', content: fullContent));
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_chatScrollCtrl.hasClients) _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
          });
        }
      }
      setState(() { _chatStreaming = false; });
    } catch (e) {
      setState(() { _chatMessages.add(_ChatMsg(role: 'assistant', content: '错误: $e')); _chatStreaming = false; });
    }
    _saveChatHistory();
    if (_chatScrollCtrl.hasClients) _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
  }

  // ==================== File Search for @file ====================

  void _searchFilesForMention(String query) {
    if (query.isEmpty) { setState(() { _fileSearchResults = []; _showFileSearch = false; }); return; }
    final allFiles = <Map<String, dynamic>>[];
    for (final repo in _repos.where((r) => r['status'] == 'done')) {
      for (final f in (repo['files'] as List).cast<Map<String, dynamic>>()) {
        allFiles.add({...f, 'repoId': repo['id']});
      }
    }
    final q = query.toLowerCase();
    final results = allFiles.where((f) => (f['path'] as String).toLowerCase().contains(q)).take(8).toList();
    setState(() { _fileSearchResults = results; _showFileSearch = results.isNotEmpty; });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showingTree && _activeRepoId != null && !_repos.any((r) => r['id'] == _activeRepoId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() { _showingTree = false; _selectedFile = null; _activeRepoId = null; });
      });
    }

    final activeRepo = _repos.where((r) => r['id'] == _activeRepoId).toList();
    final allFiles = activeRepo.isNotEmpty ? (activeRepo.first['files'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    final filteredFiles = _fileSearchQuery.isEmpty ? allFiles : allFiles.where((f) => (f['path'] as String).toLowerCase().contains(_fileSearchQuery.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_showingTree ? (activeRepo.isNotEmpty ? activeRepo.first['id'] ?? '文件树' : '文件树') : 'GitHub 代码库'),
        leading: _showingTree ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() { _showingTree = false; _selectedFile = null; })) : null,
        actions: [
          if (!_showingTree)
            IconButton(icon: const Icon(Icons.link), tooltip: '连接仓库', onPressed: _connectingStatus != null ? null : _connectRepo),
          if (_showingTree && activeRepo.isNotEmpty)
            IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新文件树', onPressed: _connectingStatus != null ? null : () => _refreshRepo(activeRepo.first)),
        ],
      ),
      body: _connectingStatus != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_connectingStatus!)]))
          : _showingTree && activeRepo.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('仓库数据无效或已删除', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => setState(() { _showingTree = false; _selectedFile = null; }), child: const Text('返回')),
                ]))
              : _showingTree
                  ? (_selectedFile != null ? _buildCodeView(theme) : _buildFileList(theme, filteredFiles))
                  : _buildRepoList(theme, activeRepo),
      floatingActionButton: activeRepo.isNotEmpty && activeRepo.first['status'] == 'done' && !_showChat && _selectedFile == null
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.small(heroTag: 'tree', onPressed: () => setState(() => _showingTree = !_showingTree), child: Icon(_showingTree ? Icons.list : Icons.account_tree)),
              const SizedBox(height: 8),
              FloatingActionButton(heroTag: 'chat', onPressed: () {
                setState(() => _showChat = true);
                _loadChatHistory();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_chatScrollCtrl.hasClients) _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
                });
              }, child: const Icon(Icons.chat)),
            ])
          : null,
      bottomSheet: _showChat ? _buildChatSheet(theme) : null,
    );
  }

  // ==================== Repo List ====================

  Widget _buildRepoList(ThemeData theme, List<Map<String, dynamic>> activeRepo) {
    if (_repos.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.cloud_off, size: 64, color: theme.colorScheme.outline), const SizedBox(height: 16),
      Text('暂无连接的仓库', style: theme.textTheme.titleMedium), const SizedBox(height: 24),
      FilledButton.icon(onPressed: _connectRepo, icon: const Icon(Icons.add), label: const Text('连接仓库')),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: _repos.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('已连接 ${_repos.length} 个仓库', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)));
        final repo = _repos[i - 1];
        final isActive = _activeRepoId == repo['id'];
        return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: Icon(Icons.check_circle, color: isActive ? Colors.green : theme.colorScheme.outline, size: 32),
          title: Text(repo['id'], style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${repo['fileCount'] ?? 0} 个代码文件${repo['token'] == null ? ' · 匿名' : ''}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(isActive ? Icons.star : Icons.star_border, color: isActive ? Colors.amber : null), onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              if (isActive) { await prefs.remove('github_active_repo_id'); _activeRepoId = null; }
              else { await prefs.setString('github_active_repo_id', repo['id'] as String); _activeRepoId = repo['id'] as String; }
              setState(() {});
            }),
            IconButton(icon: const Icon(Icons.folder_open), tooltip: '查看文件', onPressed: () => setState(() { _showingTree = true; _activeRepoId = repo['id'] as String; })),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRepo(repo)),
          ]),
        ));
      },
    );
  }

  // ==================== File List (Tree) ====================

  Widget _buildFileList(ThemeData theme, List<Map<String, dynamic>> files) {
    if (files.isEmpty) return const Center(child: Text('没有匹配的文件'));
    final root = _TreeNode(name: '', isDir: true, fullPath: '');
    for (final f in files) {
      final parts = (f['path'] as String).split('/');
      var node = root;
      for (int i = 0; i < parts.length; i++) {
        final name = parts[i];
        final isLast = i == parts.length - 1;
        final fullPath = parts.sublist(0, i + 1).join('/');
        if (!node.children.containsKey(name)) {
          node.children[name] = _TreeNode(name: name, isDir: !isLast, fullPath: fullPath);
        }
        if (isLast) node.children[name]!.file = f;
        node = node.children[name]!;
      }
    }
    final items = <Map<String, dynamic>>[];
    void _flatten(_TreeNode node, int depth) {
      final sorted = node.children.entries.toList()..sort((a, b) {
        if (a.value.isDir && !b.value.isDir) return -1;
        if (!a.value.isDir && b.value.isDir) return 1;
        return a.key.compareTo(b.key);
      });
      for (final entry in sorted) {
        final child = entry.value;
        if (child.isDir) {
          final collapsed = _collapsedFolders.contains(child.fullPath);
          items.add({'type': 'folder', 'path': child.fullPath, 'name': child.name, 'depth': depth, 'fileCount': child.descendantFileCount});
          if (!collapsed) _flatten(child, depth + 1);
        } else {
          items.add({'type': 'file', 'data': child.file!, 'depth': depth});
        }
      }
    }
    _flatten(root, 0);

    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(
        decoration: const InputDecoration(hintText: '搜索文件名...', prefixIcon: Icon(Icons.search, size: 20), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onChanged: (v) => setState(() => _fileSearchQuery = v),
      )),
      Expanded(child: items.isEmpty ? const Center(child: Text('没有匹配的文件')) : ListView.builder(
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          if (item['type'] == 'folder') {
            final collapsed = _collapsedFolders.contains(item['path']);
            return ListTile(
              leading: Icon(collapsed ? Icons.folder : Icons.folder_open, size: 20, color: Colors.amber),
              title: Text(item['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text('${item['fileCount']} 个文件', style: theme.textTheme.bodySmall),
              contentPadding: EdgeInsets.only(left: 12.0 + (item['depth'] as int) * 16.0),
              dense: true,
              onTap: () => setState(() {
                if (collapsed) _collapsedFolders.remove(item['path']);
                else _collapsedFolders.add(item['path']);
              }),
            );
          }
          final f = item['data'] as Map<String, dynamic>;
          final lang = _detectLang(f['path'] as String);
          return ListTile(
            leading: Icon(_fileIcon(f['path'] as String), size: 20, color: _fileIconColor(lang)),
            title: Text((f['path'] as String).split('/').last, style: const TextStyle(fontSize: 14)),
            subtitle: Text(f['path'] as String, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            contentPadding: EdgeInsets.only(left: 12.0 + (item['depth'] as int) * 16.0),
            dense: true,
            onTap: () => _loadFileContent(f),
          );
        },
      )),
    ]);
  }

  // ==================== Code View ====================

  Widget _buildCodeView(ThemeData theme) {
    final file = _selectedFile!;
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Row(children: [
          Icon(_fileIcon(file.path), size: 18), const SizedBox(width: 8),
          Expanded(child: Text(file.path, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(file.language, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary))),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.copy, size: 18), tooltip: '复制', onPressed: () { Clipboard.setData(ClipboardData(text: file.content ?? '')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); }),
          IconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: '返回', onPressed: () => setState(() => _selectedFile = null)),
        ]),
      ),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText.rich(
          _highlightCode(file.content ?? '', file.language, theme),
          onSelectionChanged: (selection, cause) {
            if (!selection.isCollapsed) {
              final text = file.content ?? '';
              final start = selection.start;
              final end = selection.end.clamp(0, text.length);
              if (start >= 0 && start < end) _selectedCodeText = text.substring(start, end);
            }
          },
        ),
      )),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5), border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)))),
        child: Row(children: [
          Icon(Icons.help_outline, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('选中代码后点击下方按钮向 AI 提问', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary))),
          FilledButton.tonal(
            onPressed: () async {
              final selected = _selectedCodeText;
              if (selected.isNotEmpty && selected != file.content) {
                setState(() {
                  _showChat = true;
                  _chatInputCtrl.text = '(文件: ${file.path}) 这段代码是什么意思？\n\n```\n$selected\n```';
                });
                _loadChatHistory();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_chatScrollCtrl.hasClients) _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先长按选中代码')));
              }
            },
            child: const Text('问 AI', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    ]);
  }

  // ==================== Chat Sheet ====================

  Widget _buildChatSheet(ThemeData theme) {
    final doneRepos = _repos.where((r) => r['status'] == 'done').toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)]),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.chat_bubble_outline, size: 18), const SizedBox(width: 8),
              Text('代码问答', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)), const Spacer(),
              Consumer(builder: (ctx, ref, _) {
                final providers = ref.watch(providerListProvider);
                if (providers.isEmpty) return const SizedBox();
                return DropdownButton<AIProviderConfig>(
                  value: _chatProvider, hint: const Text('模型', style: TextStyle(fontSize: 12)), isDense: true, underline: const SizedBox(),
                  items: providers.map((p) => DropdownMenuItem<AIProviderConfig>(value: p, child: Text(p.name, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _chatProvider = v),
                );
              }),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.close, size: 18), tooltip: '关闭', onPressed: () { setState(() => _showChat = false); _saveChatHistory(); }, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), padding: EdgeInsets.zero),
            ]),
            if (doneRepos.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: doneRepos.map((r) => Chip(
                avatar: const Icon(Icons.check_circle, size: 14, color: Colors.green),
                label: Text(r['id'] as String, style: const TextStyle(fontSize: 11)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero,
              )).toList()),
            ),
            if (doneRepos.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('暂无已连接仓库', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))),
          ]),
        ),
        Expanded(
          child: Stack(children: [
            _chatMessages.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.code, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.5)), const SizedBox(height: 12), Text('问我关于代码的问题', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline))]))
                : ListView.builder(
                    controller: _chatScrollCtrl, padding: const EdgeInsets.all(12),
                    itemCount: _chatMessages.length + (_chatStreaming ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _chatMessages.length) return const Padding(padding: EdgeInsets.all(8), child: Align(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
                      final msg = _chatMessages[i];
                      final isUser = msg.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                          decoration: BoxDecoration(color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                          child: _buildChatMessageContent(msg, theme),
                        ),
                      );
                    },
                  ),
            if (_showFileSearch)
              Positioned(left: 12, right: 12, bottom: 60, child: Card(
                elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.all(8), child: TextField(
                    controller: _fileSearchCtrl, autofocus: true,
                    decoration: const InputDecoration(hintText: '搜索文件名...', border: InputBorder.none, isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
                    onChanged: _searchFilesForMention,
                  )),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true, itemCount: _fileSearchResults.length,
                      itemBuilder: (ctx, i) {
                        final f = _fileSearchResults[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(_fileIcon(f['path'] as String), size: 16),
                          title: Text((f['path'] as String).split('/').last, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${f['repoId']} · ${f['path']}', style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            _chatInputCtrl.text += '[${f['repoId']}] ${f['path']}';
                            setState(() { _showFileSearch = false; _fileSearchResults = []; });
                            _fileSearchCtrl.clear();
                          },
                        );
                      },
                    ),
                  ),
                ]),
              )),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)))),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.alternate_email, size: 20),
              tooltip: '@文件',
              onPressed: () { setState(() => _showFileSearch = !_showFileSearch); if (_showFileSearch) _fileSearchCtrl.clear(); },
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 4),
            Expanded(child: TextField(
              controller: _chatInputCtrl, maxLines: null,
              decoration: InputDecoration(hintText: '问我代码相关的问题...', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), filled: true, fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)),
              onSubmitted: (_) => _chatSend(),
            )),
            const SizedBox(width: 8),
            IconButton(icon: Icon(Icons.send, color: _chatStreaming ? theme.colorScheme.outline : theme.colorScheme.primary), onPressed: _chatStreaming ? null : _chatSend),
          ]),
        ),
      ]),
    );
  }

  // ==================== Chat Message Content ====================

  Widget _buildChatMessageContent(_ChatMsg msg, ThemeData theme) {
    final content = msg.content;
    final segments = <Widget>[];
    final parts = content.split(RegExp(r'(```[\s\S]*?```)'));
    for (final part in parts) {
      if (part.startsWith('```') && part.endsWith('```')) {
        final code = part.substring(3, part.length - 3);
        final lines = code.split('\n');
        final lang = lines.first.trim();
        final codeBody = lines.length > 1 ? lines.sublist(1).join('\n') : code;
        segments.add(_buildCodeBlock(codeBody, lang, theme));
      } else if (part.isNotEmpty) {
        segments.add(_buildRichTextWithFileLinks(part, theme));
      }
    }
    if (segments.isEmpty) segments.add(_buildRichTextWithFileLinks(content, theme));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: segments);
  }

  Widget _buildCodeBlock(String code, String lang, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Padding(padding: const EdgeInsets.only(left: 8), child: Text(lang.isNotEmpty ? lang : 'code', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.copy, size: 14), tooltip: '复制', padding: const EdgeInsets.all(4), constraints: const BoxConstraints(), onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('代码已复制'), duration: Duration(seconds: 1)));
          }),
        ]),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: SelectableText(code, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: theme.colorScheme.onSurface)),
        ),
      ]),
    );
  }

  Widget _buildRichTextWithFileLinks(String text, ThemeData theme) {
    final pathRe = RegExp(r'\[(\S+?)\]\s+(\S+\.\w+)|(?<!\w)(lib/\S+\.\w+)|(?<!\w)(src/\S+\.\w+)|(?<!\w)(android/\S+\.\w+)|(?<!\w)(ios/\S+\.\w+)|(?<!\w)(test/\S+\.\w+)|(?<!\w)(web/\S+\.\w+)', caseSensitive: false);
    final spans = <InlineSpan>[];
    int pos = 0;
    for (final m in pathRe.allMatches(text)) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      final repoId = m.group(1);
      final filePath = m.group(2) ?? m.group(3) ?? m.group(4) ?? m.group(5) ?? m.group(6) ?? m.group(7) ?? '';
      final displayPath = repoId != null ? '[$repoId] $filePath' : filePath;
      spans.add(WidgetSpan(child: GestureDetector(
        onTap: () => _openFileByPath(filePath),
        child: Text(displayPath, style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline, fontSize: theme.textTheme.bodyMedium?.fontSize)),
      )));
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    if (spans.isEmpty) return SelectableText(text, style: theme.textTheme.bodyMedium);
    return RichText(text: TextSpan(children: spans, style: theme.textTheme.bodyMedium), softWrap: true);
  }

  // ==================== Icons & Syntax ====================

  IconData _fileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    const icons = {'dart': Icons.code, 'java': Icons.code, 'kt': Icons.code, 'py': Icons.code, 'js': Icons.javascript, 'ts': Icons.javascript, 'html': Icons.language, 'css': Icons.palette, 'json': Icons.data_object, 'yaml': Icons.settings, 'yml': Icons.settings, 'md': Icons.article, 'sql': Icons.storage, 'sh': Icons.terminal};
    return icons[ext] ?? Icons.insert_drive_file;
  }

  Color _fileIconColor(String lang) {
    const c = {'Dart': Color(0xFF0175C2), 'Java': Color(0xFFED8B00), 'Kotlin': Color(0xFF7F52FF), 'Python': Color(0xFF3776AB), 'JS': Color(0xFFF7DF1E), 'TS': Color(0xFF3178C6), 'HTML': Color(0xFFE34F26), 'CSS': Color(0xFF1572B6)};
    return c[lang] ?? Colors.grey;
  }

  TextSpan _highlightCode(String code, String lang, ThemeData theme) {
    final spans = <TextSpan>[];
    final keywords = {'class','extends','import','export','return','if','else','for','while','switch','case','break','continue','try','catch','finally','throw','new','this','super','final','var','const','let','void','static','async','await','function','def','self','public','private','protected','abstract','interface','implements','override','enum','sealed','late','required','factory','get','set'};
    for (final line in code.split('\n')) {
      if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('#') || line.trimLeft().startsWith('*')) {
        spans.add(TextSpan(text: '$line\n', style: TextStyle(color: const Color(0xFF888888), fontSize: 13, fontFamily: 'monospace')));
      } else {
        int pos = 0;
        final tokenRe = RegExp(r'[a-zA-Z_]\w*|\d+\.?\d*|"[^"]*"|[^"\s\w]+');
        for (final m in tokenRe.allMatches(line)) {
          if (m.start > pos) spans.add(TextSpan(text: line.substring(pos, m.start), style: const TextStyle(fontSize: 13, fontFamily: 'monospace')));
          final t = m.group(0)!;
          if (t.startsWith('"')) spans.add(TextSpan(text: t, style: TextStyle(color: const Color(0xFF0D9373), fontSize: 13, fontFamily: 'monospace')));
          else if (RegExp(r'^\d').hasMatch(t)) spans.add(TextSpan(text: t, style: TextStyle(color: const Color(0xFF0550AE), fontSize: 13, fontFamily: 'monospace')));
          else if (keywords.contains(t)) spans.add(TextSpan(text: t, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')));
          else spans.add(TextSpan(text: t, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')));
          pos = m.end;
        }
        if (pos < line.length) spans.add(TextSpan(text: line.substring(pos), style: const TextStyle(fontSize: 13, fontFamily: 'monospace')));
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return TextSpan(children: spans);
  }
}
