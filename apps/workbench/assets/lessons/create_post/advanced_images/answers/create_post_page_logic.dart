class _CreatePostPageState {
  bool _isSubmitting = false;

  Future<void> _publishPost() async {
    if (_isSubmitting) return;

    final content = _contentController.text.trim();

    if (content.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入内容或选择照片'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _postService.createPost(
        content: content,
        imageFiles: _selectedImages
            .map((image) => File(image.path))
            .toList(),
      );

      if (!mounted) return;

      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}