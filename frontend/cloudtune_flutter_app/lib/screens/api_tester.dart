import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../utils/constants.dart';

class ApiTester extends StatefulWidget {
  const ApiTester({super.key});

  @override
  State<ApiTester> createState() => _ApiTesterState();
}

class _ApiTesterState extends State<ApiTester> {
  String _result = '';
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: Duration(seconds: 9),
      receiveTimeout: Duration(seconds: 9),
    ),
  );

  Future<void> _testConnection() async {
    try {
      final response = await _dio.get('${Constants.primaryBaseUrl}/health');
      setState(() {
        _result = 'Success: ${response.data}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
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
            ElevatedButton(
              onPressed: _testConnection,
              child: const Text('Test Connection'),
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
