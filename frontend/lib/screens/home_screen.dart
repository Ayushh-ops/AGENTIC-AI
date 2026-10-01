import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

  bool _isLoadingResearch = false;
  String? _errorMessage;
  ResearchResponse? _response;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isCheckingHealth = true;
    });

    final result = await _apiService.checkHealth();

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

  Future<void> _executeResearch() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty || _isLoadingResearch) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoadingResearch = true;
      _errorMessage = null;
      _response = null;
    });

    try {
      final res = await _apiService.research(topic);
      setState(() {
        _response = res;
        _isLoadingResearch = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoadingResearch = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoadingResearch = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit =
        !_isLoadingResearch && _topicController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Agent Research Assistant'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Check backend connectivity',
            icon: _isCheckingHealth
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isBackendConnected == true
                        ? Icons.cloud_done
                        : (_isBackendConnected == false
                            ? Icons.cloud_off
                            : Icons.cloud_queue),
                    color: _isBackendConnected == true
                        ? Colors.green
                        : (_isBackendConnected == false
                            ? Colors.red
                            : null),
                  ),
            onPressed: _isCheckingHealth ? null : _checkHealth,
          ),
        ],
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
              if (_isLoadingResearch) _buildLoadingIndicator(),
              if (_errorMessage != null && !_isLoadingResearch) _buildErrorCard(),
              if (_response != null && !_isLoadingResearch) _buildResultSection(),
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
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _topicController,
              enabled: !_isLoadingResearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Research Topic',
                hintText: 'e.g., Quantum Computing in 2026',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _topicController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _isLoadingResearch
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
                if (canSubmit) _executeResearch();
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canSubmit ? _executeResearch : null,
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Conducting autonomous web research...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Researcher, Fact Checker, and Synthesizer agents are analyzing evidence.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
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
                    'Research Request Failed',
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

  Widget _buildResultSection() {
    final res = _response!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Report Markdown Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: MarkdownBody(
              data: res.reportMarkdown,
              selectable: true,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Collapsible Claims List
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(
              'Claims & Verification Audit (${res.claims.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: res.claims.map((claim) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Text(
                            'Evidence: "${claim.evidence}"',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                      if (claim.sourceUrls.isNotEmpty || claim.sourceUrl != null) ...[
                        const SizedBox(height: 6),
                        for (final url in claim.sourceUrls.isNotEmpty
                            ? claim.sourceUrls
                            : [claim.sourceUrl!])
                          SelectableText(
                            url,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 11,
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

        // Collapsible Sources List
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.link_outlined),
            title: Text(
              'Consulted Sources (${res.sources.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: res.sources.map((source) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.language, size: 20),
                title: Text(
                  source.title.isNotEmpty ? source.title : source.url,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: SelectableText(
                  source.url,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
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
