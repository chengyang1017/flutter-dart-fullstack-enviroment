//这里是service
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import '../models/user.dart';

class PostService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  PostService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _posts {
    return _firestore.collection('posts');
  }

  Future<void> createPost({
    required String content,
    bool isPrivate = false,
    List<File> imageFiles = const [],
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('用户尚未登录');
    }

    final trimmedContent = content.trim();

    if (trimmedContent.isEmpty && imageFiles.isEmpty) {
      throw ArgumentError('帖子内容和照片不能同时为空');
    }

    if (trimmedContent.length > 1000) {
      throw ArgumentError('帖子内容不能超过1000个字符');
    }

    if (imageFiles.length > 9) {
      throw ArgumentError('每篇帖子最多上传 9 张照片');
    }

    final authorName = await _getCurrentAuthorName();
    final postReference = _posts.doc();

    final imageUrls = <String>[];
    final imagePaths = <String>[];

    try {
      for (var index = 0; index < imageFiles.length; index++) {
        final imagePath =
            'post_images/${user.uid}/${postReference.id}/image_$index';

        final storageReference =
            _storage.ref().child(imagePath);

        await storageReference.putFile(
          imageFiles[index],
          SettableMetadata(
            contentType: 'image/jpeg',
          ),
        );

        final downloadUrl =
            await storageReference.getDownloadURL();

        imageUrls.add(downloadUrl);
        imagePaths.add(imagePath);
      }

      await postReference.set({
        'authorId': user.uid,
        'authorName': authorName,
        'content': trimmedContent,
        'createdAt': FieldValue.serverTimestamp(),
        'likeCount': 0,
        'isPrivate': isPrivate,
        'imageUrls': imageUrls,
        'imagePaths': imagePaths,
      });
    } catch (e) {
      // Firestore 写入失败或部分图片上传失败时，清理已经上传的图片。
      for (final imagePath in imagePaths) {
        try {
          await _storage.ref().child(imagePath).delete();
        } catch (_) {
          // 清理失败不覆盖原始错误。
        }
      }

      rethrow;
    }
  }

  Future<String> _getCurrentAuthorName() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('用户尚未登录');
    }

    final userDocument = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDocument.exists) {
      final appUser =
          AppUser.fromDocument(userDocument);
      final username = appUser.username.trim();

      if (username.isNotEmpty) {
        return username;
      }
    }

    final displayName = user.displayName?.trim();

    if (displayName != null &&
        displayName.isNotEmpty) {
      return displayName;
    }

    return user.email ?? '未知用户';
  }
}
