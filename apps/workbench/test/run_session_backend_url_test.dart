import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/models/run_session.dart';

void main() {
  test('RunSession keeps and clears Dart Frog backend URL', () {
    final session = RunSession.fromJson({
      'id': 'fullstack-1',
      'projectType': 'flutter-dart-frog',
      'status': 'running',
      'createdAt': '2026-09-02T14:00:00.000Z',
      'lastActivityAt': '2026-09-02T14:01:00.000Z',
      'previewUrl': 'http://localhost:41000',
      'backendUrl': 'http://localhost:42000',
    });

    expect(session.backendUrl, 'http://localhost:42000');
    expect(session.toJson()['backendUrl'], 'http://localhost:42000');

    final stopping = session.copyWith(status: RunnerStatus.stopping);
    expect(stopping.backendUrl, 'http://localhost:42000');

    final cleared = session.copyWith(clearBackendUrl: true);
    expect(cleared.backendUrl, isNull);
  });
}
