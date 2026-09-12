class RunnerPreviewTabHandle {
  const RunnerPreviewTabHandle();

  bool get opened => false;

  void navigate(String url) {}

  void close() {}
}

RunnerPreviewTabHandle openRunnerPreviewTab() {
  return const RunnerPreviewTabHandle();
}
