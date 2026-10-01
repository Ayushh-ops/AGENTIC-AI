import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_service.dart';
import '../main.dart';
import '../models/history_item.dart';

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
    final newItem = HistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      mode: res.mode,
      reply: res.reply,
      research: res.research,
      researchType: researchType,
      depth: depth,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
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
      _history.removeWhere((i) => i.id == id);
    });
    HistoryStorage.saveHistory(_history);
  }

  void _clearAllHistory() {
    setState(() {
      _history.clear();
    });
    HistoryStorage.saveHistory(_history);
  }

  void _selectHistoryItem(HistoryItem item) {
    setState(() {
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
    final Brightness platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark = current == ThemeMode.dark ||
        (current == ThemeMode.system && platformBrightness == Brightness.dark);
    final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
    themeModeNotifier.value = newMode;
    saveThemeMode(newMode);
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
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              const Text('About Research Assistant'),
            ],
          ),
          content: SizedBox(
            width: 520,
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
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The 3 Autonomous Agents',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Researcher: Deconstructs the topic and gathers relevant live web sources via targeted search queries.\n'
                    '• Fact-Checker: Audits sources, extracts factual claims, and evaluates multi-source corroboration with strict quote validation.\n'
                    '• Synthesizer: Compiles verified claims and cited sources into a transparent, structured report.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Research Depth',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Quick provides a fast single-search summary, Standard balances speed and corroboration, while Deep checks more sources but takes longer and uses more API calls.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Claim verification statuses',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Supported: Corroborated by 2 or more distinct domains.\n'
                    '• Single source: Found in only 1 source domain.\n'
                    '• Unsupported: Uncorroborated or contradicted by evidence.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
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
      title: const Text('Multi-Agent Research Assistant'),
      centerTitle: false,
      actions: [
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
      body: isWide
          ? Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isSidebarOpen ? 280 : 0,
                  child: _isSidebarOpen
                      ? _buildSidebarContent(isDrawer: false)
                      : const SizedBox.shrink(),
                ),
                if (_isSidebarOpen)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                Expanded(
                  child: _buildMainContent(canSubmit: canSubmit, isWide: true),
                ),
              ],
            )
          : _buildMainContent(canSubmit: canSubmit, isWide: false),
    );
  }

  Widget _buildSidebarContent({required bool isDrawer}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top: Prominent "New research" button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: FilledButton.tonalIcon(
                onPressed: _startNewResearch,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New research'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // Recent Header with Clear all action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (_history.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _clearAllHistory,
                      child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),

            // Recent List (scrollable)
            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Text(
                        'No history yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _history.length,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final isChat = item.mode == 'chat';

                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: Icon(
                            isChat
                                ? Icons.chat_bubble_outline
                                : Icons.auto_awesome,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          title: Text(
                            item.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: (!isChat && item.formattedTypeAndDepth != null)
                              ? Text(
                                  item.formattedTypeAndDepth!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.8),
                                  ),
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 14),
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteHistoryItem(item.id),
                          ),
                          onTap: () => _selectHistoryItem(item),
                        );
                      },
                    ),
            ),

            Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),

            // Bottom: About entry
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline, size: 20),
              title: const Text('About', style: TextStyle(fontSize: 14)),
              onTap: () => _showAboutDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent({required bool canSubmit, required bool isWide}) {
    final hasResultOrActivity =
        _askResponse != null || _isLoading || _errorMessage != null;

    if (!hasResultOrActivity) {
      // Centered Hero Home View
      return _buildHeroView(canSubmit);
    }

    // Result or Activity View with Compact Search Bar at Top
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 24 : 16,
            vertical: 16,
          ),
          children: [
            _buildSearchBar(canSubmit: canSubmit, isHero: false),
            const SizedBox(height: 20),
            if (_isLoading) _buildLoadingIndicator(),
            if (_errorMessage != null && !_isLoading) _buildErrorCard(),
            if (_askResponse != null && !_isLoading) ...[
              if (_askResponse!.mode == 'chat')
                _buildChatResponseCard(_askResponse!)
              else if (_askResponse!.mode == 'research' &&
                  _askResponse!.research != null)
                _buildResultSection(_askResponse!.research!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroView(bool canSubmit) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 44,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Multi-Agent Research Assistant',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Autonomous research with live web verification & cited reports',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _buildSearchBar(canSubmit: canSubmit, isHero: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar({required bool canSubmit, required bool isHero}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isHero ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isHero ? 14 : 10,
            vertical: isHero ? 4 : 2,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: colorScheme.onSurfaceVariant,
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
              FilledButton.icon(
                onPressed: canSubmit ? _executeAsk : null,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Research'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
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
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_loadingText != 'Thinking...') ...[
              const SizedBox(height: 6),
              Text(
                'Researcher, Fact-Checker, and Synthesizer agents are analyzing evidence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        borderRadius: BorderRadius.circular(12),
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
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
    final markdownContent = _cleanReportMarkdown(res.reportMarkdown);
    final colorScheme = Theme.of(context).colorScheme;

    // Build URL to title map for claims
    final sourceTitleMap = <String, String>{};
    for (final s in res.sources) {
      if (s.url.isNotEmpty) {
        sourceTitleMap[s.url] = s.title;
      }
    }

    final activeType = _activeResearchType ?? _selectedType;
    final activeDepth = _activeResearchDepth ?? _selectedDepth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Report Markdown Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Small chips at the top of the research report
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
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
                  ],
                ),
                const SizedBox(height: 16),
                MarkdownBody(
                  data: markdownContent,
                  selectable: true,
                  onTapLink: (text, href, title) {
                    if (href != null && href.isNotEmpty) {
                      _launchUrlString(href);
                    }
                  },
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    a: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Collapsible Claims List (expanded by default, shows count)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(
              'Claims & Verification Audit (${res.claims.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: res.claims.map((claim) {
              final urls = claim.sourceUrls.isNotEmpty
                  ? claim.sourceUrls
                  : (claim.sourceUrl != null ? [claim.sourceUrl!] : <String>[]);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Evidence: "${claim.evidence}"',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                      if (urls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final url in urls)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Tooltip(
                              message: url,
                              child: InkWell(
                                onTap: () => _launchUrlString(url),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (sourceTitleMap[url] != null &&
                                          sourceTitleMap[url]!.trim().isNotEmpty &&
                                          sourceTitleMap[url]!.trim() != url)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            sourceTitleMap[url]!.trim(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                          ),
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.link,
                                            size: 14,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _extractDomain(url),
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              decoration:
                                                  TextDecoration.underline,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Collapsible Sources List (collapsed by default, shows count)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.link_outlined),
            title: Text(
              'Consulted Sources (${res.sources.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: res.sources.map((source) {
              final domain = _extractDomain(source.url);
              final hasTitle = source.title.trim().isNotEmpty &&
                  source.title.trim() != source.url;

              return ListTile(
                dense: true,
                leading: const Icon(Icons.language, size: 20),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          domain,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
}

