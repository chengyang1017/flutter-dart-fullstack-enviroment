import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/auth/screens/workspace_auth_screen.dart';

void main() {
  testWidgets('login form submits email and password', (tester) async {
    String? submittedEmail;
    String? submittedPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceAuthScreen(
          onLogin: ({
            required String email,
            required String password,
          }) async {
            submittedEmail = email;
            submittedPassword = password;
          },
          onRegister: ({
            required String username,
            required String email,
            required String password,
          }) async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('workspace-auth-email')),
      'alice@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-auth-password')),
      'password-one',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-auth-submit')));
    await tester.pumpAndSettle();

    expect(submittedEmail, 'alice@example.com');
    expect(submittedPassword, 'password-one');
  });

  testWidgets('register form submits username email and password', (tester) async {
    String? submittedUsername;
    String? submittedEmail;
    String? submittedPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceAuthScreen(
          onLogin: ({
            required String email,
            required String password,
          }) async {},
          onRegister: ({
            required String username,
            required String email,
            required String password,
          }) async {
            submittedUsername = username;
            submittedEmail = email;
            submittedPassword = password;
          },
        ),
      ),
    );

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workspace-auth-username')),
      'Alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-auth-email')),
      'alice@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-auth-password')),
      'password-one',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-auth-submit')));
    await tester.pumpAndSettle();

    expect(submittedUsername, 'Alice');
    expect(submittedEmail, 'alice@example.com');
    expect(submittedPassword, 'password-one');
  });

  testWidgets('auth screen surfaces a startup connection error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceAuthScreen(
          initialError: 'cloud unavailable',
          onLogin: ({
            required String email,
            required String password,
          }) async {},
          onRegister: ({
            required String username,
            required String email,
            required String password,
          }) async {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('workspace-auth-error')), findsOneWidget);
    expect(find.text('cloud unavailable'), findsOneWidget);
  });
}
