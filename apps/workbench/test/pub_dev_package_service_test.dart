import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/packages/services/pub_dev_package_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('search keeps exact valid package name even when completion data omits it', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/package-name-completion-data');
      return http.Response(
        jsonEncode(<String, Object>{
          'packages': <String>['provider', 'flutter_riverpod', 'riverpod'],
        }),
        200,
      );
    });
    final service = PubDevPackageService(client: client);
    addTearDown(service.close);

    final results = await service.search('my_package');

    expect(results.first, 'my_package');
  });

  test('packageInfo exposes latest version, history and description', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/packages/provider');
      return http.Response(
        jsonEncode(<String, Object>{
          'latest': <String, Object>{
            'version': '6.1.5',
            'pubspec': <String, Object>{
              'description': 'State management for Flutter.',
            },
          },
          'versions': <Object>[
            <String, Object>{'version': '6.0.0'},
            <String, Object>{'version': '6.1.2'},
            <String, Object>{'version': '6.1.5'},
          ],
        }),
        200,
      );
    });
    final service = PubDevPackageService(client: client);
    addTearDown(service.close);

    final info = await service.packageInfo('provider');

    expect(info.name, 'provider');
    expect(info.latestVersion, '6.1.5');
    expect(info.versions, <String>['6.1.5', '6.1.2', '6.0.0']);
    expect(info.description, 'State management for Flutter.');
  });

  test('packageInfo reports non-success pub.dev responses', () async {
    final service = PubDevPackageService(
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    addTearDown(service.close);

    expect(
      () => service.packageInfo('missing_package'),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('HTTP 404'),
        ),
      ),
    );
  });
}
