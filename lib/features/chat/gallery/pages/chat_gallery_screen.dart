import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:langgry/core/firebase/firestore_database.dart';
import 'package:uuid/uuid.dart';

class ChatGallerySelection {
  const ChatGallerySelection({required this.url, required this.name});

  final String url;
  final String name;
}

class ChatGalleryScreen extends StatefulWidget {
  const ChatGalleryScreen({
    this.roomId,
    this.roomTitle,
    this.selectionMode = false,
    super.key,
  });

  final String? roomId;
  final String? roomTitle;
  final bool selectionMode;

  @override
  State<ChatGalleryScreen> createState() => _ChatGalleryScreenState();
}

enum _GalleryView { all, rooms, albums }

class _ChatGalleryScreenState extends State<ChatGalleryScreen> {
  static const _pageSize = 30;
  late Future<_GalleryData> _gallery = _loadGallery();
  _GalleryView _view = _GalleryView.all;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedImageIds = {};
  final Map<String, String> _draftNames = {};
  bool _uploading = false;
  bool _selectionMode = false;
  bool _trashMode = false;
  bool _loadingMore = false;
  int _visibleImageCount = _pageSize;
  double _imageAspectRatio = 3 / 4;
  List<_GalleryImage> _loadedImages = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNextPageOnScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadNextPageOnScroll)
      ..dispose();
    super.dispose();
  }

  void _loadNextPageOnScroll() {
    if (!_scrollController.hasClients ||
        _loadingMore ||
        _visibleImageCount >= _loadedImages.length ||
        _scrollController.position.extentAfter > 360) {
      return;
    }
    _loadingMore = true;
    setState(() {
      _visibleImageCount =
          (_visibleImageCount + _pageSize).clamp(0, _loadedImages.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadingMore = false;
      if (mounted) _loadNextPageOnScroll();
    });
  }

  FirebaseStorage get _storage => FirebaseStorage.instanceFor(
        app: Firebase.app(),
        bucket: 'gs://languagehungry.firebasestorage.app',
      );

  Future<_GalleryData> _loadGallery() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인 후 갤러리를 볼 수 있습니다.');
    final userDocument = langgryFirestore().collection('users').doc(user.uid);
    final albumsSnapshot =
        await userDocument.collection('chatGalleryAlbums').get();
    final albums = {
      for (final document in albumsSnapshot.docs)
        document.id: document.data()['name'] as String? ?? '앨범',
    };
    final galleryByUrl = <String, _GalleryImage>{};
    final images = galleryByUrl;
    final galleryCollection = userDocument.collection('chatGalleryImages');
    final galleryDocuments = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (widget.roomId == null || !widget.selectionMode) {
      galleryDocuments.addAll((await galleryCollection.get()).docs);
    } else {
      for (final albumId in albums.keys) {
        final albumImages =
            await galleryCollection.where('albumId', isEqualTo: albumId).get();
        galleryDocuments.addAll(albumImages.docs);
      }
    }
    final trashedUrls = <String>{};
    for (final document in galleryDocuments) {
      final data = document.data();
      final url = data['url'];
      if (url is! String || url.isEmpty) continue;
      final image = _GalleryImage(
        id: document.id,
        url: url,
        name: data['name'] as String? ?? '사진',
        roomId: data['roomId'] as String?,
        roomTitle: data['roomTitle'] as String? ?? '갤러리',
        prompt: data['prompt'] as String? ?? '',
        kind: data['kind'] as String? ?? 'uploaded',
        albumId: data['albumId'] as String?,
        createdAt: _dateOf(data['createdAt']),
        isTrashed: data['isTrashed'] as bool? ?? false,
        deletedAt: _dateOf(data['deletedAt']),
      );
      galleryByUrl[url] = image;
      if (image.isTrashed) trashedUrls.add(url);
    }
    if (_trashMode) {
      final now = DateTime.now();
      final expired = galleryByUrl.values
          .where(
            (image) =>
                image.isTrashed && now.difference(image.deletedAt).inDays >= 7,
          )
          .toList();
      for (final image in expired) {
        await _permanentlyDeleteImage(userDocument, image);
        galleryByUrl.remove(image.url);
      }
    }

    final rooms = userDocument.collection('chatRooms');
    final roomDocuments = widget.roomId == null
        ? (await rooms.get()).docs
        : [(await rooms.doc(widget.roomId).get())];
    for (final room in roomDocuments) {
      if (!room.exists) continue;
      final roomName =
          widget.roomTitle ?? (room.data()?['title'] as String? ?? '채팅방');
      final roomGallery =
          await room.reference.collection('galleryImages').get();
      for (final document in roomGallery.docs) {
        final data = document.data();
        final url = data['url'];
        if (url is! String || url.isEmpty) continue;
        if (trashedUrls.contains(url)) continue;
        final image = _GalleryImage(
          id: document.id,
          url: url,
          name: data['name'] as String? ?? '사진',
          roomId: room.id,
          roomTitle: roomName,
          prompt: data['prompt'] as String? ?? '',
          kind: data['kind'] as String? ?? 'uploaded',
          albumId: data['albumId'] as String?,
          createdAt: _dateOf(data['createdAt']),
          isTrashed: false,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
        images.putIfAbsent(url, () => image);
      }
      final messages = await room.reference.collection('messages').get();
      for (final message in messages.docs) {
        final data = message.data();
        final url = data['imageUrl'];
        if (data['type'] != 'image' || url is! String || url.isEmpty) continue;
        if (trashedUrls.contains(url)) continue;
        final existing = images[url];
        images[url] = _GalleryImage(
          id: existing?.id ?? '${room.id}--${message.id}',
          url: url,
          name: existing?.name ?? '채팅 사진',
          roomId: room.id,
          roomTitle: roomName,
          prompt: data['prompt'] as String? ?? existing?.prompt ?? '',
          kind: data['imageKind'] as String? ?? existing?.kind ?? 'uploaded',
          albumId: existing?.albumId,
          createdAt: _dateOf(data['createdAt'], fallback: existing?.createdAt),
          isTrashed: false,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }
    }
    final visibleImages = images.values.where((image) {
      if (_trashMode) return image.isTrashed;
      if (image.isTrashed) return false;
      if (widget.roomId == null) return true;
      return image.roomId == widget.roomId ||
          (image.albumId != null && albums.containsKey(image.albumId));
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _loadedImages = visibleImages;
    return _GalleryData(images: visibleImages, albums: albums);
  }

  DateTime _dateOf(dynamic value, {DateTime? fallback}) => value is Timestamp
      ? value.toDate()
      : fallback ?? DateTime.fromMillisecondsSinceEpoch(0);

  void _reload() {
    setState(() {
      _visibleImageCount = _pageSize;
      _gallery = _loadGallery();
    });
  }

  void _toggleSelection(_GalleryImage image) {
    setState(() {
      _selectionMode = true;
      if (!_selectedImageIds.add(image.id)) {
        _selectedImageIds.remove(image.id);
      }
      if (_selectedImageIds.isEmpty && _draftNames.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _startSelection(_GalleryImage image) {
    setState(() {
      _selectionMode = true;
      _selectedImageIds.add(image.id);
    });
  }

  void _toggleSelectAll(List<_GalleryImage> images) {
    final imageIds = images.map((image) => image.id).toSet();
    final allSelected =
        imageIds.isNotEmpty && imageIds.every(_selectedImageIds.contains);
    setState(() {
      if (allSelected) {
        _selectedImageIds.removeAll(imageIds);
      } else {
        _selectedImageIds.addAll(imageIds);
      }
    });
  }

  Future<void> _editTitle(_GalleryImage image) async {
    final controller = TextEditingController(
      text: _draftNames[image.id] ?? image.name,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('사진 제목 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: '제목',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _selectionMode = true;
      _selectedImageIds.add(image.id);
      _draftNames[image.id] = name;
    });
  }

  Future<void> _saveTitleChanges({bool exitAfterSave = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 사진 제목을 저장할 수 있습니다.');
      return;
    }
    final userDocument = langgryFirestore().collection('users').doc(user.uid);
    final images = _currentImages;
    try {
      for (final entry in _draftNames.entries) {
        _GalleryImage? image;
        for (final candidate in images) {
          if (candidate.id == entry.key) {
            image = candidate;
            break;
          }
        }
        if (image == null) continue;
        await _catalogReference(userDocument, image).set({
          'url': image.url,
          'name': entry.value,
          'kind': image.kind,
          'prompt': image.prompt,
          'createdAt': Timestamp.fromDate(image.createdAt),
          if (image.roomId != null) 'roomId': image.roomId,
          'roomTitle': image.roomTitle,
          if (image.albumId != null) 'albumId': image.albumId,
          'isTrashed': false,
        }, SetOptions(merge: true));
        if (image.roomId != null) {
          final roomImage = userDocument
              .collection('chatRooms')
              .doc(image.roomId)
              .collection('galleryImages')
              .doc(image.id);
          await roomImage.set({'name': entry.value}, SetOptions(merge: true));
        }
      }
      if (!mounted) return;
      setState(() {
        _draftNames.clear();
        if (exitAfterSave) {
          _selectionMode = false;
          _selectedImageIds.clear();
        }
        _gallery = _loadGallery();
      });
      _notify('사진 제목을 저장했습니다.');
    } catch (error) {
      _notify('사진 제목을 저장하지 못했습니다: $error');
    }
  }

  void _leaveSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedImageIds.clear();
      _draftNames.clear();
    });
  }

  Future<void> _confirmLeaveSelection() async {
    if (_draftNames.isEmpty) {
      _leaveSelectionMode();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('제목 변경 저장'),
        content: const Text('저장하지 않은 제목 변경이 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('저장 안 하고 나가기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'stay'),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('저장하고 나가기'),
          ),
        ],
      ),
    );
    if (choice == 'discard') _leaveSelectionMode();
    if (choice == 'save') await _saveTitleChanges(exitAfterSave: true);
  }

  List<_GalleryImage> get _currentImages => _loadedImages;

  DocumentReference<Map<String, dynamic>> _catalogReference(
    DocumentReference<Map<String, dynamic>> userDocument,
    _GalleryImage image,
  ) =>
      userDocument.collection('chatGalleryImages').doc(image.id);

  Future<void> _moveSelectedToTrash() async {
    final selectedIds = Set<String>.from(_selectedImageIds);
    if (selectedIds.isEmpty) return;
    if (_draftNames.isNotEmpty) {
      await _confirmLeaveSelection();
      if (_selectionMode) return;
      await _gallery;
    }
    final selected = _currentImages
        .where((image) => selectedIds.contains(image.id))
        .toList();
    if (selected.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 사진을 휴지통으로 이동할 수 있습니다.');
      return;
    }
    final userDocument = langgryFirestore().collection('users').doc(user.uid);
    final deletedAt = Timestamp.now();
    try {
      for (final image in selected) {
        await _catalogReference(userDocument, image).set({
          'url': image.url,
          'name': image.name,
          'kind': image.kind,
          'prompt': image.prompt,
          'createdAt': Timestamp.fromDate(image.createdAt),
          if (image.roomId != null) 'roomId': image.roomId,
          'roomTitle': image.roomTitle,
          if (image.albumId != null) 'albumId': image.albumId,
          'isTrashed': true,
          'deletedAt': deletedAt,
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      setState(() {
        _selectedImageIds.clear();
        _draftNames.clear();
        _selectionMode = false;
        _gallery = _loadGallery();
      });
      _notify('${selected.length}장의 사진을 휴지통으로 이동했습니다.');
    } catch (error) {
      _notify('사진을 휴지통으로 이동하지 못했습니다: $error');
    }
  }

  Future<void> _restoreImage(_GalleryImage image) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 사진을 복원할 수 있습니다.');
      return;
    }
    try {
      var roomWasDeleted = false;
      if (image.roomId != null) {
        final room = await langgryFirestore()
            .collection('users')
            .doc(user.uid)
            .collection('chatRooms')
            .doc(image.roomId)
            .get();
        roomWasDeleted = !room.exists;
      }
      await _catalogReference(
        langgryFirestore().collection('users').doc(user.uid),
        image,
      ).set({
        'isTrashed': false,
        'deletedAt': FieldValue.delete(),
        if (roomWasDeleted) ...{
          'roomId': FieldValue.delete(),
          'roomTitle': '갤러리',
          'albumId': FieldValue.delete(),
        },
      }, SetOptions(merge: true));
      _reload();
    } catch (error) {
      _notify('사진을 복원하지 못했습니다: $error');
    }
  }

  Future<void> _permanentlyDeleteImage(
    DocumentReference<Map<String, dynamic>> userDocument,
    _GalleryImage image,
  ) async {
    try {
      await _storage.refFromURL(image.url).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
    final rooms = await userDocument.collection('chatRooms').get();
    for (final room in rooms.docs) {
      final messages = await room.reference
          .collection('messages')
          .where('imageUrl', isEqualTo: image.url)
          .get();
      for (final message in messages.docs) {
        await message.reference.delete();
      }
      final roomImages = await room.reference
          .collection('galleryImages')
          .where('url', isEqualTo: image.url)
          .get();
      for (final roomImage in roomImages.docs) {
        await roomImage.reference.delete();
      }
    }
    final galleryCopies = await userDocument
        .collection('chatGalleryImages')
        .where('url', isEqualTo: image.url)
        .get();
    for (final copy in galleryCopies.docs) {
      await copy.reference.delete();
    }
  }

  Future<void> _deleteForever(_GalleryImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('사진 완전 삭제'),
        content: Text('"${image.name}" 사진을 영구적으로 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('완전 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 사진을 삭제할 수 있습니다.');
      return;
    }
    try {
      await _permanentlyDeleteImage(
        langgryFirestore().collection('users').doc(user.uid),
        image,
      );
      _reload();
    } catch (error) {
      _notify('사진을 완전히 삭제하지 못했습니다: $error');
    }
  }

  Future<void> _toggleTrash() async {
    if (_draftNames.isNotEmpty) {
      await _confirmLeaveSelection();
      if (_selectionMode) return;
    }
    setState(() {
      _trashMode = !_trashMode;
      _selectionMode = false;
      _visibleImageCount = _pageSize;
      _selectedImageIds.clear();
      _draftNames.clear();
      _gallery = _loadGallery();
    });
  }

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _uploadImage() async {
    if (_uploading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _notify('선택한 사진을 읽을 수 없습니다.');
      return;
    }
    if (bytes.length > 10 * 1024 * 1024) {
      _notify('사진은 10MB 이하만 업로드할 수 있습니다.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 사진을 업로드할 수 있습니다.');
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'avif' => 'image/avif',
      _ => 'image/jpeg',
    };
    final id = const Uuid().v4();
    setState(() => _uploading = true);
    try {
      final reference = _storage.ref(
        'users/${user.uid}/chatGallery/$id',
      );
      await reference.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final url = await reference.getDownloadURL();
      final roomId = widget.roomId;
      final userDocument = langgryFirestore().collection('users').doc(user.uid);
      final imageDocument = roomId == null
          ? userDocument.collection('chatGalleryImages').doc(id)
          : userDocument
              .collection('chatRooms')
              .doc(roomId)
              .collection('galleryImages')
              .doc(id);
      final metadata = {
        'url': url,
        'name': file.name,
        'kind': 'uploaded',
        'createdAt': Timestamp.now(),
        if (roomId != null) 'roomId': roomId,
        if (roomId != null) 'roomTitle': widget.roomTitle ?? '채팅방',
      };
      await imageDocument.set(metadata);
      if (roomId != null) {
        await userDocument
            .collection('chatGalleryImages')
            .doc(id)
            .set(metadata);
      }
      if (!mounted) return;
      _reload();
      _notify('사진을 갤러리에 추가했습니다.');
    } catch (error) {
      _notify('사진을 업로드하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('새 앨범'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '앨범 이름',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 앨범을 만들 수 있습니다.');
      return;
    }
    try {
      final albums = langgryFirestore()
          .collection('users')
          .doc(user.uid)
          .collection('chatGalleryAlbums');
      final existing = await albums.get();
      if (existing.docs.any(
        (album) =>
            (album.data()['name'] as String? ?? '').trim().toLowerCase() ==
            name.toLowerCase(),
      )) {
        _notify('같은 이름의 앨범이 이미 있습니다.');
        return;
      }
      await albums.doc(const Uuid().v4()).set({
        'name': name,
        'createdAt': Timestamp.now(),
      });
      _reload();
    } catch (error) {
      _notify('앨범을 만들지 못했습니다: $error');
    }
  }

  Future<String?> _askAlbumName(String title, {String initialName = ''}) async {
    final controller = TextEditingController(text: initialName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '앨범 이름',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name?.trim();
  }

  Future<String?> _renameAlbum(String albumId, String oldName) async {
    final name = await _askAlbumName('앨범 이름 수정', initialName: oldName);
    if (name == null || name.isEmpty || !mounted) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 앨범 이름을 수정할 수 있습니다.');
      return null;
    }
    try {
      final userDocument = langgryFirestore().collection('users').doc(user.uid);
      final albums = userDocument.collection('chatGalleryAlbums');
      final existing = await albums.get();
      if (existing.docs.any(
        (album) =>
            album.id != albumId &&
            (album.data()['name'] as String? ?? '').trim().toLowerCase() ==
                name.toLowerCase(),
      )) {
        _notify('같은 이름의 앨범이 이미 있습니다.');
        return null;
      }
      await albums.doc(albumId).update({'name': name});
      _reload();
      return name;
    } catch (error) {
      _notify('앨범 이름을 수정하지 못했습니다: $error');
      return null;
    }
  }

  Future<bool> _deleteAlbum(String albumId, String albumName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('앨범 삭제'),
        content: Text(
          '"$albumName" 앨범을 삭제할까요? 사진은 갤러리에 남고 앨범에서만 제거됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 앨범을 삭제할 수 있습니다.');
      return false;
    }
    try {
      final userDocument = langgryFirestore().collection('users').doc(user.uid);
      final albumImages = await userDocument
          .collection('chatGalleryImages')
          .where('albumId', isEqualTo: albumId)
          .get();
      for (final image in albumImages.docs) {
        await image.reference.update({'albumId': FieldValue.delete()});
        final roomId = image.data()['roomId'] as String?;
        if (roomId == null) continue;
        final roomImage = await userDocument
            .collection('chatRooms')
            .doc(roomId)
            .collection('galleryImages')
            .doc(image.id)
            .get();
        if (roomImage.exists) {
          await roomImage.reference.update({'albumId': FieldValue.delete()});
        }
      }
      await userDocument.collection('chatGalleryAlbums').doc(albumId).delete();
      _reload();
      return true;
    } catch (error) {
      _notify('앨범을 삭제하지 못했습니다: $error');
      return false;
    }
  }

  Future<void> _manageAlbums(Map<String, String> albums) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 앨범을 관리할 수 있습니다.');
      return;
    }
    final albumList = albums.entries.toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('앨범 관리'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: albumList.isEmpty
                ? const Center(child: Text('등록된 앨범이 없습니다.'))
                : ListView.builder(
                    itemCount: albumList.length,
                    itemBuilder: (context, index) {
                      final album = albumList[index];
                      return ListTile(
                        title: Text(album.value),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: '이름 수정',
                              onPressed: () async {
                                final name = await _renameAlbum(
                                  album.key,
                                  album.value,
                                );
                                if (name != null) {
                                  setDialogState(() {
                                    albumList[index] = MapEntry(
                                      album.key,
                                      name,
                                    );
                                  });
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '앨범 삭제',
                              onPressed: () async {
                                if (await _deleteAlbum(
                                  album.key,
                                  album.value,
                                )) {
                                  setDialogState(() {
                                    albumList.removeAt(index);
                                  });
                                }
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageCurrentAlbums() async {
    final data = await _gallery;
    if (!mounted) return;
    await _manageAlbums(data.albums);
  }

  void _setImageAspectRatio(double ratio) {
    setState(() => _imageAspectRatio = ratio);
  }

  void _setGalleryView(_GalleryView view) {
    setState(() {
      _view = view;
      _visibleImageCount = _pageSize;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _setAlbum(
    _GalleryImage image,
    Map<String, String> albums,
  ) async {
    final selectedAlbum = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('앨범 지정')),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('앨범에서 제거'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final album in albums.entries)
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.value),
                onTap: () => Navigator.pop(context, album.key),
              ),
          ],
        ),
      ),
    );
    if (selectedAlbum == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _notify('로그인 후 앨범을 변경할 수 있습니다.');
      return;
    }
    try {
      final userDocument = langgryFirestore().collection('users').doc(user.uid);
      final metadata = {
        'url': image.url,
        'name': image.name,
        'kind': image.kind,
        'prompt': image.prompt,
        'createdAt': Timestamp.fromDate(image.createdAt),
        if (image.roomId != null) 'roomId': image.roomId,
        'roomTitle': image.roomTitle,
        'albumId': selectedAlbum.isEmpty ? FieldValue.delete() : selectedAlbum,
      };
      await _catalogReference(userDocument, image)
          .set(metadata, SetOptions(merge: true));
      if (image.roomId != null) {
        await userDocument
            .collection('chatRooms')
            .doc(image.roomId)
            .collection('galleryImages')
            .doc(image.id)
            .set(metadata, SetOptions(merge: true));
      }
      if (mounted) _reload();
    } catch (error) {
      _notify('앨범을 지정하지 못했습니다: $error');
    }
  }

  Future<void> _showImage(
    _GalleryImage image,
    Map<String, String> albums,
    List<_GalleryImage> images,
  ) {
    if (widget.selectionMode) {
      Navigator.of(context).pop(
        ChatGallerySelection(url: image.url, name: image.name),
      );
      return Future<void>.value();
    }
    final pageController = PageController(
      initialPage: images.indexWhere((candidate) => candidate.id == image.id),
    );
    var currentIndex =
        images.indexWhere((candidate) => candidate.id == image.id);
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final current = images[currentIndex];
          return Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 720,
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.62,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PageView.builder(
                          controller: pageController,
                          itemCount: images.length,
                          onPageChanged: (index) =>
                              setDialogState(() => currentIndex = index),
                          itemBuilder: (context, index) => InteractiveViewer(
                            child: Image.network(
                              images[index].url,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                        if (currentIndex > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton.filledTonal(
                              tooltip: '이전 사진',
                              onPressed: () => pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                              icon: const Icon(Icons.arrow_back_ios_new),
                            ),
                          ),
                        if (currentIndex < images.length - 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton.filledTonal(
                              tooltip: '다음 사진',
                              onPressed: () => pageController.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                              icon: const Icon(Icons.arrow_forward_ios),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(current.name),
                    subtitle: Text(
                      '${currentIndex + 1}/${images.length} · '
                      '${current.roomTitle} · '
                      '${current.kind == 'generated' ? '생성' : '업로드'} · '
                      '${_dateLabel(current.createdAt)}'
                      '${current.prompt.isEmpty ? '' : '\n${current.prompt}'}',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _setAlbum(current, albums);
                      },
                      icon: const Icon(Icons.photo_album_outlined),
                      label: Text(
                        current.albumId == null
                            ? '앨범에 추가'
                            : '앨범: ${albums[current.albumId] ?? '지정됨'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(pageController.dispose);
  }

  Map<String, List<_GalleryImage>> _groupImages(
    List<_GalleryImage> images,
    Map<String, String> albums,
  ) {
    final groups = <String, List<_GalleryImage>>{};
    for (final image in images) {
      final key = switch (_view) {
        _GalleryView.all =>
          '${image.createdAt.year}년 ${image.createdAt.month}월',
        _GalleryView.rooms => _roomGroupKey(image),
        _GalleryView.albums =>
          image.albumId == null ? '앨범 미지정' : albums[image.albumId] ?? '앨범 미지정',
      };
      groups.putIfAbsent(key, () => []).add(image);
    }
    return groups;
  }

  String _roomGroupKey(_GalleryImage image) =>
      image.roomId ?? 'legacy:${image.roomTitle}';

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_selectionMode || widget.roomId != null || widget.selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            _selectionMode &&
            widget.roomId == null &&
            !widget.selectionMode) {
          _confirmLeaveSelection();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _trashMode
                ? '휴지통'
                : widget.selectionMode
                    ? '참고 이미지 선택'
                    : widget.roomId == null
                        ? '사진 갤러리'
                        : '채팅방 갤러리',
          ),
          actions: [
            if (_selectionMode &&
                widget.roomId == null &&
                !widget.selectionMode &&
                !_trashMode)
              IconButton(
                onPressed: _confirmLeaveSelection,
                tooltip: '선택 모드 나가기',
                icon: const Icon(Icons.close_rounded),
              ),
            if (widget.roomId == null &&
                !widget.selectionMode &&
                !_selectionMode)
              IconButton(
                onPressed: _toggleTrash,
                tooltip: '휴지통',
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            if (_trashMode)
              IconButton(
                onPressed: _toggleTrash,
                tooltip: '갤러리로 돌아가기',
                icon: const Icon(Icons.photo_library_outlined),
              ),
            if (!widget.selectionMode) ...[
              if (!_trashMode && !_selectionMode) ...[
                PopupMenuButton<double>(
                  tooltip: '사진 비율',
                  initialValue: _imageAspectRatio,
                  onSelected: _setImageAspectRatio,
                  icon: const Icon(Icons.aspect_ratio_rounded),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 0.75,
                      child: Text('3:4 세로'),
                    ),
                    PopupMenuItem(
                      value: 1.3333333333,
                      child: Text('4:3 가로'),
                    ),
                    PopupMenuItem(
                      value: 0.5625,
                      child: Text('9:16 세로'),
                    ),
                    PopupMenuItem(
                      value: 1.7777777778,
                      child: Text('16:9 가로'),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _uploading ? null : _uploadImage,
                  tooltip: '사진 업로드',
                  icon: _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                ),
                IconButton(
                  onPressed: _createAlbum,
                  tooltip: '앨범 추가',
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
                IconButton(
                  onPressed: _manageCurrentAlbums,
                  tooltip: '앨범 관리',
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
            ],
            IconButton(
              onPressed: _reload,
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_GalleryData>(
          future: _gallery,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('갤러리를 불러오지 못했습니다: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final images = data.images;
            final previewImages = images.take(_visibleImageCount).toList();
            final groups = _groupImages(previewImages, data.albums);
            final canSelect =
                widget.roomId == null && !widget.selectionMode && !_trashMode;
            return Column(
              children: [
                if (!widget.selectionMode && !_trashMode && !_selectionMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: SegmentedButton<_GalleryView>(
                      segments: const [
                        ButtonSegment(
                          value: _GalleryView.all,
                          label: Text('전체'),
                          icon: Icon(Icons.photo_library_outlined),
                        ),
                        ButtonSegment(
                          value: _GalleryView.rooms,
                          label: Text('채팅방'),
                          icon: Icon(Icons.chat_bubble_outline),
                        ),
                        ButtonSegment(
                          value: _GalleryView.albums,
                          label: Text('앨범'),
                          icon: Icon(Icons.photo_album_outlined),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (selection) =>
                          _setGalleryView(selection.first),
                    ),
                  ),
                if (images.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.selectionMode
                            ? '참고할 사진이 없습니다. 갤러리에 사진을 추가해 주세요.'
                            : _trashMode
                                ? '휴지통이 비었습니다.'
                                : '사진이 없습니다. 오른쪽 위 버튼으로 사진을 추가해 보세요.',
                      ),
                    ),
                  )
                else if (_view == _GalleryView.albums && groups.isEmpty)
                  const Expanded(child: Center(child: Text('표시할 앨범 사진이 없습니다.')))
                else
                  Expanded(
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        for (final group in groups.entries) ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _view == _GalleryView.rooms
                                          ? group.value.first.roomTitle
                                          : group.key,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                childAspectRatio: _imageAspectRatio,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final image = group.value[index];
                                  final selected =
                                      _selectedImageIds.contains(image.id);
                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(
                                        color: selected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Colors.transparent,
                                        width: selected ? 2 : 0,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: InkWell(
                                      onTap: _trashMode
                                          ? null
                                          : _selectionMode && canSelect
                                              ? () => _toggleSelection(image)
                                              : () => _showImage(
                                                    image,
                                                    data.albums,
                                                    images,
                                                  ),
                                      onLongPress: canSelect
                                          ? () => _startSelection(image)
                                          : null,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                Image.network(
                                                  image.url,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Center(
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                                  ),
                                                ),
                                                if (canSelect && _selectionMode)
                                                  Positioned(
                                                    top: 4,
                                                    right: 4,
                                                    child: IgnorePointer(
                                                      child: Checkbox(
                                                        value: selected,
                                                        onChanged: (_) {},
                                                      ),
                                                    ),
                                                  ),
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    color: Colors.black54,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          _draftNames[
                                                                  image.id] ??
                                                              image.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        if (_trashMode)
                                                          Text(
                                                            '삭제 예정: ${_dateLabel(image.deletedAt.add(const Duration(days: 7)))}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        if (!_trashMode)
                                                          Text(
                                                            '${image.kind == 'generated' ? '생성' : '업로드'} · '
                                                            '${_dateLabel(image.createdAt)}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        if (_trashMode)
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .end,
                                                            children: [
                                                              IconButton(
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                tooltip: '복원',
                                                                onPressed: () =>
                                                                    _restoreImage(
                                                                        image),
                                                                icon:
                                                                    const Icon(
                                                                  Icons
                                                                      .restore_rounded,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                              IconButton(
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                tooltip:
                                                                    '완전히 삭제',
                                                                onPressed: () =>
                                                                    _deleteForever(
                                                                        image),
                                                                icon:
                                                                    const Icon(
                                                                  Icons
                                                                      .delete_forever_rounded,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                childCount: group.value.length,
                              ),
                            ),
                          ),
                        ],
                        if (_visibleImageCount < images.length)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  '${previewImages.length}/${images.length}장 표시 중 · 아래로 스크롤하면 더 불러옵니다',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: _selectionMode &&
                widget.roomId == null &&
                !widget.selectionMode &&
                !_trashMode
            ? SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('${_selectedImageIds.length}장 선택'),
                      ),
                      TextButton.icon(
                        onPressed: () => _toggleSelectAll(_currentImages),
                        icon: Icon(
                          _currentImages.isNotEmpty &&
                                  _currentImages
                                      .every(_selectedImageIds.contains)
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                        ),
                        label: Text(
                          _currentImages.isNotEmpty &&
                                  _currentImages
                                      .every(_selectedImageIds.contains)
                              ? '전체 해제'
                              : '전체 선택',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _selectedImageIds.length == 1
                            ? () {
                                final image = _currentImages.firstWhere(
                                  (item) => item.id == _selectedImageIds.first,
                                );
                                _editTitle(image);
                              }
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('제목 수정'),
                      ),
                      TextButton.icon(
                        onPressed: _selectedImageIds.isEmpty
                            ? null
                            : _moveSelectedToTrash,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('휴지통'),
                      ),
                      TextButton.icon(
                        onPressed: _draftNames.isEmpty
                            ? null
                            : () => _saveTitleChanges(),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('저장'),
                      ),
                      TextButton.icon(
                        onPressed: _confirmLeaveSelection,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('나가기'),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _GalleryData {
  const _GalleryData({required this.images, required this.albums});

  final List<_GalleryImage> images;
  final Map<String, String> albums;
}

class _GalleryImage {
  const _GalleryImage({
    required this.id,
    required this.url,
    required this.name,
    required this.roomId,
    required this.roomTitle,
    required this.prompt,
    required this.kind,
    required this.albumId,
    required this.createdAt,
    required this.isTrashed,
    required this.deletedAt,
  });

  final String id;
  final String url;
  final String name;
  final String? roomId;
  final String roomTitle;
  final String prompt;
  final String kind;
  final String? albumId;
  final DateTime createdAt;
  final bool isTrashed;
  final DateTime deletedAt;
}
