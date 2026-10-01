import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _topicController = TextEditingController();
  final ApiService _apiService = ApiService();

  bool _isCheckingHealth = false;
  bool? _isBackendConnected;
  String _healthStatusMessage = '';

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
    _checkHealth();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isCheckingHealth = true;
    });

    final result = await _apiService.checkHealth();

    if (mounted) {
      setState(() {
        _isCheckingHealth = false;
        if (result['success'] == true) {
          _isBackendConnected = true;
          _healthStatusMessage = 'Connected (${result['service']})';
        } else {
          _isBackendConnected = false;
          _healthStatusMessage = result['error']?.toString() ?? 'Offline';
        }
      });
    }
  }

  Future<void> _executeAsk() async {
    final message = _topicController.text.trim();
    if (message.isEmpty || _isLoading) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    _loadingTimer?.cancel();
    setState(() {
      _isLoading = true;
      _loadingText = 'Thinking...';
      _errorMessage = null;
      _askResponse = null;
    });

    // For the first second show "Thinking...", then transition to detailed status
    _loadingTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        setState(() {
          _loadingText = 'Conducting autonomous web research...';
        });
      }
    });

    try {
      final res = await _apiService.ask(message);
      _loadingTimer?.cancel();
      if (mounted) {
        setState(() {
          _askResponse = res;
          _isLoading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final bool canSubmit =
        !_isLoading && _topicController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Agent Research Assistant'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              _buildHealthStatusCard(),
              const SizedBox(height: 16),
              _buildInputCard(canSubmit),
              const SizedBox(height: 20),
              if (_isLoading) _buildLoadingIndicator(),
              if (_errorMessage != null && !_isLoading) _buildErrorCard(),
              if (_askResponse != null && !_isLoading) ...[
                if (_askResponse!.mode == 'chat')
                  _buildChatResponseCard(_askResponse!)
                else if (_askResponse!.mode == 'research' &&
                    _askResponse!.research != null)
                  _buildResultSection(_askResponse!.research!),
                _buildCallsFooter(_askResponse!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthStatusCard() {
    Color bg;
    Color border;
    IconData icon;
    Color iconColor;

    if (_isCheckingHealth) {
      bg = Colors.blue.shade50;
      border = Colors.blue.shade200;
      icon = Icons.sync;
      iconColor = Colors.blue.shade700;
    } else if (_isBackendConnected == true) {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      icon = Icons.check_circle;
      iconColor = const Color(0xFF16A34A);
    } else {
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFFECACA);
      icon = Icons.warning_amber_rounded;
      iconColor = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isCheckingHealth
                  ? 'Verifying backend connection at ${_apiService.baseUrl}...'
                  : (_isBackendConnected == true
                      ? 'Backend Online: $_healthStatusMessage (${_apiService.baseUrl})'
                      : 'Backend Unreachable: $_healthStatusMessage (${_apiService.baseUrl})'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: iconColor,
              ),
            ),
          ),
          if (!_isCheckingHealth && _isBackendConnected != true)
            TextButton(
              onPressed: _checkHealth,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Widget _buildInputCard(bool canSubmit) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _topicController,
              enabled: !_isLoading,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Ask or enter a research topic',
                hintText: 'e.g., Hi, or explore Quantum Computing in 2026',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _topicController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _isLoading
                            ? null
                            : () {
                                _topicController.clear();
                                setState(() {});
                              },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canSubmit) _executeAsk();
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canSubmit ? _executeAsk : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Research', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
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
                'Researcher, Fact Checker, and Synthesizer agents are analyzing evidence.',
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
    return Card(
      elevation: 0,
      color: const Color(0xFFFEF2F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFCA5A5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Request Failed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF991B1B),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage ?? 'Unknown error occurred.',
                    style: const TextStyle(
                      color: Color(0xFF7F1D1D),
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
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Assistant',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
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

  Widget _buildCallsFooter(AskResponse res) {
    final llm = res.llmCalls ?? 0;
    final search = res.searchCalls ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      child: Center(
        child: Text(
          'LLM calls: $llm - Searches: $search',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection(ResearchResponse res) {
    final markdownContent = _cleanReportMarkdown(res.reportMarkdown);

    // Build URL to title map for claims
    final sourceTitleMap = <String, String>{};
    for (final s in res.sources) {
      if (s.url.isNotEmpty) {
        sourceTitleMap[s.url] = s.title;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Report Markdown Card (only executive summary / key findings, audit & sources are in interactive panels below)
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
            child: MarkdownBody(
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
}
