import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/widgets/dart_frog_api_lab_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('API Lab sends a GET request and pretty prints JSON', (tester) async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        '{"status":"ok","framework":"dart_frog"}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartFrogApiLabDialog(
            baseUrl: 'http://backend.test',
            httpClient: client,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('dart-frog-api-send-button')),
    );
    await tester.pumpAndSettle();

    expect(requestedUri, Uri.parse('http://backend.test/'));
    expect(find.text('HTTP 200'), findsOneWidget);
    expect(find.textContaining('"status": "ok"'), findsOneWidget);
    expect(find.textContaining('"framework": "dart_frog"'), findsOneWidget);
  });
}
