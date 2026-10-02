import 'dart:convert';
import '../api/api_service.dart';

/// Converts a topic string into a clean lowercase hyphenated slug.
String buildTopicSlug(String topic) {
  final slug = topic
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'research-report' : slug;
}

/// Generates a YYYY-MM-DD date string.
String buildExportDateString([DateTime? date]) {
  final d = date ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Builds full markdown export text from research results.
String buildReportMarkdown({
  required ResearchResponse research,
  required String type,
  required String depth,
}) {
  final buffer = StringBuffer();

  // 1. Title
  buffer.writeln('# ${research.topic}');
  buffer.writeln();

  // 2. Type & Depth
  final t = type.trim().isNotEmpty
      ? (type.trim()[0].toUpperCase() + type.trim().substring(1))
      : 'General';
  final d = depth.trim().isNotEmpty
      ? (depth.trim()[0].toUpperCase() + depth.trim().substring(1))
      : 'Standard';
  buffer.writeln('**Type:** $t | **Depth:** $d');
  buffer.writeln();

  // 3. Tally
  final supported = research.claims
      .where((c) => c.status.toLowerCase() == 'supported')
      .length;
  final singleSource = research.claims
      .where((c) => c.status.toLowerCase() == 'single_source')
      .length;
  final unsupported = research.claims
      .where((c) => c.status.toLowerCase() == 'unsupported')
      .length;
  buffer.writeln(
      '**Tally:** $supported Corroborated, $singleSource Single source, $unsupported Unsupported (${research.claims.length} claims total)');
  buffer.writeln();

  // 4. Summary & Key Findings from synthesized report
  buffer.writeln('## SUMMARY');
  buffer.writeln();
  if (research.reportMarkdown.trim().isNotEmpty) {
    buffer.writeln(research.reportMarkdown.trim());
  } else {
    buffer.writeln('No summary available.');
  }
  buffer.writeln();

  // 5. Claims with status, quote/evidence, and source URLs
  buffer.writeln('## CLAIMS & EVIDENCE');
  buffer.writeln();
  if (research.claims.isEmpty) {
    buffer.writeln('No claims evaluated.');
  } else {
    for (int i = 0; i < research.claims.length; i++) {
      final claim = research.claims[i];
      buffer.writeln('### Claim ${i + 1}: ${claim.statement}');
      buffer.writeln('- **Status:** ${claim.status}');
      if (claim.evidence.trim().isNotEmpty) {
        buffer.writeln('- **Evidence / Quote:** "${claim.evidence.trim()}"');
      }
      final urls = claim.sourceUrls.isNotEmpty
          ? claim.sourceUrls
          : (claim.sourceUrl != null && claim.sourceUrl!.trim().isNotEmpty
              ? [claim.sourceUrl!.trim()]
              : <String>[]);
      if (urls.isNotEmpty) {
        buffer.writeln('- **Source URLs:**');
        for (final u in urls) {
          buffer.writeln('  - $u');
        }
      }
      buffer.writeln();
    }
  }

  // 6. Consulted sources
  buffer.writeln('## CONSULTED SOURCES');
  buffer.writeln();
  if (research.sources.isEmpty) {
    buffer.writeln('No sources recorded.');
  } else {
    for (int i = 0; i < research.sources.length; i++) {
      final s = research.sources[i];
      final title = s.title.trim().isNotEmpty ? s.title.trim() : s.url;
      buffer.writeln('${i + 1}. [$title](${s.url})');
    }
  }
  buffer.writeln();

  // 7. Mandatory final disclaimer line
  buffer.writeln('AI-generated, unverified. Read the evidence under each claim.');

  return buffer.toString();
}

/// Builds JSON export map for the report.
Map<String, dynamic> buildReportJson({
  required ResearchResponse research,
  required String type,
  required String depth,
  DateTime? exportedAt,
}) {
  return {
    'app': 'Multi Agent Research Assistant',
    'version': 1,
    'type': type,
    'depth': depth,
    'topic': research.topic,
    'result': research.toJson(),
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
  };
}

/// Parsed structure after validating and importing a JSON report.
class ParsedImportedReport {
  final String app;
  final int version;
  final String type;
  final String depth;
  final String topic;
  final ResearchResponse result;
  final String exportedAt;

  const ParsedImportedReport({
    required this.app,
    required this.version,
    required this.type,
    required this.depth,
    required this.topic,
    required this.result,
    required this.exportedAt,
  });
}

/// Validates and parses the JSON report format strictly.
ParsedImportedReport parseReportJson(String rawJson) {
  final dynamic decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid report file: root must be a JSON object.');
  }

  final app = decoded['app'];
  if (app is! String || app.trim().isEmpty) {
    throw const FormatException('Invalid report file: missing or invalid "app" field.');
  }

  final version = decoded['version'];
  if (version is! int) {
    throw const FormatException('Invalid report file: missing or invalid "version" field.');
  }

  final resultObj = decoded['result'];
  if (resultObj is! Map<String, dynamic>) {
    throw const FormatException('Invalid report file: missing or invalid "result" object.');
  }

  final topic = decoded['topic']?.toString() ?? resultObj['topic']?.toString() ?? '';
  if (topic.trim().isEmpty) {
    throw const FormatException('Invalid report file: "topic" cannot be empty.');
  }

  final research = ResearchResponse.fromJson(resultObj);

  return ParsedImportedReport(
    app: app,
    version: version,
    type: decoded['type']?.toString() ?? 'general',
    depth: decoded['depth']?.toString() ?? 'standard',
    topic: topic,
    result: research,
    exportedAt: decoded['exportedAt']?.toString() ?? DateTime.now().toIso8601String(),
  );
}
