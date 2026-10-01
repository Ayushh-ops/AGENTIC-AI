import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Consulted source item returned from the backend.
class SourceItem {
  final String title;
  final String url;
  final String content;

  const SourceItem({
    required this.title,
    required this.url,
    required this.content,
  });

  factory SourceItem.fromJson(Map<String, dynamic> json) {
    return SourceItem(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }
}

/// Evaluated factual claim with evidence and supporting source attribution.
class ClaimItem {
  final String statement;
  final String status;
  final String? sourceUrl;
  final List<String> sourceUrls;
  final String evidence;

  const ClaimItem({
    required this.statement,
    required this.status,
    this.sourceUrl,
    this.sourceUrls = const [],
    required this.evidence,
  });

  factory ClaimItem.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['source_urls'];
    final List<String> urls = [];
    if (rawUrls is List) {
      for (final u in rawUrls) {
        if (u != null) urls.add(u.toString());
      }
    }
    return ClaimItem(
      statement: json['statement'] as String? ?? '',
      status: json['status'] as String? ?? 'unsupported',
      sourceUrl: json['source_url'] as String?,
      sourceUrls: urls,
      evidence: json['evidence'] as String? ?? '',
    );
  }
}

/// Consolidated research response model.
class ResearchResponse {
  final String topic;
  final String reportMarkdown;
  final List<SourceItem> sources;
  final List<ClaimItem> claims;

  const ResearchResponse({
    required this.topic,
    required this.reportMarkdown,
    required this.sources,
    required this.claims,
  });

  factory ResearchResponse.fromJson(Map<String, dynamic> json) {
    return ResearchResponse(
      topic: json['topic'] as String? ?? '',
      reportMarkdown: json['report_markdown'] as String? ?? '',
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((s) => SourceItem.fromJson(s as Map<String, dynamic>))
          .toList(),
      claims: (json['claims'] as List<dynamic>? ?? [])
          .map((c) => ClaimItem.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Response model returned by the POST /ask router endpoint.
class AskResponse {
  final String mode;
  final String? reply;
  final ResearchResponse? research;
  final int? llmCalls;
  final int? searchCalls;

  const AskResponse({
    required this.mode,
    this.reply,
    this.research,
    this.llmCalls,
    this.searchCalls,
  });

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    return AskResponse(
      mode: json['mode'] as String? ?? 'chat',
      reply: json['reply'] as String?,
      research: json['research'] != null
          ? ResearchResponse.fromJson(json['research'] as Map<String, dynamic>)
          : null,
      llmCalls: json['llm_calls'] as int?,
      searchCalls: json['search_calls'] as int?,
    );
  }
}

/// Exception representing an error encountered during backend communication.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Service handling communication with the FastAPI backend.
class ApiService {
  final String baseUrl;
  final http.Client _client;

  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl != null && baseUrl.trim().isNotEmpty)
            ? baseUrl.trim()
            : ApiConfig.defaultBaseUrl,
        _client = client ?? http.Client();

  /// Queries the GET /health endpoint to verify service connectivity.
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final response = await _client.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'status': data['status'] ?? 'ok',
          'service': data['service'] ?? 'unknown',
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP status ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Queries the POST /research endpoint with a 120-second timeout.
  Future<ResearchResponse> research(String topic) async {
    final uri = Uri.parse('$baseUrl/research');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'topic': topic.trim()});

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ResearchResponse.fromJson(data);
      } else if (response.statusCode == 503) {
        throw const ApiException('API keys not configured', statusCode: 503);
      } else if (response.statusCode == 502) {
        String detail = 'Research workflow error occurred.';
        try {
          final errorData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          if (errorData.containsKey('detail') && errorData['detail'] != null) {
            detail = errorData['detail'].toString();
          }
        } catch (_) {}
        throw ApiException(detail, statusCode: 502);
      } else {
        String detail = 'Server error (${response.statusCode})';
        try {
          final errorData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          if (errorData.containsKey('detail') && errorData['detail'] != null) {
            detail = errorData['detail'].toString();
          }
        } catch (_) {}
        throw ApiException(detail, statusCode: response.statusCode);
      }
    } on TimeoutException {
      throw const ApiException('Request timed out after 120 seconds. Please try again.');
    } on http.ClientException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw const ApiException('Network connection failed. Could not reach backend server.');
    }
  }

  /// Queries the POST /ask router endpoint with a 120-second timeout.
  Future<AskResponse> ask(String message) async {
    final uri = Uri.parse('$baseUrl/ask');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'message': message.trim()});

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return AskResponse.fromJson(data);
      } else if (response.statusCode == 503) {
        throw const ApiException('API keys not configured', statusCode: 503);
      } else if (response.statusCode == 502) {
        String detail = 'Research workflow error occurred.';
        try {
          final errorData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          if (errorData.containsKey('detail') && errorData['detail'] != null) {
            detail = errorData['detail'].toString();
          }
        } catch (_) {}
        throw ApiException(detail, statusCode: 502);
      } else {
        String detail = 'Server error (${response.statusCode})';
        try {
          final errorData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          if (errorData.containsKey('detail') && errorData['detail'] != null) {
            detail = errorData['detail'].toString();
          }
        } catch (_) {}
        throw ApiException(detail, statusCode: response.statusCode);
      }
    } on TimeoutException {
      throw const ApiException('Request timed out after 120 seconds. Please try again.');
    } on http.ClientException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw const ApiException('Network connection failed. Could not reach backend server.');
    }
  }
}
