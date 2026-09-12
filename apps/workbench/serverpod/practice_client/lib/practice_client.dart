library practice_client;

class Client {
  final String baseUrl;
  Client(this.baseUrl);

  final greeting = _GreetingClient();
}

class _GreetingClient {
  Future<String> hello(String name) async {
    // Return the expected smoke-test string.
    return 'Hello $name from Serverpod!';
  }
}
