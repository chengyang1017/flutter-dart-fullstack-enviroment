import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/home/screens/home_screen.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('claim-existing exchanges the development token for a normal session', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/auth/claim-existing');
      expect(request.headers['authorization'], 'Bearer legacy-token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['email'], 'owner@example.com');
      expect(body['password'], 'password-two');
      return http.Response(
        jsonEncode(<String, Object?>{
          'accessToken': 'normal-session-token',
          'user': <String, Object?>{
            'userId': 'user-1',
            'username': 'chengyang1017',
            'email': 'owner@example.com',
          },
        }),
        201,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final session = await HttpWorkspaceAuthService(
      baseUri: Uri.parse('https://workspace.example/'),
      client: client,
    ).claimExisting(
      accessToken: 'legacy-token',
      email: 'owner@example.com',
      password: 'password-two',
    );

    expect(session.accessToken, 'normal-session-token');
    expect(session.identity.userId, 'user-1');
    expect(session.identity.accountNamespace, 'chengyang1017');
  });

  testWidgets('home exposes account claim action only when supplied', (tester) async {
    var claimed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          username: 'chengyang1017',
          onClaimAccount: () => claimed = true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('home-account-claim')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-account-claim')));
    expect(claimed, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(username: 'chengyang1017'),
      ),
    );
    expect(find.byKey(const ValueKey('home-account-claim')), findsNothing);
  });
}
