import 'run_session.dart';

enum RunnerEventType {
  status,
  log,
  session,
}

class RunnerEvent {
  const RunnerEvent.status(this.status)
      : type = RunnerEventType.status,
        message = null,
        session = null;

  const RunnerEvent.log(this.message)
      : type = RunnerEventType.log,
        status = null,
        session = null;

  const RunnerEvent.session(this.session)
      : type = RunnerEventType.session,
        status = null,
        message = null;

  final RunnerEventType type;
  final RunnerStatus? status;
  final String? message;
  final RunSession? session;
}
