Scaffold(
  appBar: AppBar(
    title: const Text('Create Post'),
  ),
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextField(
          minLines: 6,
          maxLines: 10,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: 'Share what is on your mind...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: null,
          child: const Text('Publish'),
        ),
      ],
    ),
  ),
)