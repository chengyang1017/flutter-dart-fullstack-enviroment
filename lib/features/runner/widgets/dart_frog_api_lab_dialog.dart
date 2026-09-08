import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DartFrogApiLabDialog extends StatefulWidget {
  const DartFrogApiLabDialog({
    super.key,
    required this.baseUrl,
    this.httpClient,
  });

  final String baseUrl;
  final http.Client? httpClient;

  @override
  State<DartFrogApiLabDialog> createState() => _DartFrogApiLabDialogState();
}

class _DartFrogApiLabDialogState extends State<DartFrogApiLabDialog> {
  late final http.Client _client;
  late final bool _ownsClient;
  late final TextEditingController _pathController;
  late final TextEditingController _bodyController;

  String _method = 'GET';
  bool _sending = false;
  int? _statusCode;
  int? _elapsedMilliseconds;
  String _responseBody = 'Run the Dart Frog session, then send a request.';

  @override
  void initState() {
    super.initState();
    _client = widget.httpClient ?? http.Client();
    _ownsClient = widget.httpClient == null;
    _pathController = TextEditingController(text: '/');
    _bodyController = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(
        {'message': 'Hello from the API Lab'},
      ),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    _bodyController.dispose();
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;

    setState(() {
      _sending = true;
      _statusCode = null;
      _elapsedMilliseconds = null;
      _responseBody = 'Sending...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final uri = _requestUri();
      final response = switch (_method) {
        'POST' => await _client.post(
            uri,
            headers: const {
              'accept': 'application/json',
              'content-type': 'application/json',
            },
            body: _bodyController.text,
          ),
        _ => await _client.get(
            uri,
            headers: const {'accept': 'application/json'},
          ),
      };

      stopwatch.stop();
      if (!mounted) return;

      setState(() {
        _sending = false;
        _statusCode = response.statusCode;
        _elapsedMilliseconds = stopwatch.elapsedMilliseconds;
        _responseBody = _prettyBody(response.body);
      });
    } catch (error) {
      stopwatch.stop();
      if (!mounted) return;

      setState(() {
        _sending = false;
        _elapsedMilliseconds = stopwatch.elapsedMilliseconds;
        _responseBody = 'Request failed: $error';
      });
    }
  }

  Uri _requestUri() {
    final cleanBase = widget.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final rawPath = _pathController.text.trim();
    final path = rawPath.isEmpty
        ? '/'
        : rawPath.startsWith('/')
            ? rawPath
            : '/$rawPath';
    return Uri.parse('$cleanBase$path');
  }

  String _prettyBody(String source) {
    if (source.trim().isEmpty) return '<empty response body>';

    try {
      final decoded = jsonDecode(source);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.api),
          SizedBox(width: 10),
          Text('Dart Frog API Lab'),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              widget.baseUrl,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Method',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'GET', child: Text('GET')),
                      DropdownMenuItem(value: 'POST', child: Text('POST')),
                    ],
                    onChanged: _sending
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _method = value);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    enabled: !_sending,
                    decoration: const InputDecoration(
                      labelText: 'Path',
                      hintText: '/api/status or /api/echo',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('dart-frog-api-send-button'),
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_method == 'POST') ...[
              TextField(
                controller: _bodyController,
                enabled: !_sending,
                minLines: 5,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'JSON Body',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                if (_statusCode != null) Chip(label: Text('HTTP $_statusCode')),
                if (_elapsedMilliseconds != null) ...[
                  const SizedBox(width: 8),
                  Chip(label: Text('${_elapsedMilliseconds} ms')),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _responseBody,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
