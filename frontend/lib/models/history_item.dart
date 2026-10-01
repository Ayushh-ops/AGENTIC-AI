import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';

/// Representation of a single saved search or chat interaction.
class HistoryItem {
  final String id;
  final String message;
  final String mode; // 'chat' or 'research'
  final String? reply;
  final ResearchResponse? research;
  final String? researchType; // 'general', 'news', 'academic'
  final String? depth; // 'quick', 'standard', 'deep'
  final int timestamp;

  const HistoryItem({
    required this.id,
    required this.message,
    required this.mode,
    this.reply,
    this.research,
    this.researchType,
    this.depth,
    required this.timestamp,
  });

  /// Formatted tag for sidebar list display, e.g. "News - Deep".
  String? get formattedTypeAndDepth {
    if (mode != 'research') return null;
    final t = (researchType != null && researchType!.trim().isNotEmpty)
        ? researchType!.trim().toLowerCase()
        : 'general';
    final d = (depth != null && depth!.trim().isNotEmpty)
        ? depth!.trim().toLowerCase()
        : 'standard';
    final tCap = t[0].toUpperCase() + t.substring(1);
    final dCap = d[0].toUpperCase() + d.substring(1);
    return '$tCap - $dCap';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'mode': mode,
      'reply': reply,
      'research_type': researchType,
      'depth': depth,
      'research': research != null
          ? {
              'topic': research!.topic,
              'report_markdown': research!.reportMarkdown,
              'sources': research!.sources
                  .map((s) => {
                        'title': s.title,
                        'url': s.url,
                        'content': s.content,
                      })
                  .toList(),
              'claims': research!.claims
                  .map((c) => {
                        'statement': c.statement,
                        'status': c.status,
                        'evidence': c.evidence,
                        'source_urls': c.sourceUrls,
                        'source_url': c.sourceUrl,
                      })
                  .toList(),
            }
          : null,
      'timestamp': timestamp,
    };
  }

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      message: json['message'] as String? ?? '',
      mode: json['mode'] as String? ?? 'research',
      reply: json['reply'] as String?,
      researchType: json['research_type'] as String?,
      depth: json['depth'] as String?,
      research: json['research'] != null
          ? ResearchResponse.fromJson(json['research'] as Map<String, dynamic>)
          : null,
      timestamp: json['timestamp'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Local storage service using shared_preferences.
class HistoryStorage {
  static const String _storageKey = 'research_history_items_v2';
  static const int maxHistoryItems = 30;

  /// Loads persisted history items, returning an empty list on missing or corrupted data.
  static Future<List<HistoryItem>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final List<HistoryItem> items = [];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          try {
            items.add(HistoryItem.fromJson(entry));
          } catch (_) {
            // Skip corrupted individual item
          }
        }
      }
      return items;
    } catch (_) {
      // Safe fallback on any error
      return [];
    }
  }

  /// Persists the list of history items, capped to maxHistoryItems.
  static Future<void> saveHistory(List<HistoryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final capped = items.take(maxHistoryItems).toList();
      final payload = jsonEncode(capped.map((i) => i.toJson()).toList());
      await prefs.setString(_storageKey, payload);
    } catch (_) {}
  }
}
