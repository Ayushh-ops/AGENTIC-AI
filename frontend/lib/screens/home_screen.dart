import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _topicController = TextEditingController();
  final ApiService _apiService = ApiService();

  bool _showLanding = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _pipelineTimer;
  int _activePipelineIndex = 0;
  final ScrollController _landingScrollController = ScrollController();
  final GlobalKey _howItWorksKey = GlobalKey();
  final GlobalKey _claimsKey = GlobalKey();

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

  /// Strips the first markdown heading line if its text closely matches [topic].
  /// Handles patterns like "# Research Report: <topic>" or "# <topic>".
  String _stripLeadingTitleHeading(String markdown, String topic) {
    final trimmed = markdown.trimLeft();
    if (!trimmed.startsWith('#')) return markdown;

    final firstNewline = trimmed.indexOf('\n');
    final firstLine = firstNewline == -1 ? trimmed : trimmed.substring(0, firstNewline);
    final headingText = firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();

    // Match exact topic or "Research Report: <topic>" variants
    final topicLower = topic.trim().toLowerCase();
    final headingLower = headingText.toLowerCase();
    final isRepeat = headingLower == topicLower ||
        headingLower == 'research report: $topicLower' ||
        headingLower == 'research report - $topicLower' ||
        headingLower.endsWith(': $topicLower');

    if (!isRepeat) return markdown;

    return firstNewline == -1 ? '' : trimmed.substring(firstNewline + 1).trimLeft();
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
    final bool isRunningInTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(_pulseController);

    if (!isRunningInTest) {
      _pulseController.repeat(reverse: true);
      _pipelineTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (mounted && _showLanding) {
          setState(() {
            _activePipelineIndex = (_activePipelineIndex + 1) % 3;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pipelineTimer?.cancel();
    _landingScrollController.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Clear all history?',
          style: AppTheme.displayFont(fontSize: 22),
        ),
        content: Text(
          'This will permanently delete all saved research queries and summaries.',
          style: AppTheme.bodyFont(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppTheme.bodyFont(
                fontSize: 14,
                color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? AppTheme.darkBad : AppTheme.lightBad,
              foregroundColor: Colors.white,
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
  }

  Future<void> _executeAsk() async {
    final message = _topicController.text.trim();
    if (message.isEmpty || _isLoading) return;

    final typeToRun = _selectedType;
    final depthToRun = _selectedDepth;

    FocusScope.of(context).unfocus();

    _loadingTimer?.cancel();
    setState(() {
      _showLanding = false;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: line, width: 1.0),
              borderRadius: BorderRadius.circular(AppTheme.radiusDialog),
              boxShadow: [
                isDark ? AppTheme.darkShadow : AppTheme.lightShadow,
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About Multi Agent Research Assistant',
                          style: AppTheme.displayFont(
                            fontSize: 32,
                            color: ink,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'A research assistant that searches the live web, cross-checks each claim against independent sources, and writes a cited report.',
                          style: AppTheme.bodyFont(
                            fontSize: 15,
                            color: mute,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'THE 3 AUTONOMOUS AGENTS',
                          style: AppTheme.monoFont(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: mute,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildAgentTile(
                          number: '01',
                          name: 'Researcher:',
                          role:
                              'Deconstructs the topic and gathers relevant live web sources via targeted search queries.',
                          isDark: isDark,
                        ),
                        _buildAgentTile(
                          number: '02',
                          name: 'Fact-Checker:',
                          role:
                              'Audits sources, extracts factual claims, and evaluates multi-source corroboration with strict quote validation.',
                          isDark: isDark,
                        ),
                        _buildAgentTile(
                          number: '03',
                          name: 'Synthesizer:',
                          role:
                              'Compiles verified claims and cited sources into a transparent, structured report.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'RESEARCH DEPTH',
                          style: AppTheme.monoFont(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: mute,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            border: Border.all(color: line, width: 1.0),
                          ),
                          child: Text(
                            'Quick provides a fast single-search summary, Standard balances speed and corroboration, while Deep checks more sources but takes longer and uses more API calls.',
                            style: AppTheme.bodyFont(
                              fontSize: 13.5,
                              color: mute,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Reports should still be read critically. Verify key evidence before taking critical decisions.',
                          style: AppTheme.bodyFont(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: mute,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: acc,
                      foregroundColor: onAcc,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: AppTheme.bodyFont(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgentTile({
    required String number,
    required String name,
    required String role,
    required bool isDark,
  }) {
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: line, width: 1.0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: AppTheme.monoFont(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: at,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTheme.bodyFont(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role,
                  style: AppTheme.bodyFont(
                    fontSize: 13,
                    color: mute,
                    height: 1.4,
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
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'p' : 'a';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min$ampm';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _showLanding
          ? KeyedSubtree(
              key: const ValueKey('landing_screen'),
              child: _buildLandingScreen(context),
            )
          : KeyedSubtree(
              key: const ValueKey('workspace_screen'),
              child: _buildWorkspaceScreen(context),
            ),
    );
  }

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && _landingScrollController.hasClients) {
        final viewport = RenderAbstractViewport.of(box);
        final revealOffset = viewport.getOffsetToReveal(box, 0.0).offset;
        final targetOffset = (revealOffset - 16.0).clamp(
          0.0,
          _landingScrollController.position.maxScrollExtent,
        );
        _landingScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      } else {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Widget _buildLandingScreen(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double contentPad = (screenWidth * 0.04).clamp(16.0, 32.0);

    return Scaffold(
      body: DynamicBackground(
        isLoading: false,
        accentColor: isDark ? AppTheme.darkAt : AppTheme.lightAt,
        child: Column(
          children: [
            _buildLandingTopBar(context, isDark, screenWidth),
            Expanded(
              child: SingleChildScrollView(
                controller: _landingScrollController,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: contentPad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLandingHero(context, isDark, screenWidth, screenHeight),
                          _buildLandingHowItWorks(context, isDark, screenWidth),
                          _buildLandingHonestByDesign(context, isDark, screenWidth),
                          _buildLandingCta(context, isDark, screenWidth),
                          _buildLandingFooter(context, isDark, screenWidth),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandingTopBar(BuildContext context, bool isDark, double screenWidth) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final double hPad = (screenWidth * 0.04).clamp(16.0, 48.0);
    final bool showTextLinks = screenWidth >= 860;

    return Container(
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: line, width: 1.0)),
      ),
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: hPad),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildBrandWordmark(isDark),
              ),
            ),
            const SizedBox(width: 8),
            if (showTextLinks) ...[
              TextButton(
                onPressed: () => _scrollToSection(_howItWorksKey),
                style: TextButton.styleFrom(
                  foregroundColor: mute,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: Text(
                  'How it works',
                  style: AppTheme.bodyFont(fontSize: 14, color: mute),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _scrollToSection(_claimsKey),
                style: TextButton.styleFrom(
                  foregroundColor: mute,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: Text(
                  'Claims',
                  style: AppTheme.bodyFont(fontSize: 14, color: mute),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'About Multi Agent Research Assistant',
                child: TextButton(
                  onPressed: () => _showAboutDialog(context),
                  style: TextButton.styleFrom(
                    foregroundColor: mute,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: Text(
                    'About',
                    style: AppTheme.bodyFont(fontSize: 14, color: mute),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            _buildIconButton(
              icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
              isDark: isDark,
              size: 38,
              onPressed: _toggleTheme,
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => setState(() => _showLanding = false),
              style: FilledButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: onAcc,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
              ),
              child: Text(
                'Get started',
                style: AppTheme.bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandingHero(
    BuildContext context,
    bool isDark,
    double screenWidth,
    double screenHeight,
  ) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;

    final double topPad = (screenHeight * 0.11).clamp(56.0, 120.0);
    final double h1Size = (screenWidth * 0.084).clamp(46.0, 104.0);

    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: 40),
      child: Column(
        children: [
          // Eyebrow pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: line, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _pulseAnimation,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: at,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Live search · cross-checked claims · cited reports',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyFont(fontSize: 13, color: mute),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // H1 Instrument Serif
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTheme.displayFont(
                fontSize: h1Size,
                color: ink,
                height: 0.98,
                letterSpacing: -0.02 * h1Size,
              ),
              children: [
                const TextSpan(text: 'Research that shows '),
                TextSpan(
                  text: 'its work.',
                  style: TextStyle(
                    color: at,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Lead paragraph
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              'Ask anything. Multi Agent Research Assistant searches the live web, checks each claim against independent sources, and labels how well each one is supported.',
              textAlign: TextAlign.center,
              style: AppTheme.bodyFont(
                fontSize: 18,
                color: mute,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 36),

          // Shared composer
          _buildComposer(context, isDark),
          const SizedBox(height: 18),

          // Example chips
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildLandingExampleChip('Quantum computing in 2026', isDark),
              _buildLandingExampleChip('Latest on CRISPR', isDark),
              _buildLandingExampleChip('How does RAG work?', isDark),
            ],
          ),

          // Pipeline row
          Container(
            constraints: const BoxConstraints(maxWidth: 700),
            margin: const EdgeInsets.only(top: 56),
            child: Row(
              children: [
                Expanded(child: _buildPipelineStep(0, 'Search the web', isDark)),
                Expanded(child: _buildPipelineStep(1, 'Cross-check claims', isDark)),
                Expanded(child: _buildPipelineStep(2, 'Write the report', isDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final bool canSubmit = !_isLoading && _topicController.text.trim().isNotEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isNarrow = screenWidth < 700 || constraints.maxWidth < 620;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Large multiline input box: min 3 lines (~112px), grows to 6, radius 20, padding 16, font 18, surface fill, 1px line border (accent border on focus), maxLength 200 (counter shown only above 160). Enter submits, Shift+Enter = newline.
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                    if (HardwareKeyboard.instance.isShiftPressed) {
                      return KeyEventResult.ignored;
                    } else {
                      if (canSubmit) {
                        _executeAsk();
                      }
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _topicController,
                  enabled: !_isLoading,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 200,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                    if (currentLength > 160) {
                      return Text(
                        '$currentLength/$maxLength',
                        style: AppTheme.monoFont(fontSize: 11, color: mute),
                      );
                    }
                    return null;
                  },
                  style: AppTheme.bodyFont(fontSize: 18, color: ink),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: surface,
                    hintText: 'Ask or enter a research topic',
                    hintStyle: AppTheme.bodyFont(fontSize: 18, color: mute),
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: line, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: line, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: at, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),

              // Directly BELOW the box, one row: LEFT = Type chips (General/News/Academic, pill segmented, always visible) + a "Filters" button (shows "Filters · Standard"). RIGHT = Research button. Under 700px: chips/Filters row, then full-width Research button.
              if (!isNarrow)
                Row(
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTypePills(isDark),
                            const SizedBox(width: 8),
                            _buildFiltersButton(isDark),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildResearchButton(
                      canSubmit: canSubmit,
                      isDark: isDark,
                      fullWidth: false,
                      height: 40,
                    ),
                  ],
                )
              else ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTypePills(isDark),
                      const SizedBox(width: 8),
                      _buildFiltersButton(isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildResearchButton(
                  canSubmit: canSubmit,
                  isDark: isDark,
                  fullWidth: true,
                  height: 42,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTypePills(bool isDark) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: line, width: 1.0),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypePillItem('General', 'general', isDark),
          const SizedBox(width: 2),
          _buildTypePillItem('News', 'news', isDark),
          const SizedBox(width: 2),
          _buildTypePillItem('Academic', 'academic', isDark),
        ],
      ),
    );
  }

  Widget _buildTypePillItem(String label, String value, bool isDark) {
    final isSelected = _selectedType == value;
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return InkWell(
      onTap: _isLoading
          ? null
          : () {
              setState(() => _selectedType = value);
              _saveTypePreference(value);
            },
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? acc : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.bodyFont(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? onAcc : mute,
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersButton(bool isDark) {
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final depthLabel = _selectedDepth.isNotEmpty
        ? (_selectedDepth[0].toUpperCase() + _selectedDepth.substring(1))
        : 'Standard';

    return InkWell(
      onTap: _isLoading ? null : () => _openDepthFilterPopover(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: line, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.tune, size: 14, color: mute),
            const SizedBox(width: 6),
            Text(
              'Filters · ',
              style: AppTheme.bodyFont(fontSize: 13, color: mute),
            ),
            Text(
              depthLabel,
              style: AppTheme.bodyFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDepthFilterPopover(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;

    final options = [
      {'value': 'quick', 'label': 'Quick', 'helper': '~3 claims, fast'},
      {'value': 'standard', 'label': 'Standard', 'helper': '~5 claims, balanced'},
      {'value': 'deep', 'label': 'Deep', 'helper': '~8 claims, slower, more sources'},
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: line, width: 1.0),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RESEARCH DEPTH',
                        style: AppTheme.bodyFont(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mute,
                          letterSpacing: 0.08,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...options.map((opt) {
                        final val = opt['value']!;
                        final isSelected = _selectedDepth == val;
                        return InkWell(
                          onTap: () {
                            setState(() => _selectedDepth = val);
                            _saveDepthPreference(val);
                            Navigator.of(ctx).pop();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? at.withValues(alpha: 0.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? at.withValues(alpha: 0.3) : Colors.transparent,
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? at : mute,
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: isSelected
                                      ? Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: at,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        opt['label']!,
                                        style: AppTheme.bodyFont(
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                          color: isSelected ? at : ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        opt['helper']!,
                                        style: AppTheme.bodyFont(
                                          fontSize: 12,
                                          color: mute,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLandingExampleChip(String text, bool isDark) {
    return _HoverChip(
      text: text,
      isDark: isDark,
      onTap: () {
        _topicController.text = text;
        setState(() {});
      },
    );
  }

  Widget _buildPipelineStep(int index, String label, bool isDark) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final bool isActive = _activePipelineIndex == index;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 2,
                color: index == 0 ? Colors.transparent : line,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? at : bg,
                border: Border.all(
                  color: isActive ? at : line,
                  width: 2.0,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 2,
                color: index == 2 ? Colors.transparent : line,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTheme.bodyFont(
            fontSize: 13,
            color: mute,
          ),
        ),
      ],
    );
  }

  Widget _buildLandingHowItWorks(
    BuildContext context,
    bool isDark,
    double screenWidth,
  ) {
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final bool isWide = screenWidth >= 860;
    final h2Size = (screenWidth * 0.05).clamp(34.0, 56.0);

    return Container(
      padding: const EdgeInsets.only(top: 84),
      child: Column(
        key: _howItWorksKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOW IT WORKS',
            style: AppTheme.monoFont(
              fontSize: 13,
              color: at,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'Three agents, one rule: no claim without a source.',
              style: AppTheme.displayFont(
                fontSize: h2Size,
                color: ink,
                height: 1.04,
              ),
            ),
          ),
          const SizedBox(height: 36),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: line, width: 1.0)),
            ),
            child: Column(
              children: [
                _buildHowStepRow(
                  number: '1',
                  title: 'Researcher',
                  description:
                      'Searches the live web for your topic and gathers sources, skipping known low-quality and social sites.',
                  isWide: isWide,
                  isDark: isDark,
                ),
                _buildHowStepRow(
                  number: '2',
                  title: 'Fact-Checker',
                  description:
                      'Extracts claims, looks for the same fact in other independent domains, and keeps only quotes it can find in the source text.',
                  isWide: isWide,
                  isDark: isDark,
                ),
                _buildHowStepRow(
                  number: '3',
                  title: 'Synthesizer',
                  description:
                      'Writes a short report. Its references list only sources that back a claim, and weak claims are never labelled corroborated.',
                  isWide: isWide,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowStepRow({
    required String number,
    required String title,
    required String description,
    required bool isWide,
    required bool isDark,
  }) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line, width: 1.0)),
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    number,
                    style: AppTheme.displayFont(
                      fontSize: 56,
                      color: at,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 10,
                  child: Text(
                    title,
                    style: AppTheme.bodyFont(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 13,
                  child: Text(
                    description,
                    style: AppTheme.bodyFont(
                      fontSize: 16,
                      color: mute,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    number,
                    style: AppTheme.displayFont(
                      fontSize: 44,
                      color: at,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodyFont(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: AppTheme.bodyFont(
                          fontSize: 15,
                          color: mute,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLandingHonestByDesign(
    BuildContext context,
    bool isDark,
    double screenWidth,
  ) {
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final ok = isDark ? AppTheme.darkOk : AppTheme.lightOk;
    final warn = isDark ? AppTheme.darkWarn : AppTheme.lightWarn;
    final bad = isDark ? AppTheme.darkBad : AppTheme.lightBad;
    final h2Size = (screenWidth * 0.05).clamp(34.0, 56.0);
    final bool isStacked = screenWidth < 860;

    return Container(
      padding: const EdgeInsets.only(top: 84),
      child: Column(
        key: _claimsKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HONEST BY DESIGN',
            style: AppTheme.monoFont(
              fontSize: 13,
              color: at,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'Every claim carries its own label.',
              style: AppTheme.displayFont(
                fontSize: h2Size,
                color: ink,
                height: 1.04,
              ),
            ),
          ),
          const SizedBox(height: 34),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: line, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: isStacked
                ? Column(
                    children: [
                      _buildLegendCell(
                        label: 'Corroborated',
                        color: ok,
                        marker: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: ok,
                            shape: BoxShape.circle,
                          ),
                        ),
                        description: 'Two or more independent domains state the same fact.',
                        hasBorder: true,
                        isDark: isDark,
                        isBottomBorder: true,
                      ),
                      _buildLegendCell(
                        label: 'Single source',
                        color: warn,
                        marker: Transform.rotate(
                          angle: 0.785398,
                          child: Container(
                            width: 7,
                            height: 7,
                            color: warn,
                          ),
                        ),
                        description: 'Only one source found. Treat it as a lead, not a fact.',
                        hasBorder: true,
                        isDark: isDark,
                        isBottomBorder: true,
                      ),
                      _buildLegendCell(
                        label: 'Unsupported',
                        color: bad,
                        marker: Container(
                          width: 7,
                          height: 7,
                          color: bad,
                        ),
                        description: 'No verified source backed it up. Treat it as unconfirmed.',
                        hasBorder: false,
                        isDark: isDark,
                        isBottomBorder: false,
                      ),
                    ],
                  )
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildLegendCell(
                            label: 'Corroborated',
                            color: ok,
                            marker: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: ok,
                                shape: BoxShape.circle,
                              ),
                            ),
                            description: 'Two or more independent domains state the same fact.',
                            hasBorder: true,
                            isDark: isDark,
                            isBottomBorder: false,
                          ),
                        ),
                        Expanded(
                          child: _buildLegendCell(
                            label: 'Single source',
                            color: warn,
                            marker: Transform.rotate(
                              angle: 0.785398,
                              child: Container(
                                width: 7,
                                height: 7,
                                color: warn,
                              ),
                            ),
                            description: 'Only one source found. Treat it as a lead, not a fact.',
                            hasBorder: true,
                            isDark: isDark,
                            isBottomBorder: false,
                          ),
                        ),
                        Expanded(
                          child: _buildLegendCell(
                            label: 'Unsupported',
                            color: bad,
                            marker: Container(
                              width: 7,
                              height: 7,
                              color: bad,
                            ),
                            description: 'No verified source backed it up. Treat it as unconfirmed.',
                            hasBorder: false,
                            isDark: isDark,
                            isBottomBorder: false,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendCell({
    required String label,
    required Color color,
    required Widget marker,
    required String description,
    required bool hasBorder,
    required bool isDark,
    required bool isBottomBorder,
  }) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        border: hasBorder
            ? (isBottomBorder
                ? Border(bottom: BorderSide(color: line, width: 1.0))
                : Border(right: BorderSide(color: line, width: 1.0)))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: color, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                marker,
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.monoFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: AppTheme.bodyFont(
              fontSize: 15,
              color: mute,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandingCta(BuildContext context, bool isDark, double screenWidth) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final h2Size = (screenWidth * 0.04).clamp(30.0, 44.0);

    return Container(
      margin: const EdgeInsets.only(top: 90),
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: line, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Ask your first question.',
              textAlign: TextAlign.center,
              style: AppTheme.displayFont(
                fontSize: h2Size,
                color: ink,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => setState(() => _showLanding = false),
            style: FilledButton.styleFrom(
              backgroundColor: acc,
              foregroundColor: onAcc,
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Text(
              'Get started',
              style: AppTheme.bodyFont(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandingFooter(BuildContext context, bool isDark, double screenWidth) {
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 40),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 10,
        children: [
          Text(
            'Multi Agent Research Assistant',
            style: AppTheme.bodyFont(
              fontSize: 14,
              color: mute,
            ),
          ),
          Text(
            'Reports should still be read critically.',
            style: AppTheme.bodyFont(
              fontSize: 14,
              color: mute,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceScreen(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth >= 860;
    final bool canSubmit =
        !_isLoading && _topicController.text.trim().isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final appBar = _buildTopBar(
      context: context,
      isWide: isWide,
      canSubmit: canSubmit,
      isDark: isDark,
    );

    return Scaffold(
      appBar: appBar,
      drawer: isWide
          ? null
          : Drawer(
              width: 288,
              backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              child: _buildSidebarContent(isDrawer: true),
            ),
      body: DynamicBackground(
        isLoading: _isLoading,
        accentColor: isDark ? AppTheme.darkAt : AppTheme.lightAt,
        child: isWide
            ? Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    width: _isSidebarOpen ? 288 : 0,
                    child: _isSidebarOpen
                        ? _buildSidebarContent(isDrawer: false)
                        : const SizedBox.shrink(),
                  ),
                  if (_isSidebarOpen)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: isDark ? AppTheme.darkLines : AppTheme.lightLines,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final bad = isDark ? AppTheme.darkBad : AppTheme.lightBad;

    return Material(
      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: App logo mark + close button on drawer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(child: _buildBrandWordmark(isDark, twoLines: true)),
                  if (isDrawer)
                    _buildIconButton(
                      icon: Icons.chevron_left,
                      tooltip: 'Close sidebar',
                      isDark: isDark,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),

            // Top: Full-width New research button (.btn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: NewResearchButton(onPressed: _startNewResearch),
            ),

            // Recent Header with Clear all action
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    'RECENT',
                    style: AppTheme.monoFont(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: mute,
                    ),
                  ),
                  const Spacer(),
                  if (_history.isNotEmpty)
                    InkWell(
                      onTap: _confirmClearAllHistory,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Clear all',
                          style: AppTheme.monoFont(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: bad,
                          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 26,
                color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
              ),
              const SizedBox(height: 8),
              Text(
                'No research history yet',
                style: AppTheme.bodyFont(
                  fontSize: 13,
                  color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Text(
        title.toUpperCase(),
        style: AppTheme.monoFont(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.08,
          color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
        ),
      ),
    );
  }

  Widget _buildMainContent({required bool canSubmit, required bool isWide}) {
    final hasResultOrActivity =
        _askResponse != null || _isLoading || _errorMessage != null;

    final childKey = _isLoading
        ? 'loading'
        : (_askResponse != null
            ? 'result_${_selectedHistoryItemId ?? _askResponse!.research?.topic}'
            : (_errorMessage != null ? 'error' : 'hero'));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(childKey),
        child: !hasResultOrActivity
            ? _buildHeroView(canSubmit)
            : _buildResultView(canSubmit),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar({
    required BuildContext context,
    required bool isWide,
    required bool canSubmit,
    required bool isDark,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 700;
    final bool isSidebarVisible = isWide && _isSidebarOpen;
    final double hPad = screenWidth >= 1000 ? 24.0 : 16.0;
    final bool hasResultOrActivity =
        _isLoading || _askResponse != null || _errorMessage != null;
    final double topBarHeight = hasResultOrActivity ? (isNarrow ? 164.0 : 118.0) : 68.0;

    return PreferredSize(
      preferredSize: Size.fromHeight(topBarHeight),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppTheme.darkLines : AppTheme.lightLines,
              width: 1.0,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Row 1: sidebar-toggle icon button, [wordmark ONLY if sidebar is hidden], spacer, About text button, theme icon button.
                Row(
                  children: [
                    Builder(
                      builder: (ctx) => _buildIconButton(
                        icon: Icons.menu,
                        tooltip: 'Toggle sidebar',
                        isDark: isDark,
                        size: 36,
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
                    if (!isSidebarVisible) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: _buildBrandWordmark(isDark),
                      ),
                    ],
                    const Spacer(),
                    _buildAboutLink(isDark),
                    const SizedBox(width: 4),
                    _buildIconButton(
                      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
                      isDark: isDark,
                      size: 36,
                      onPressed: _toggleTheme,
                    ),
                  ],
                ),
                if (hasResultOrActivity) ...[
                  const SizedBox(height: 10),
                  // Compact top-bar search (input + Filters + Research, no big chips)
                  if (!isNarrow)
                    Row(
                      children: [
                        Expanded(
                          child: _buildCompactSearchInput(canSubmit: canSubmit, isDark: isDark),
                        ),
                        const SizedBox(width: 8),
                        _buildFiltersButton(isDark),
                        const SizedBox(width: 8),
                        _buildResearchButton(canSubmit: canSubmit, isDark: isDark, fullWidth: false, height: 40),
                      ],
                    )
                  else ...[
                    _buildCompactSearchInput(canSubmit: canSubmit, isDark: isDark),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFiltersButton(isDark),
                        const Spacer(),
                        _buildResearchButton(canSubmit: canSubmit, isDark: isDark, fullWidth: false, height: 40),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required VoidCallback onPressed,
    double size = 42,
  }) {
    return _HoverIconButton(
      icon: icon,
      tooltip: tooltip,
      isDark: isDark,
      onPressed: onPressed,
      size: size,
    );
  }

  Widget _buildAboutLink(bool isDark) {
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    return Tooltip(
      message: 'About Multi Agent Research Assistant',
      child: TextButton(
        onPressed: () => _showAboutDialog(context),
        style: TextButton.styleFrom(
          foregroundColor: mute,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'About',
          style: AppTheme.bodyFont(fontSize: 14, color: mute),
        ),
      ),
    );
  }

  Widget _buildBrandWordmark(bool isDark, {bool twoLines = false}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWideText = screenWidth >= 700;
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;

    return InkWell(
      onTap: () {
        if (_showLanding) {
          if (_landingScrollController.hasClients) {
            _landingScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } else {
          setState(() => _showLanding = true);
        }
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: acc,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: CustomPaint(
                size: const Size(26, 26),
                painter: _LogoPainter(color: onAcc),
              ),
            ),
            const SizedBox(width: 8),
            if (twoLines)
              Flexible(
                child: Text(
                  'Multi Agent\nResearch Assistant',
                  softWrap: true,
                  style: AppTheme.displayFont(
                    fontSize: 20,
                    color: ink,
                    height: 1.2,
                  ),
                ),
              )
            else
              Flexible(
                child: Text(
                  isWideText ? 'Multi Agent Research Assistant' : 'Multi Agent',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTheme.displayFont(
                    fontSize: 22,
                    color: ink,
                    height: 1.0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactSearchInput({
    required bool canSubmit,
    required bool isDark,
  }) {
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 16, color: mute),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _topicController,
              enabled: !_isLoading,
              textInputAction: TextInputAction.search,
              style: AppTheme.bodyFont(
                fontSize: 14,
                color: ink,
              ),
              decoration: InputDecoration(
                hintText: 'Ask or enter a research topic',
                hintStyle: AppTheme.bodyFont(
                  fontSize: 14,
                  color: mute,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canSubmit) _executeAsk();
              },
            ),
          ),
          if (_topicController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear, size: 14, color: mute),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: _isLoading
                  ? null
                  : () {
                      _topicController.clear();
                      setState(() {});
                    },
            ),
        ],
      ),
    );
  }

  Widget _buildResearchButton({
    required bool canSubmit,
    required bool isDark,
    bool fullWidth = false,
    double height = 44,
  }) {
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;

    return SizedBox(
      height: height,
      width: fullWidth ? double.infinity : null,
      child: FilledButton(
        onPressed: canSubmit ? _executeAsk : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.transparent;
            }
            return acc;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return at.withValues(alpha: 0.6);
            }
            return onAcc;
          }),
          elevation: WidgetStateProperty.resolveWith<double>((states) {
            if (states.contains(WidgetState.hovered) && !states.contains(WidgetState.disabled)) {
              return 2.0;
            }
            return 0.0;
          }),
          side: WidgetStateProperty.resolveWith<BorderSide>((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: at.withValues(alpha: 0.5), width: 1.0);
            }
            return BorderSide.none;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 22),
          ),
          textStyle: WidgetStateProperty.all(
            AppTheme.bodyFont(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          animationDuration: const Duration(milliseconds: 150),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _isLoading
              ? SizedBox(
                  key: const ValueKey('ws_spinner'),
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(onAcc),
                  ),
                )
              : const Text(
                  'Research',
                  key: ValueKey('ws_label'),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroView(bool canSubmit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Center(
      key: const ValueKey('hero_view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Empty state heading (.empty h2.serif)
              Text(
                'What shall we look into?',
                textAlign: TextAlign.center,
                style: AppTheme.displayFont(
                  fontSize: 44,
                  color: ink,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 12),

              // Subtext (.empty text)
              Text(
                'Type a topic below to begin.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyFont(
                  fontSize: 16,
                  color: mute,
                ),
              ),
              const SizedBox(height: 32),

              // Shared composer
              _buildComposer(context, isDark),
              const SizedBox(height: 24),

              // Starter Example Prompts (.eg button)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildExampleChip('Quantum computing in 2026', isDark),
                  _buildExampleChip('Latest on CRISPR', isDark),
                  _buildExampleChip('How does RAG work?', isDark),
                ],
              ),
              const SizedBox(height: 48),

              // Footer link
              TextButton(
                onPressed: () => _showAboutDialog(context),
                style: TextButton.styleFrom(
                  foregroundColor: mute,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: Text(
                  'About Multi Agent Research Assistant',
                  style: AppTheme.bodyFont(fontSize: 13, color: mute),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExampleChip(String prompt, bool isDark) {
    return _HoverChip(
      text: prompt,
      isDark: isDark,
      onTap: () => _onSelectExamplePrompt(prompt),
    );
  }

  Widget _buildResultView(bool canSubmit) {
    return Center(
      key: const ValueKey('result_view'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
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
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Loading heading (.run .serif)
          Text(
            'Working on it…',
            style: AppTheme.displayFont(
              fontSize: 36,
              color: ink,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 28),

          // Steps list (.run ol / li)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepRow(
                  label: 'Searching live sources',
                  isDone: _loadingText != 'Thinking...',
                  isActive: _loadingText == 'Thinking...',
                  isDark: isDark,
                ),
                _buildStepRow(
                  label: 'Cross-checking claims',
                  isDone: false,
                  isActive: _loadingText != 'Thinking...',
                  isDark: isDark,
                ),
                _buildStepRow(
                  label: 'Validating quotes',
                  isDone: false,
                  isActive: false,
                  isDark: isDark,
                ),
                _buildStepRow(
                  label: 'Writing the report',
                  isDone: false,
                  isActive: false,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required String label,
    required bool isDone,
    required bool isActive,
    required bool isDark,
  }) {
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? at : Colors.transparent,
              border: Border.all(
                color: (isDone || isActive) ? at : line,
                width: 2.0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            style: AppTheme.bodyFont(
              fontSize: 14,
              color: isActive ? ink : mute,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bad = isDark ? AppTheme.darkBad : AppTheme.lightBad;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: bad, width: 1.0),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: bad, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request Failed',
                  style: AppTheme.bodyFont(
                    fontWeight: FontWeight.bold,
                    color: bad,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _errorMessage ?? 'Unknown error occurred.',
                  style: AppTheme.bodyFont(
                    color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatResponseCard(AskResponse res) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: line, width: 1.0),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assistant',
            style: AppTheme.displayFont(
              fontSize: 20,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            res.reply ?? '',
            style: AppTheme.bodyFont(
              fontSize: 15,
              height: 1.55,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection(ResearchResponse res) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final ok = isDark ? AppTheme.darkOk : AppTheme.lightOk;
    final warn = isDark ? AppTheme.darkWarn : AppTheme.lightWarn;
    final bad = isDark ? AppTheme.darkBad : AppTheme.lightBad;

    final activeType = _activeResearchType ?? _selectedType;
    final activeDepth = _activeResearchDepth ?? _selectedDepth;

    final supportedCount =
        res.claims.where((c) => c.status.toLowerCase() == 'supported').length;
    final singleSourceCount =
        res.claims.where((c) => c.status.toLowerCase() == 'single_source').length;
    final unsupportedCount =
        res.claims.where((c) => c.status.toLowerCase() == 'unsupported').length;

    // Strip the first heading if it only repeats the report title
    final cleanedMarkdown = _stripLeadingTitleHeading(
      _cleanReportMarkdown(res.reportMarkdown),
      res.topic,
    );

    // Uppercase h1-h3 heading text so the muted label style looks like a section header
    final uppercasedMarkdown = cleanedMarkdown.split('\n').map((l) {
      final m = RegExp(r'^(#{1,3}) (.+)$').firstMatch(l);
      if (m != null) return '${m.group(1)} ${m.group(2)!.toUpperCase()}';
      return l;
    }).join('\n');

    // Extract bullet points for Key findings (.fl) if present in report
    final lines = cleanedMarkdown.split('\n');
    final bulletLines = lines
        .where((l) => l.trim().startsWith('- ') || l.trim().startsWith('* '))
        .map((l) => l.trim().substring(2).trim())
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Report Chips (.bd)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildReportChip('Type: ${_formatType(activeType)}', isDark),
            _buildReportChip('Depth: ${_formatDepth(activeDepth)}', isDark),
          ],
        ),
        const SizedBox(height: 12),

        // 2. Report Title (.rp h2)
        Text(
          res.topic,
          style: AppTheme.displayFont(
            fontSize: 42,
            color: ink,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 22),

        // 3. Tally Box (.stats)
        _StaggeredEntrance(
          index: 0,
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(color: line, width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTallyCol(
                    count: supportedCount,
                    label: 'Corroborated',
                    color: ok,
                    isDark: isDark,
                    hasBorder: true,
                  ),
                ),
                Expanded(
                  child: _buildTallyCol(
                    count: singleSourceCount,
                    label: 'Single source',
                    color: warn,
                    isDark: isDark,
                    hasBorder: true,
                  ),
                ),
                Expanded(
                  child: _buildTallyCol(
                    count: unsupportedCount,
                    label: 'Unsupported',
                    color: bad,
                    isDark: isDark,
                    hasBorder: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 4. Summary / Report Body (.sum + markdown)
        _StaggeredEntrance(
          index: 1,
          child: MarkdownBody(
            data: uppercasedMarkdown,
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null && href.isNotEmpty) {
                _launchUrlString(href);
              }
            },
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: AppTheme.bodyFont(
                fontSize: 17,
                height: 1.6,
                color: ink,
              ),
              // Headings: Geist 600, 13px, UPPERCASE, muted color — not Instrument Serif/bold
              h1: AppTheme.bodyFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
                color: mute,
                height: 1.2,
              ),
              h1Padding: const EdgeInsets.only(top: 20, bottom: 8),
              h2: AppTheme.bodyFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
                color: mute,
                height: 1.2,
              ),
              h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
              h3: AppTheme.bodyFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
                color: mute,
                height: 1.2,
              ),
              h3Padding: const EdgeInsets.only(top: 20, bottom: 8),
              h4: AppTheme.monoFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
                color: mute,
              ),
              listBullet: AppTheme.monoFont(
                fontSize: 13,
                color: at,
              ),
              a: TextStyle(
                color: at,
                decoration: TextDecoration.underline,
              ),
              blockquote: AppTheme.bodyFont(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: mute,
              ),
              blockquoteDecoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: line, width: 1.0),
              ),
              blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 34),

        // 5. Key findings (.fl) if bullets were extracted
        if (bulletLines.isNotEmpty) ...[
          _StaggeredEntrance(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'KEY FINDINGS',
                  style: AppTheme.monoFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                    color: mute,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < bulletLines.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: line, width: 1.0),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (i + 1).toString().padLeft(2, '0'),
                          style: AppTheme.monoFont(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: at,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            bulletLines[i],
                            style: AppTheme.bodyFont(
                              fontSize: 16,
                              color: ink,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 34),
        ],

        // 6. Claims and evidence (.cl)
        if (res.claims.isNotEmpty) ...[
          _StaggeredEntrance(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'CLAIMS AND EVIDENCE',
                  style: AppTheme.monoFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                    color: mute,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < res.claims.length; i++)
                  _buildClaimBlock(
                    claim: res.claims[i],
                    isLast: i == res.claims.length - 1,
                    isDark: isDark,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 34),
        ],

        // 7. Consulted sources panel
        if (res.sources.isNotEmpty) ...[
          _StaggeredEntrance(
            index: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'CONSULTED SOURCES',
                  style: AppTheme.monoFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                    color: mute,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: line, width: 1.0),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < res.sources.length; i++)
                        InkWell(
                          onTap: () => _launchUrlString(res.sources[i].url),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: i > 0
                                  ? Border(top: BorderSide(color: line, width: 1.0))
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (res.sources[i].title.trim().isNotEmpty &&
                                          res.sources[i].title.trim() != res.sources[i].url)
                                        Text(
                                          res.sources[i].title.trim(),
                                          style: AppTheme.bodyFont(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: ink,
                                          ),
                                        ),
                                      Text(
                                        _extractDomain(res.sources[i].url),
                                        style: AppTheme.monoFont(
                                          fontSize: 12,
                                          color: mute,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.open_in_new, size: 14, color: mute),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReportChip(String label, bool isDark) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: line, width: 1.0),
      ),
      child: Text(
        label,
        style: AppTheme.monoFont(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: mute,
        ),
      ),
    );
  }

  Widget _buildTallyCol({
    required int count,
    required String label,
    required Color color,
    required bool isDark,
    required bool hasBorder,
  }) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        border: hasBorder
            ? Border(right: BorderSide(color: line, width: 1.0))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: AppTheme.displayFont(
              fontSize: 44,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyFont(
              fontSize: 13,
              color: mute,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimBlock({
    required ClaimItem claim,
    required bool isLast,
    required bool isDark,
  }) {
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final ok = isDark ? AppTheme.darkOk : AppTheme.lightOk;
    final warn = isDark ? AppTheme.darkWarn : AppTheme.lightWarn;
    final bad = isDark ? AppTheme.darkBad : AppTheme.lightBad;

    final statusLower = claim.status.toLowerCase();
    final Color badgeColor;
    final String badgeLabel;
    final Widget badgeMarker;

    switch (statusLower) {
      case 'supported':
        badgeColor = ok;
        badgeLabel = 'Corroborated';
        badgeMarker = Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: ok,
            shape: BoxShape.circle,
          ),
        );
        break;
      case 'single_source':
        badgeColor = warn;
        badgeLabel = 'Single source';
        badgeMarker = Transform.rotate(
          angle: 0.785398, // 45 degrees diamond
          child: Container(
            width: 7,
            height: 7,
            color: warn,
          ),
        );
        break;
      case 'unsupported':
      default:
        badgeColor = bad;
        badgeLabel = 'Unsupported';
        badgeMarker = Container(
          width: 7,
          height: 7,
          color: bad,
        );
        break;
    }

    final urls = claim.sourceUrls.isNotEmpty
        ? claim.sourceUrls
        : (claim.sourceUrl != null ? [claim.sourceUrl!] : <String>[]);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: line, width: 1.0),
          bottom: isLast ? BorderSide(color: line, width: 1.0) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge (.bd)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: badgeColor, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                badgeMarker,
                const SizedBox(width: 7),
                Text(
                  badgeLabel,
                  style: AppTheme.monoFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.04,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Claim Statement (.cl p)
          Text(
            claim.statement,
            style: AppTheme.bodyFont(
              fontSize: 17,
              color: ink,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),

          // Evidence quote blockquote (.cl blockquote)
          if (claim.evidence.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: line, width: 1.0),
              ),
              child: Text(
                '“${claim.evidence}”',
                style: AppTheme.bodyFont(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: mute,
                  height: 1.45,
                ),
              ),
            ),

          // Source domain link chips (.mt a)
          if (urls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final url in urls)
                  InkWell(
                    onTap: () => _launchUrlString(url),
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        border: Border.all(color: line, width: 1.0),
                      ),
                      child: Text(
                        _extractDomain(url),
                        style: AppTheme.monoFont(
                          fontSize: 13,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
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
}

/// History tile replicating `.hi` from reference prototype.
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
    final isChat = widget.item.mode == 'chat';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final at = isDark ? AppTheme.darkAt : AppTheme.lightAt;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;

    final showDelete = !widget.isWide || _isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isSelected ? bg : (_isHovered ? bg : Colors.transparent),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: widget.isSelected
                  ? Border.all(color: line, width: 1.0)
                  : (_isHovered
                      ? Border.all(color: line, width: 1.0)
                      : Border.all(color: Colors.transparent, width: 1.0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 8px circular dot (.hi i: 8x8 dot in --at or ring in --mute for chat)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isChat ? Colors.transparent : at,
                    border: isChat ? Border.all(color: mute, width: 2) : null,
                  ),
                ),
                const SizedBox(width: 10),

                // Title and subtle secondary line
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyFont(
                          fontSize: 14,
                          fontWeight:
                              widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: ink,
                        ),
                      ),
                      if (!isChat && widget.item.formattedTypeAndDepth != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.item.formattedTypeAndDepth!,
                          style: AppTheme.monoFont(
                            fontSize: 11,
                            color: mute,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Timestamp (.hi small)
                Text(
                  widget.relativeTime,
                  style: AppTheme.monoFont(
                    fontSize: 11,
                    color: mute,
                  ),
                ),

                if (showDelete) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.close, size: 14, color: mute),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    onPressed: widget.onDelete,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 150ms animated border & fill hover chip
class _HoverChip extends StatefulWidget {
  final String text;
  final bool isDark;
  final VoidCallback onTap;

  const _HoverChip({
    required this.text,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_HoverChip> createState() => _HoverChipState();
}

class _HoverChipState extends State<_HoverChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final mute = widget.isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final surface = widget.isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final ink = widget.isDark ? AppTheme.darkInk : AppTheme.lightInk;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered ? surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: _isHovered ? ink : line,
              width: 1.0,
            ),
          ),
          child: Text(
            widget.text,
            style: AppTheme.bodyFont(
              fontSize: 14,
              color: _isHovered ? ink : mute,
            ),
          ),
        ),
      ),
    );
  }
}

/// 150ms animated border & fill hover icon button
class _HoverIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onPressed;
  final double size;

  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onPressed,
    this.size = 42,
  });

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = widget.isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final ink = widget.isDark ? AppTheme.darkInk : AppTheme.lightInk;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: _isHovered ? ink : line,
                width: 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 18, color: ink),
          ),
        ),
      ),
    );
  }
}

/// Staggered fade and 8px slide-up entrance for result report blocks
class _StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int index;

  const _StaggeredEntrance({
    super.key, // ignore: unused_element_parameter
    required this.child,
    required this.index,
  });

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _delayTimer;

  static const _delayStep = Duration(milliseconds: 40);
  static const _duration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _controller = AnimationController(vsync: this, duration: _duration);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04), // ~8px on typical block height
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (isTest) {
      _controller.value = 1.0;
    } else {
      final delay = _delayStep * widget.index;
      _delayTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color color;

  const _LogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double cy = size.height / 2.0;
    const double r = 6.6;

    final p1 = Offset(cx, cy - r);
    final p2 = Offset(cx + r * math.cos(math.pi / 6), cy + r * math.sin(math.pi / 6));
    final p3 = Offset(cx - r * math.cos(math.pi / 6), cy + r * math.sin(math.pi / 6));
    final center = Offset(cx, cy);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    canvas.drawPath(path, linePaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 3 small circles at triangle vertices (r=2.2)
    canvas.drawCircle(p1, 2.2, fillPaint);
    canvas.drawCircle(p2, 2.2, fillPaint);
    canvas.drawCircle(p3, 2.2, fillPaint);

    // Filled center dot (r=2.6)
    canvas.drawCircle(center, 2.6, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => color != oldDelegate.color;
}
