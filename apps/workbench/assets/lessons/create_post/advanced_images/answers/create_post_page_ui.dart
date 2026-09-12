Scaffold(
  appBar: AppBar(
    title: const Text('发布帖子'),
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
            hintText: '分享你的想法',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: null,
          child: const Text('发布'),
        ),
      ],
    ),
  ),
)