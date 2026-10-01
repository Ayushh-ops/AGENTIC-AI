import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_service.dart';
import '../main.dart';
import '../models/history_item.dart';
import '../theme/app_theme.dart';
import '../widgets/dynamic_background.dart';
import '../widgets/interactive_controls.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _topicController = TextEditingController();
  final ApiService _apiService = ApiService();

  bool _isSidebarOpen = true;
  List<HistoryItem> _history = [];
  String? _selectedHistoryItemId;

  String _selectedType = 'general'; // 'general' | 'news' | 'academic'
  String _selectedDepth = 'standard'; // 'quick' | 'standard' | 'deep'
  String? _activeResearchType;
  String? _activeResearchDepth;

  bool _isLoading = false;
  String _loadingText = 'Thinking...';
  Timer? _loadingTimer;
  String? _errorMessage;
  AskResponse? _askResponse;

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url.trim());
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) {
        host = host.substring(4);
      }
      return host.isNotEmpty ? host : url;
    } catch (_) {
      return url;
    }
  }

  String _cleanReportMarkdown(String fullReport) {
    const delimiter = '## Evaluated Claims & Verification Audit';
    final index = fullReport.indexOf(delimiter);
    if (index != -1) {
      return fullReport.substring(0, index).trim();
    }
    return fullReport.trim();
  }

  Future<void> _launchUrlString(String urlStr) async {
    final trimmed = urlStr.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid URL: $urlStr'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $urlStr'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $urlStr'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadHistory();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedType = prefs.getString('app_research_type');
      final savedDepth = prefs.getString('app_research_depth');
      if (mounted) {
        setState(() {
          if (savedType != null &&
              ['general', 'news', 'academic'].contains(savedType)) {
            _selectedType = savedType;
          }
          if (savedDepth != null &&
              ['quick', 'standard', 'deep'].contains(savedDepth)) {
            _selectedDepth = savedDepth;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTypePreference(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_research_type', type);
    } catch (_) {}
  }

  Future<void> _saveDepthPreference(String depth) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_research_depth', depth);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final items = await HistoryStorage.loadHistory();
    if (mounted) {
      setState(() {
        _history = items;
      });
    }
  }

  void _saveToHistory(
    String message,
    AskResponse res, {
    String? researchType,
    String? depth,
  }) {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newItem = HistoryItem(
      id: newId,
      message: message,
      mode: res.mode,
      reply: res.reply,
      research: res.research,
      researchType: researchType,
      depth: depth,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _selectedHistoryItemId = newId;
      _history.removeWhere(
          (i) => i.message.trim().toLowerCase() == message.trim().toLowerCase());
      _history.insert(0, newItem);
      if (_history.length > HistoryStorage.maxHistoryItems) {
        _history = _history.sublist(0, HistoryStorage.maxHistoryItems);
      }
    });

    HistoryStorage.saveHistory(_history);
  }

  void _deleteHistoryItem(String id) {
    setState(() {
      if (_selectedHistoryItemId == id) {
        _selectedHistoryItemId = null;
      }
      _history.removeWhere((i) => i.id == id);
    });
    HistoryStorage.saveHistory(_history);
  }

  void _clearAllHistory() {
    setState(() {
      _selectedHistoryItemId = null;
      _history.clear();
    });
    HistoryStorage.saveHistory(_history);
  }

  void _confirmClearAllHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Clear all history?',
          style: AppTheme.displayFont(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will permanently delete all saved research queries and summaries.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _clearAllHistory();
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  void _selectHistoryItem(HistoryItem item) {
    setState(() {
      _selectedHistoryItemId = item.id;
      _topicController.text = item.message;
      _errorMessage = null;
      _isLoading = false;
      _activeResearchType = item.researchType ?? 'general';
      _activeResearchDepth = item.depth ?? 'standard';
      _askResponse = AskResponse(
        mode: item.mode,
        reply: item.reply,
        research: item.research,
        llmCalls: null,
        searchCalls: null,
      );
    });
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _startNewResearch() {
    setState(() {
      _selectedHistoryItemId = null;
      _topicController.clear();
      _errorMessage = null;
      _askResponse = null;
      _isLoading = false;
      _activeResearchType = null;
      _activeResearchDepth = null;
    });
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _toggleTheme() {
    final current = themeModeNotifier.value;
    final Brightness platformBrightness =
        MediaQuery.platformBrightnessOf(context);
    final isDark = current == ThemeMode.dark ||
        (current == ThemeMode.system && platformBrightness == Brightness.dark);
    final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
    themeModeNotifier.value = newMode;
    saveThemeMode(newMode);
  }

  void _onSelectExamplePrompt(String prompt) {
    _topicController.text = prompt;
    setState(() {});
    _executeAsk();
  }

  Future<void> _executeAsk() async {
    final message = _topicController.text.trim();
    if (message.isEmpty || _isLoading) return;

    final typeToRun = _selectedType;
    final depthToRun = _selectedDepth;

    FocusScope.of(context).unfocus();

    _loadingTimer?.cancel();
    setState(() {
      _isLoading = true;
      _loadingText = 'Thinking...';
      _errorMessage = null;
      _askResponse = null;
    });

    _loadingTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        setState(() {
          _loadingText = 'Conducting autonomous web research...';
        });
      }
    });

    try {
      final res = await _apiService.ask(
        message,
        researchType: typeToRun,
        depth: depthToRun,
      );
      _loadingTimer?.cancel();
      if (mounted) {
        setState(() {
          _activeResearchType = typeToRun;
          _activeResearchDepth = depthToRun;
          _askResponse = res;
          _isLoading = false;
        });
        _saveToHistory(
          message,
          res,
          researchType: typeToRun,
          depth: depthToRun,
        );
      }
    } on ApiException catch (e) {
      _loadingTimer?.cancel();
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      _loadingTimer?.cancel();
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.hub_outlined, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'About Multi-Agent Assistant',
                style: AppTheme.displayFont(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'What it does',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Executes live web search, cross-checks claims across independent sources, and synthesizes cited reports with verification status.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The 3 Autonomous Agents',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildAgentCard(
                    name: 'Researcher:',
                    role:
                        'Deconstructs the topic and gathers relevant live web sources via targeted search queries.',
                    icon: Icons.travel_explore,
                    color: colorScheme.primary,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),
                  _buildAgentCard(
                    name: 'Fact-Checker:',
                    role:
                        'Audits sources, extracts factual claims, and evaluates multi-source corroboration with strict quote validation.',
                    icon: Icons.fact_check_outlined,
                    color: colorScheme.secondary,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),
                  _buildAgentCard(
                    name: 'Synthesizer:',
                    role:
                        'Compiles verified claims and cited sources into a transparent, structured report.',
                    icon: Icons.auto_awesome,
                    color: colorScheme.tertiary,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Research Depth',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      'Quick provides a fast single-search summary, Standard balances speed and corroboration, while Deep checks more sources but takes longer and uses more API calls.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Claim verification statuses',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatusChip('supported'),
                      _buildStatusChip('single_source'),
                      _buildStatusChip('unsupported'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Limitations',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI models may misinterpret subtle nuances or encounter biased sources. Synthesized reports provide an evidence base and should always be read critically.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAgentCard({
    required String name,
    required String role,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(int timestamp) {
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.month}/${dt.day}';
    }
  }

  String _getDateGroup(int timestamp) {
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime(dt.year, dt.month, dt.day);

    if (itemDate.isAtSameMomentAs(today)) {
      return 'Today';
    } else if (itemDate.isAtSameMomentAs(yesterday)) {
      return 'Yesterday';
    } else {
      return 'Earlier';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 800;
    final bool canSubmit =
        !_isLoading && _topicController.text.trim().isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final appBar = AppBar(
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Toggle sidebar',
          onPressed: () {
            if (isWide) {
              setState(() {
                _isSidebarOpen = !_isSidebarOpen;
              });
            } else {
              Scaffold.of(ctx).openDrawer();
            }
          },
        ),
      ),
      title: Text(
        'Multi-Agent Research Assistant',
        style: AppTheme.displayFont(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'About Multi-Agent Assistant',
          onPressed: () => _showAboutDialog(context),
        ),
        IconButton(
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
          tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          onPressed: _toggleTheme,
        ),
      ],
    );

    return Scaffold(
      appBar: appBar,
      drawer: isWide ? null : Drawer(child: _buildSidebarContent(isDrawer: true)),
      body: DynamicBackground(
        isLoading: _isLoading,
        child: isWide
            ? Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    width: _isSidebarOpen ? 290 : 0,
                    child: _isSidebarOpen
                        ? _buildSidebarContent(isDrawer: false)
                        : const SizedBox.shrink(),
                  ),
                  if (_isSidebarOpen)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                  Expanded(
                    child: _buildMainContent(canSubmit: canSubmit, isWide: true),
                  ),
                ],
              )
            : _buildMainContent(canSubmit: canSubmit, isWide: false),
      ),
    );
  }

  Widget _buildSidebarContent({required bool isDrawer}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: App logo mark + short name
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? AppTheme.primaryGradientDark
                          : AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Research Assistant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.displayFont(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Top: Full-width New research button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: NewResearchButton(onPressed: _startNewResearch),
            ),

            // Recent Header with Clear all action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'RECENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (_history.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: _confirmClearAllHistory,
                      child: Text(
                        'Clear all',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Grouped Recent List (scrollable)
            Expanded(
              child: _buildGroupedHistoryList(!isDrawer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedHistoryList(bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_toggle_off,
                size: 32,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'No research history yet',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final todayItems = <HistoryItem>[];
    final yesterdayItems = <HistoryItem>[];
    final earlierItems = <HistoryItem>[];

    for (final item in _history) {
      final group = _getDateGroup(item.timestamp);
      if (group == 'Today') {
        todayItems.add(item);
      } else if (group == 'Yesterday') {
        yesterdayItems.add(item);
      } else {
        earlierItems.add(item);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (todayItems.isNotEmpty) ...[
          _buildGroupHeader('Today'),
          for (final item in todayItems)
            _HistoryTile(
              item: item,
              isSelected: _selectedHistoryItemId == item.id,
              isWide: isWide,
              relativeTime: _formatRelativeTime(item.timestamp),
              onTap: () => _selectHistoryItem(item),
              onDelete: () => _deleteHistoryItem(item.id),
            ),
        ],
        if (yesterdayItems.isNotEmpty) ...[
          _buildGroupHeader('Yesterday'),
          for (final item in yesterdayItems)
            _HistoryTile(
              item: item,
              isSelected: _selectedHistoryItemId == item.id,
              isWide: isWide,
              relativeTime: _formatRelativeTime(item.timestamp),
              onTap: () => _selectHistoryItem(item),
              onDelete: () => _deleteHistoryItem(item.id),
            ),
        ],
        if (earlierItems.isNotEmpty) ...[
          _buildGroupHeader('Earlier'),
          for (final item in earlierItems)
            _HistoryTile(
              item: item,
              isSelected: _selectedHistoryItemId == item.id,
              isWide: isWide,
              relativeTime: _formatRelativeTime(item.timestamp),
              onTap: () => _selectHistoryItem(item),
              onDelete: () => _deleteHistoryItem(item.id),
            ),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildMainContent({required bool canSubmit, required bool isWide}) {
    final hasResultOrActivity =
        _askResponse != null || _isLoading || _errorMessage != null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: !hasResultOrActivity
          ? _buildHeroView(canSubmit)
          : _buildResultView(canSubmit),
    );
  }

  Widget _buildHeroView(bool canSubmit) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      key: const ValueKey('hero_view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Large Display Title with subtle gradient on key word
              ShaderMask(
                shaderCallback: (bounds) => (isDark
                        ? AppTheme.heroTitleGradientDark
                        : AppTheme.heroTitleGradient)
                    .createShader(bounds),
                child: Text(
                  'Autonomous Multi-Agent Research',
                  textAlign: TextAlign.center,
                  style: AppTheme.displayFont(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // One-line Tagline
              Text(
                'Live web investigation, strict multi-source corroboration, and transparent synthesis.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyFont(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // Centered Search Bar with Glass-like Card Styling (28px rounded)
              _buildSearchBar(canSubmit: canSubmit, isHero: true),
              const SizedBox(height: 24),

              // 3 Clickable Example Prompt Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildExampleChip('Quantum computing in 2026'),
                  _buildExampleChip('Latest on CRISPR'),
                  _buildExampleChip('Explain how RAG works'),
                ],
              ),
              const SizedBox(height: 48),

              // Footer About Link
              TextButton.icon(
                onPressed: () => _showAboutDialog(context),
                icon: const Icon(Icons.info_outline, size: 14),
                label: const Text(
                  'About Multi-Agent Assistant',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExampleChip(String prompt) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: const Icon(Icons.north_west, size: 13),
      label: Text(
        prompt,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => _onSelectExamplePrompt(prompt),
    );
  }

  Widget _buildResultView(bool canSubmit) {
    return Center(
      key: const ValueKey('result_view'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            _buildSearchBar(canSubmit: canSubmit, isHero: false),
            const SizedBox(height: 20),
            if (_isLoading) _buildLoadingIndicator(),
            if (_errorMessage != null) ...[
              _buildErrorCard(),
              const SizedBox(height: 16),
            ],
            if (_askResponse != null) ...[
              if (_askResponse!.mode == 'chat')
                _buildChatResponseCard(_askResponse!)
              else if (_askResponse!.research != null)
                _buildResultSection(_askResponse!.research!),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar({required bool canSubmit, required bool isHero}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Glass-like container
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainer.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: isHero ? 24 : 14,
                spreadRadius: isHero ? 2 : 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: colorScheme.primary,
                size: isHero ? 22 : 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _topicController,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Ask or enter a research topic',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (canSubmit) _executeAsk();
                  },
                ),
              ),
              if (_topicController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: _isLoading
                      ? null
                      : () {
                          _topicController.clear();
                          setState(() {});
                        },
                ),
              const SizedBox(width: 4),
              PrimaryResearchButton(
                onPressed: canSubmit ? _executeAsk : null,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildTypeAndDepthSelectors(colorScheme),
      ],
    );
  }

  Widget _buildTypeAndDepthSelectors(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildTypeSelector(colorScheme),
          _buildDepthSelector(colorScheme),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(ColorScheme colorScheme) {
    final typeInfo = {
      'general': {
        'label': 'General',
        'icon': Icons.public,
        'tooltip': 'General: searches across authoritative public web sources',
      },
      'news': {
        'label': 'News',
        'icon': Icons.newspaper,
        'tooltip': 'News: recent news articles from the past 30 days',
      },
      'academic': {
        'label': 'Academic',
        'icon': Icons.school,
        'tooltip': 'Academic: peer-reviewed journals & preprint archives',
      },
    };

    final current = typeInfo[_selectedType] ?? typeInfo['general']!;

    return Tooltip(
      message: current['tooltip'] as String,
      child: PopupMenuButton<String>(
        enabled: !_isLoading,
        initialValue: _selectedType,
        tooltip: 'Select research type',
        onSelected: (val) {
          setState(() {
            _selectedType = val;
          });
          _saveTypePreference(val);
        },
        itemBuilder: (context) => [
          _buildSelectorMenuItem(
            value: 'general',
            label: 'General',
            icon: Icons.public,
            desc: 'General public web sources',
            isSelected: _selectedType == 'general',
            colorScheme: colorScheme,
          ),
          _buildSelectorMenuItem(
            value: 'news',
            label: 'News',
            icon: Icons.newspaper,
            desc: 'Recent news (last 30 days)',
            isSelected: _selectedType == 'news',
            colorScheme: colorScheme,
          ),
          _buildSelectorMenuItem(
            value: 'academic',
            label: 'Academic',
            icon: Icons.school,
            desc: 'Peer-reviewed journals & preprints',
            isSelected: _selectedType == 'academic',
            colorScheme: colorScheme,
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                current['icon'] as IconData,
                size: 15,
                color: _isLoading
                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                    : colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Type: ${current['label']}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _isLoading
                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                    : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: _isLoading
                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepthSelector(ColorScheme colorScheme) {
    final depthInfo = {
      'quick': {
        'label': 'Quick',
        'icon': Icons.bolt,
        'tooltip': 'Quick: 1 search, ~3 LLM calls, fast summary',
      },
      'standard': {
        'label': 'Standard',
        'icon': Icons.tune,
        'tooltip': 'Standard: up to 3 queries, multi-source corroboration',
      },
      'deep': {
        'label': 'Deep',
        'icon': Icons.layers,
        'tooltip': 'Deep: up to 4 queries, fallback searches, up to 15 sources',
      },
    };

    final current = depthInfo[_selectedDepth] ?? depthInfo['standard']!;

    return Tooltip(
      message: current['tooltip'] as String,
      child: PopupMenuButton<String>(
        enabled: !_isLoading,
        initialValue: _selectedDepth,
        tooltip: 'Select research depth',
        onSelected: (val) {
          setState(() {
            _selectedDepth = val;
          });
          _saveDepthPreference(val);
        },
        itemBuilder: (context) => [
          _buildSelectorMenuItem(
            value: 'quick',
            label: 'Quick',
            icon: Icons.bolt,
            desc: 'Single search, fast summary',
            isSelected: _selectedDepth == 'quick',
            colorScheme: colorScheme,
          ),
          _buildSelectorMenuItem(
            value: 'standard',
            label: 'Standard',
            icon: Icons.tune,
            desc: 'Up to 3 queries, multi-source corroboration',
            isSelected: _selectedDepth == 'standard',
            colorScheme: colorScheme,
          ),
          _buildSelectorMenuItem(
            value: 'deep',
            label: 'Deep',
            icon: Icons.layers,
            desc: 'Up to 4 queries, 15 sources, deep checks',
            isSelected: _selectedDepth == 'deep',
            colorScheme: colorScheme,
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                current['icon'] as IconData,
                size: 15,
                color: _isLoading
                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                    : colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Depth: ${current['label']}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _isLoading
                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                    : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: _isLoading
                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildSelectorMenuItem({
    required String value,
    required String label,
    required IconData icon,
    required String desc,
    required bool isSelected,
    required ColorScheme colorScheme,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color:
                isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 6),
            Icon(Icons.check, size: 16, color: colorScheme.primary),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _loadingText,
              style: AppTheme.displayFont(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_loadingText != 'Thinking...') ...[
              const SizedBox(height: 6),
              Text(
                'Researcher, Fact-Checker, and Synthesizer agents are analyzing evidence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Request Failed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage ?? 'Unknown error occurred.',
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatResponseCard(AskResponse res) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Assistant',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              res.reply ?? '',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection(ResearchResponse res) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build URL to title map for claims
    final sourceTitleMap = <String, String>{};
    for (final s in res.sources) {
      if (s.url.isNotEmpty) {
        sourceTitleMap[s.url] = s.title;
      }
    }

    final activeType = _activeResearchType ?? _selectedType;
    final activeDepth = _activeResearchDepth ?? _selectedDepth;

    // Claim Counts
    final supportedCount =
        res.claims.where((c) => c.status.toLowerCase() == 'supported').length;
    final singleSourceCount =
        res.claims.where((c) => c.status.toLowerCase() == 'single_source').length;
    final unsupportedCount =
        res.claims.where((c) => c.status.toLowerCase() == 'unsupported').length;

    final cleanedMarkdown = _cleanReportMarkdown(res.reportMarkdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Report Header Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topic as Title
                Text(
                  res.topic,
                  style: AppTheme.displayFont(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                // Type & Depth Badges and Audit Summary Strip
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildReportChip(
                      icon: _iconForType(activeType),
                      label: 'Type: ${_formatType(activeType)}',
                      colorScheme: colorScheme,
                    ),
                    _buildReportChip(
                      icon: _iconForDepth(activeDepth),
                      label: 'Depth: ${_formatDepth(activeDepth)}',
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 4),
                    // Audit count badges
                    _buildAuditCountBadge(
                      label: '$supportedCount Supported',
                      icon: Icons.check_circle,
                      color: AppTheme.statusSupported,
                      bgColor: isDark
                          ? AppTheme.statusSupportedBgDark
                          : AppTheme.statusSupportedBgLight,
                    ),
                    _buildAuditCountBadge(
                      label: '$singleSourceCount Single source',
                      icon: Icons.warning_amber_rounded,
                      color: AppTheme.statusSingleSource,
                      bgColor: isDark
                          ? AppTheme.statusSingleSourceBgDark
                          : AppTheme.statusSingleSourceBgLight,
                    ),
                    if (unsupportedCount > 0)
                      _buildAuditCountBadge(
                        label: '$unsupportedCount Unsupported',
                        icon: Icons.cancel_outlined,
                        color: AppTheme.statusUnsupported,
                        bgColor: isDark
                            ? AppTheme.statusUnsupportedBgDark
                            : AppTheme.statusUnsupportedBgLight,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Synthesized Report Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: MarkdownBody(
                data: cleanedMarkdown,
                selectable: true,
                onTapLink: (text, href, title) {
                  if (href != null && href.isNotEmpty) {
                    _launchUrlString(href);
                  }
                },
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: AppTheme.bodyFont(
                    fontSize: 14,
                    height: 1.6,
                    color: colorScheme.onSurface,
                  ),
                  h1: AppTheme.displayFont(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  h2: AppTheme.displayFont(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  h3: AppTheme.displayFont(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  a: TextStyle(
                    color: colorScheme.primary,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w500,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: Border(
                      left: BorderSide(color: colorScheme.primary, width: 4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Claims & Verification Audit Panel (expanded by default)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Icon(Icons.fact_check_outlined, color: colorScheme.primary),
            title: Text(
              'Claims & Verification Audit (${res.claims.length})',
              style: AppTheme.displayFont(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            children: res.claims.map((claim) {
              final urls = claim.sourceUrls.isNotEmpty
                  ? claim.sourceUrls
                  : (claim.sourceUrl != null ? [claim.sourceUrl!] : <String>[]);

              final statusColor = _statusColor(claim.status);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      border: Border(
                        left: BorderSide(color: statusColor, width: 4),
                        top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusChip(claim.status),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              claim.statement,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (claim.evidence.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Evidence: "${claim.evidence}"',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                              color: colorScheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                      if (urls.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final url in urls)
                              InkWell(
                                onTap: () => _launchUrlString(url),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.open_in_new,
                                        size: 12,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _extractDomain(url),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // 4. Consulted Sources Panel (collapsed by default)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            leading: Icon(Icons.link_outlined, color: colorScheme.primary),
            title: Text(
              'Consulted Sources (${res.sources.length})',
              style: AppTheme.displayFont(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            children: res.sources.map((source) {
              final domain = _extractDomain(source.url);
              final hasTitle = source.title.trim().isNotEmpty &&
                  source.title.trim() != source.url;
              final firstLetter = domain.isNotEmpty
                  ? domain[0].toUpperCase()
                  : 'S';

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    firstLetter,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                title: hasTitle
                    ? Text(
                        source.title.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      )
                    : null,
                subtitle: Tooltip(
                  message: source.url,
                  child: InkWell(
                    onTap: () => _launchUrlString(source.url),
                    child: Text(
                      domain,
                      style: TextStyle(
                        color: colorScheme.primary,
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  tooltip: source.url,
                  onPressed: () => _launchUrlString(source.url),
                ),
                onTap: () => _launchUrlString(source.url),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'supported':
        return AppTheme.statusSupported;
      case 'single_source':
        return AppTheme.statusSingleSource;
      case 'unsupported':
      default:
        return AppTheme.statusUnsupported;
    }
  }

  Widget _buildAuditCountBadge({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportChip({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Chip(
      avatar: Icon(icon, size: 14, color: colorScheme.primary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  String _formatType(String? type) {
    switch (type?.toLowerCase()) {
      case 'news':
        return 'News';
      case 'academic':
        return 'Academic';
      case 'general':
      default:
        return 'General';
    }
  }

  IconData _iconForType(String? type) {
    switch (type?.toLowerCase()) {
      case 'news':
        return Icons.newspaper;
      case 'academic':
        return Icons.school;
      case 'general':
      default:
        return Icons.public;
    }
  }

  String _formatDepth(String? depth) {
    switch (depth?.toLowerCase()) {
      case 'quick':
        return 'Quick';
      case 'deep':
        return 'Deep';
      case 'standard':
      default:
        return 'Standard';
    }
  }

  IconData _iconForDepth(String? depth) {
    switch (depth?.toLowerCase()) {
      case 'quick':
        return Icons.bolt;
      case 'deep':
        return Icons.layers;
      case 'standard':
      default:
        return Icons.tune;
    }
  }

  Widget _buildStatusChip(String status) {
    switch (status.toLowerCase()) {
      case 'supported':
        return const Chip(
          avatar: Icon(Icons.check_circle, size: 14, color: Color(0xFF15803D)),
          label: Text('supported'),
          backgroundColor: Color(0xFFDCFCE7),
          labelStyle: TextStyle(
            color: Color(0xFF15803D),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          side: BorderSide(color: Color(0xFF86EFAC)),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
      case 'single_source':
        return const Chip(
          avatar: Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
          label: Text('single_source'),
          backgroundColor: Color(0xFFFEF3C7),
          labelStyle: TextStyle(
            color: Color(0xFFB45309),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          side: BorderSide(color: Color(0xFFFDE68A)),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
      case 'unsupported':
      default:
        return const Chip(
          avatar: Icon(Icons.cancel_outlined, size: 14, color: Color(0xFFB91C1C)),
          label: Text('unsupported'),
          backgroundColor: Color(0xFFFEE2E2),
          labelStyle: TextStyle(
            color: Color(0xFFB91C1C),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          side: BorderSide(color: Color(0xFFFCA5A5)),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
    }
  }
}

/// Redesigned sidebar item with mode icon in circle, relative timestamp,
/// active item highlight, and hover delete button.
class _HistoryTile extends StatefulWidget {
  final HistoryItem item;
  final bool isSelected;
  final bool isWide;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final String relativeTime;

  const _HistoryTile({
    required this.item,
    required this.isSelected,
    required this.isWide,
    required this.onTap,
    required this.onDelete,
    required this.relativeTime,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isChat = widget.item.mode == 'chat';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showDelete = !widget.isWide || _isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          color: widget.isSelected
              ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.6)
              : (_isHovered
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Colors.transparent),
          border: Border.all(
            color: widget.isSelected
                ? colorScheme.primary.withValues(alpha: 0.6)
                : (_isHovered
                    ? colorScheme.outlineVariant.withValues(alpha: 0.4)
                    : Colors.transparent),
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Leading mode icon in tinted circle
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isChat
                        ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
                        : colorScheme.primaryContainer.withValues(alpha: 0.6),
                  ),
                  child: Icon(
                    isChat ? Icons.chat_bubble_outline : Icons.auto_awesome,
                    size: 15,
                    color: isChat ? colorScheme.secondary : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              widget.isSelected ? FontWeight.bold : FontWeight.w500,
                          color: colorScheme.onSurface,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            widget.relativeTime,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                          if (!isChat &&
                              widget.item.formattedTypeAndDepth != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.item.formattedTypeAndDepth!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (showDelete)
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
