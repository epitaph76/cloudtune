import 'package:flutter/material.dart';

import '../services/backend_client.dart';
import '../utils/constants.dart';

class ApiTester extends StatefulWidget {
  const ApiTester({super.key});

  @override
  State<ApiTester> createState() => _ApiTesterState();
}

class _ApiTesterState extends State<ApiTester> {
  String _result = '';
  String _lastResolvedHost = '-';
  bool _isLoading = false;
  final BackendClient _backendClient = BackendClient(
    connectTimeout: const Duration(seconds: 9),
    receiveTimeout: const Duration(seconds: 9),
  );

  String _toHostLabel(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) {
      return rawUrl;
    }
    final portLabel = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portLabel';
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _backendClient.request<dynamic>(
        method: 'GET',
        path: '/health',
      );
      final realUri = response.realUri;
      final portLabel = realUri.hasPort ? ':${realUri.port}' : '';
      setState(() {
        _lastResolvedHost = '${realUri.scheme}://${realUri.host}$portLabel';
        _result = 'Success (${response.statusCode}): ${response.data}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Tester')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Primary base URL: ${Constants.primaryBaseUrl}'),
            Text(
              'Fallback hosts enabled: ${Constants.enableFallbackBaseUrls ? "yes" : "no"}',
            ),
            Text(
              'Configured hosts: ${Constants.activeBaseUrls.map(_toHostLabel).join(", ")}',
            ),
            Text('Last resolved host: $_lastResolvedHost'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testConnection,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test Connection'),
            ),
            const SizedBox(height: 20),
            Text('Result:', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            SelectableText(_result.isEmpty ? 'Click test button...' : _result),
          ],
        ),
      ),
    );
  }
}
