import 'package:flutter/material.dart';
import '../api/api_config.dart';
import '../main.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Settings dialog displaying API Keys, Research Defaults, Appearance, and Data.
class SettingsDialog extends StatefulWidget {
  final String? baseUrl;
  final VoidCallback? onHistoryCleared;

  const SettingsDialog({
    super.key,
    this.baseUrl,
    this.onHistoryCleared,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final TextEditingController _groqController = TextEditingController();
  final TextEditingController _tavilyController = TextEditingController();

  String? _groqError;
  String? _tavilyError;

  @override
  void dispose() {
    _groqController.dispose();
    _tavilyController.dispose();
    super.dispose();
  }

  void _onAddGroqKey(SettingsService settings) async {
    final text = _groqController.text.trim();
    final err = SettingsService.validateKey(text, settings.groqKeys);
    if (err != null) {
      setState(() => _groqError = err);
      return;
    }
    setState(() => _groqError = null);
    await settings.addGroqKey(text);
    _groqController.clear();
  }

  void _onAddTavilyKey(SettingsService settings) async {
    final text = _tavilyController.text.trim();
    final err = SettingsService.validateKey(text, settings.tavilyKeys);
    if (err != null) {
      setState(() => _tavilyError = err);
      return;
    }
    setState(() => _tavilyError = null);
    await settings.addTavilyKey(text);
    _tavilyController.clear();
  }

  void _confirmClearAllKeys(SettingsService settings, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusDialog),
          side: BorderSide(
            color: isDark ? AppTheme.darkLines : AppTheme.lightLines,
          ),
        ),
        title: Text(
          'Clear all API keys?',
          style: AppTheme.displayFont(
            fontSize: 24,
            color: isDark ? AppTheme.darkInk : AppTheme.lightInk,
          ),
        ),
        content: Text(
          'This will remove all custom Groq and Tavily keys stored in this browser.',
          style: AppTheme.bodyFont(
            fontSize: 14,
            color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
          ),
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
              settings.clearAllKeys();
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusDialog),
          side: BorderSide(
            color: isDark ? AppTheme.darkLines : AppTheme.lightLines,
          ),
        ),
        title: Text(
          'Clear all history?',
          style: AppTheme.displayFont(
            fontSize: 24,
            color: isDark ? AppTheme.darkInk : AppTheme.lightInk,
          ),
        ),
        content: Text(
          'This will permanently delete all saved research queries and summaries.',
          style: AppTheme.bodyFont(
            fontSize: 14,
            color: isDark ? AppTheme.darkMuted : AppTheme.lightMuted,
          ),
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
              widget.onHistoryCleared?.call();
            },
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.darkInk : AppTheme.lightInk;
    final mute = isDark ? AppTheme.darkMuted : AppTheme.lightMuted;
    final line = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    final onAcc = isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc;

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 600;
    final effectiveBaseUrl = widget.baseUrl ?? ApiConfig.defaultBaseUrl;
    final isHttpInsecure = SettingsService.isUnencryptedHttp(effectiveBaseUrl);

    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final settings = SettingsService.instance;
        final hasCustomKeys =
            settings.groqKeys.isNotEmpty || settings.tavilyKeys.isNotEmpty;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: isSmall
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: isSmall
                ? const BoxConstraints.expand()
                : const BoxConstraints(maxWidth: 560, maxHeight: 740),
            padding: EdgeInsets.all(isSmall ? 20 : 28),
            decoration: BoxDecoration(
              color: surface,
              border: isSmall ? null : Border.all(color: line, width: 1.0),
              borderRadius: isSmall
                  ? BorderRadius.zero
                  : BorderRadius.circular(AppTheme.radiusDialog),
              boxShadow: [
                isDark ? AppTheme.darkShadow : AppTheme.lightShadow,
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Settings',
                      style: AppTheme.displayFont(
                        fontSize: 32,
                        color: ink,
                        height: 1.1,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: mute, size: 20),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: line, height: 1.0),

                // Scrollable Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- SECTION A: API KEYS ---
                        _buildSectionHeader('API Keys', mute),

                        // Status Line
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: hasCustomKeys
                                ? (isDark
                                    ? AppTheme.darkOk.withValues(alpha: 0.15)
                                    : AppTheme.lightOk.withValues(alpha: 0.1))
                                : (isDark
                                    ? AppTheme.darkLines
                                    : AppTheme.lightLines),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: hasCustomKeys
                                      ? (isDark
                                          ? AppTheme.darkOk
                                          : AppTheme.lightOk)
                                      : mute,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                hasCustomKeys
                                    ? 'Using your keys'
                                    : "Using the backend's keys",
                                style: AppTheme.monoFont(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: hasCustomKeys
                                      ? (isDark
                                          ? AppTheme.darkOk
                                          : AppTheme.lightOk)
                                      : mute,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Note text
                        Text(
                          'Stored only in this browser (not encrypted). Sent to your backend with each request. Leave empty to use the keys configured on the backend.',
                          style: AppTheme.bodyFont(fontSize: 13, color: mute),
                        ),
                        const SizedBox(height: 12),

                        // Insecure HTTP warning banner
                        if (isHttpInsecure) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkWarn.withValues(alpha: 0.12)
                                  : AppTheme.lightWarn.withValues(alpha: 0.08),
                              border: Border.all(
                                color: isDark
                                    ? AppTheme.darkWarn
                                    : AppTheme.lightWarn,
                                width: 1.0,
                              ),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: isDark
                                      ? AppTheme.darkWarn
                                      : AppTheme.lightWarn,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Warning: Backend URL ($effectiveBaseUrl) uses unencrypted HTTP. API keys travel in plaintext over the network. Use HTTPS in production.',
                                    style: AppTheme.bodyFont(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppTheme.darkWarn
                                          : AppTheme.lightWarn,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Groq Keys List & Input
                        _buildProviderKeyList(
                          providerName: 'Groq',
                          keys: settings.groqKeys,
                          controller: _groqController,
                          errorMessage: _groqError,
                          hintText: 'Paste Groq key (e.g. gsk_...)',
                          isDark: isDark,
                          ink: ink,
                          mute: mute,
                          line: line,
                          surface: surface,
                          acc: acc,
                          onAcc: onAcc,
                          onAdd: () => _onAddGroqKey(settings),
                          onRemove: (idx) => settings.removeGroqKey(idx),
                        ),

                        const SizedBox(height: 16),

                        // Tavily Keys List & Input
                        _buildProviderKeyList(
                          providerName: 'Tavily',
                          keys: settings.tavilyKeys,
                          controller: _tavilyController,
                          errorMessage: _tavilyError,
                          hintText: 'Paste Tavily key (e.g. tvly-...)',
                          isDark: isDark,
                          ink: ink,
                          mute: mute,
                          line: line,
                          surface: surface,
                          acc: acc,
                          onAcc: onAcc,
                          onAdd: () => _onAddTavilyKey(settings),
                          onRemove: (idx) => settings.removeTavilyKey(idx),
                        ),

                        if (hasCustomKeys) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: () =>
                                  _confirmClearAllKeys(settings, isDark),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isDark
                                      ? AppTheme.darkBad.withValues(alpha: 0.5)
                                      : AppTheme.lightBad.withValues(alpha: 0.5),
                                ),
                                foregroundColor:
                                    isDark ? AppTheme.darkBad : AppTheme.lightBad,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                              ),
                              child: const Text('Clear all keys'),
                            ),
                          ),
                        ],

                        // --- SECTION B: REPORT ---
                        _buildSectionHeader('Report', mute),

                        // Report Language Dropdown
                        _buildSettingRow(
                          label: 'Report language',
                          isDark: isDark,
                          mute: mute,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(color: line, width: 1.0),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: settings.reportLanguage,
                                dropdownColor: surface,
                                icon: Icon(Icons.arrow_drop_down, color: mute),
                                style: AppTheme.bodyFont(
                                  fontSize: 14,
                                  color: ink,
                                ),
                                items: kAllowedReportLanguages
                                    .map(
                                      (lang) => DropdownMenuItem(
                                        value: lang,
                                        child: Text(lang),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (newLang) {
                                  if (newLang != null) {
                                    settings.setReportLanguage(newLang);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quotes stay in their original language.',
                          style: AppTheme.bodyFont(
                            fontSize: 12,
                            color: mute,
                            fontStyle: FontStyle.italic,
                          ),
                        ),

                        // --- SECTION C: APPEARANCE ---
                        _buildSectionHeader('Appearance', mute),

                        // Theme Mode
                        _buildSettingRow(
                          label: 'Theme',
                          isDark: isDark,
                          mute: mute,
                          child: _buildSegmentedChoice<ThemeMode>(
                            options: const [
                              ThemeMode.system,
                              ThemeMode.light,
                              ThemeMode.dark,
                            ],
                            labels: const ['System', 'Light', 'Dark'],
                            selected: settings.themeMode,
                            isDark: isDark,
                            line: line,
                            acc: acc,
                            onAcc: onAcc,
                            onSelected: (val) {
                              settings.setThemeMode(val);
                              themeModeNotifier.value = val;
                              saveThemeMode(val);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Cursor Spotlight Switch
                        _buildSwitchRow(
                          title: 'Cursor spotlight',
                          subtitle:
                              'Glow effect following mouse cursor (disabled when reduce motion is on)',
                          value: settings.cursorSpotlight,
                          enabled: !settings.reduceMotion,
                          isDark: isDark,
                          ink: ink,
                          mute: mute,
                          onChanged: (val) =>
                              settings.setCursorSpotlight(val),
                        ),
                        const SizedBox(height: 12),

                        // Reduce Motion Switch
                        _buildSwitchRow(
                          title: 'Reduce motion',
                          subtitle:
                              'Zero-duration transitions/stagger and spotlight off',
                          value: settings.reduceMotion,
                          enabled: true,
                          isDark: isDark,
                          ink: ink,
                          mute: mute,
                          onChanged: (val) =>
                              settings.setReduceMotion(val),
                        ),

                        // --- SECTION D: DATA ---
                        _buildSectionHeader('Data', mute),

                        // Save History Switch
                        _buildSwitchRow(
                          title: 'Save history',
                          subtitle:
                              'Save research reports in local browser storage',
                          value: settings.saveHistory,
                          enabled: true,
                          isDark: isDark,
                          ink: ink,
                          mute: mute,
                          onChanged: (val) => settings.setSaveHistory(val),
                        ),
                        const SizedBox(height: 12),

                        // Clear History Button
                        OutlinedButton(
                          onPressed: () => _confirmClearHistory(isDark),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: line),
                            foregroundColor: ink,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          child: const Text('Clear history'),
                        ),

                        const SizedBox(height: 24),
                      ],
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

  Widget _buildSectionHeader(String title, Color mute) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: AppTheme.monoFont(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: mute,
        ),
      ),
    );
  }

  Widget _buildProviderKeyList({
    required String providerName,
    required List<String> keys,
    required TextEditingController controller,
    required String? errorMessage,
    required String hintText,
    required bool isDark,
    required Color ink,
    required Color mute,
    required Color line,
    required Color surface,
    required Color acc,
    required Color onAcc,
    required VoidCallback onAdd,
    required ValueChanged<int> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$providerName Keys',
              style: AppTheme.bodyFont(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            Text(
              '${keys.length}/10',
              style: AppTheme.monoFont(
                fontSize: 12,
                color: mute,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // List of masked keys
        if (keys.isNotEmpty) ...[
          for (int i = 0; i < keys.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: line, width: 1.0),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      SettingsService.maskKey(keys[i]),
                      style: AppTheme.monoFont(
                        fontSize: 13,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: mute),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: 'Remove key',
                    onPressed: () => onRemove(i),
                  ),
                ],
              ),
            ),
        ],

        // Input row
        if (keys.length < 10) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: controller,
                    obscureText: true,
                    style: AppTheme.monoFont(fontSize: 13, color: ink),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: AppTheme.monoFont(fontSize: 12, color: mute),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        borderSide: BorderSide(color: line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        borderSide: BorderSide(color: line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        borderSide: BorderSide(color: acc, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => onAdd(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: acc,
                  foregroundColor: onAcc,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                child: const Text('Add key'),
              ),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              errorMessage,
              style: AppTheme.bodyFont(
                fontSize: 12,
                color: isDark ? AppTheme.darkBad : AppTheme.lightBad,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSettingRow({
    required String label,
    required bool isDark,
    required Color mute,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: mute,
                ),
              ),
              const SizedBox(height: 6),
              child,
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTheme.bodyFont(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: mute,
              ),
            ),
            child,
          ],
        );
      },
    );
  }

  Widget _buildSegmentedChoice<T>({
    required List<T> options,
    required List<String> labels,
    required T selected,
    required bool isDark,
    required Color line,
    required Color acc,
    required Color onAcc,
    required ValueChanged<T> onSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: line, width: 1.0),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onSelected(options[i]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: options[i] == selected ? acc : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  labels[i],
                  style: AppTheme.bodyFont(
                    fontSize: 12,
                    fontWeight: options[i] == selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: options[i] == selected
                        ? onAcc
                        : (isDark ? AppTheme.darkInk : AppTheme.lightInk),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required bool isDark,
    required Color ink,
    required Color mute,
    required ValueChanged<bool> onChanged,
  }) {
    final acc = isDark ? AppTheme.darkAcc : AppTheme.lightAcc;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: enabled ? ink : mute,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTheme.bodyFont(
                  fontSize: 12,
                  color: mute,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: acc,
          activeThumbColor: isDark ? AppTheme.darkOnAcc : AppTheme.lightOnAcc,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
