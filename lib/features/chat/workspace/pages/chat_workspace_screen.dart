import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:langgry/core/firebase/firestore_database.dart';
import 'package:langgry/features/chat/models/chat_room.dart';
import 'package:langgry/features/chat/models/chat_settings.dart';
import 'package:langgry/features/chat/models/friend.dart';
import 'package:langgry/features/chat/gallery/pages/chat_gallery_screen.dart';
import 'package:langgry/features/chat/room/pages/chat_room_screen.dart';
import 'package:langgry/features/chat/setup/pages/chat_room_settings_screen.dart';
import 'package:langgry/features/chat/setup/pages/chat_setup_screen.dart';
import 'package:langgry/features/chat/widgets/chat_avatar.dart';
import 'package:langgry/features/knowledge/services/knowledge_store.dart';

class ChatWorkspaceScreen extends StatefulWidget {
  const ChatWorkspaceScreen({
    required this.store,
    this.autoStart = false,
    super.key,
  });

  final KnowledgeStore store;
  final bool autoStart;

  @override
  State<ChatWorkspaceScreen> createState() => _ChatWorkspaceScreenState();
}

class _ChatWorkspaceScreenState extends State<ChatWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final List<ChatRoom> _rooms = [];
  final List<Friend> _friends = [];
  final Set<String> _startingFriendIds = {};
  final _firestore = langgryFirestore();
  bool _loading = true;
  bool _showHiddenFriends = false;

  @override
  void initState() {
    super.initState();
    _initFriends();
    _loadRooms().then((_) {
      if (widget.autoStart && mounted) {
        if (_rooms.isNotEmpty) {
          _openRoom(_rooms.first);
        } else {
          _createChat();
        }
      }
    });
  }

  void _initFriends() {
    _friends.addAll([
      Friend(
        id: 'emma-ai',
        name: 'Emma',
        description: 'AI 영어 회화 코치',
        type: 'ai',
        isFavorite: true,
        aiRole: '친절한 언어 학습 보조',
      ),
      Friend(
        id: 'japanese-ai',
        name: '일본어 선생님',
        description: 'AI 일본어 맞춤 학습 대상자',
        type: 'ai',
        isFavorite: false,
        aiRole: '일본어 대화 상대',
      ),
    ]);
  }

  Future<void> _loadRooms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final friends = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('chatFriends')
            .get();
        for (final document in friends.docs) {
          final data = document.data();
          final friend = Friend.fromMap(data, document.id);
          _friends.removeWhere((item) => item.id == friend.id);
          if (friend.isDeleted) continue;
          _friends.add(friend);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('AI 친구 목록을 불러오지 못했습니다: $error')),
          );
        }
      }
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('chatRooms')
            .get();
        _rooms.clear();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final legacyMessages =
              (data['messages'] as List?)?.whereType<String>().toList() ??
                  <String>[];
          if (legacyMessages.isNotEmpty) {
            final messages = doc.reference.collection('messages');
            for (var start = 0; start < legacyMessages.length; start += 450) {
              final batch = _firestore.batch();
              final end = (start + 450).clamp(0, legacyMessages.length);
              for (var index = start; index < end; index++) {
                batch.set(
                  messages.doc('legacy-${index.toString().padLeft(8, '0')}'),
                  {
                    'text': legacyMessages[index],
                    'createdAt': Timestamp.fromDate(
                      DateTime.utc(2000).add(Duration(seconds: index)),
                    ),
                  },
                );
              }
              await batch.commit();
            }
            await doc.reference.update({
              'messages': FieldValue.delete(),
              'lastMessage': legacyMessages.last,
            });
          }
          final room = _roomFromDocument(doc);
          final friend = _friendForRoom(room);
          if (room.isAi && room.settings.aiProfileImageUrl == null) {
            room.settings.aiProfileImageUrl = friend?.imageUrl;
          }
          room.lastMessage =
              await _loadLatestMessage(doc.reference) ?? room.lastMessage;
          _rooms.add(room);
        }
        _rooms.sort((left, right) =>
            (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
              left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ));
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('채팅방을 불러오지 못했습니다: $error')),
          );
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  ChatRoom _roomFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final settings = data['settings'] is Map
        ? Map<String, dynamic>.from(data['settings'] as Map)
        : <String, dynamic>{};
    return ChatRoom(
      id: document.id,
      title: data['title'] as String? ?? '채팅방',
      partner: data['partner'] as String? ?? 'AI 보조',
      isAi: data['isAi'] as bool? ?? true,
      settings: ChatSettings.fromMap(settings),
      friendId: data['friendId'] as String?,
      lastMessage: data['lastMessage'] as String?,
      updatedAt: _dateFrom(data['updatedAt']),
    );
  }

  Future<void> _createChat() async {
    final visibleFriends = _friends.where((friend) => !friend.isHidden).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    if (visibleFriends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅할 친구가 없습니다. 친구 목록에 먼저 추가해 주세요.')),
      );
      return;
    }
    final selectedFriend = await showDialog<Friend>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('대화할 친구 선택'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.separated(
            itemCount: visibleFriends.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final friend = visibleFriends[index];
              return ListTile(
                leading: ChatAvatar(
                  isAi: friend.isAi,
                  imageUrl: friend.imageUrl,
                ),
                title: Text(friend.name),
                subtitle: Text(
                  friend.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(dialogContext).pop(friend),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (selectedFriend == null || !mounted) return;

    final initialSettings = ChatSettings(
      name: selectedFriend.name,
      partnerType: selectedFriend.isAi ? 'AI' : '타유저',
      role: selectedFriend.aiRole ?? selectedFriend.description,
      tone: '친근하게',
      saveEvery: 10,
      selectedSources: const [],
      selectedParticipantIds: [selectedFriend.id],
      aiProfileImageUrl: selectedFriend.imageUrl,
      aiTraits: selectedFriend.traits,
      instructionHistory: selectedFriend.assistantInstructions,
    );
    final settings = await Navigator.of(context).push<ChatSettings>(
      MaterialPageRoute(
        builder: (_) => ChatSetupScreen(
          initialSettings: initialSettings,
          isRoomCreation: true,
        ),
      ),
    );
    if (settings == null || !mounted) return;

    final roomSettings =
        await Navigator.of(context).push<ChatRoomSettingsResult>(
      MaterialPageRoute(
        builder: (_) => ChatRoomSettingsScreen(
          initialTitle: '${selectedFriend.name}와의 대화',
          initialSettings: settings,
          store: widget.store,
          friends: _friends.where((friend) => !friend.isDeleted).toList(),
          primaryFriendId: selectedFriend.id,
        ),
      ),
    );
    if (roomSettings == null || !mounted) return;
    await _createRoomForFriend(
      selectedFriend,
      roomSettings.title,
      roomSettings.settings,
    );
  }

  Future<void> _addAiProfile() async {
    final settings = await Navigator.of(context).push<ChatSettings>(
      MaterialPageRoute(builder: (_) => const ChatSetupScreen()),
    );
    if (settings == null || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 AI 친구를 추가할 수 있습니다.')),
      );
      return;
    }

    final friend = Friend(
      id: 'ai-${DateTime.now().microsecondsSinceEpoch}',
      name: settings.name,
      description: settings.role,
      type: 'ai',
      imageUrl: settings.aiProfileImageUrl,
      aiRole: settings.role,
      traits: settings.aiTraits,
      assistantInstructions: settings.instructionHistory,
    );
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chatFriends')
          .doc(friend.id)
          .set(friend.toMap());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 친구를 저장하지 못했습니다: $error')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _friends.add(friend));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${friend.name} AI 친구를 추가했습니다.')),
    );
  }

  Future<void> _createRoomForFriend(
    Friend friend,
    String title,
    ChatSettings settings,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 채팅방을 만들 수 있습니다.')),
      );
      return;
    }
    final room = ChatRoom(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      partner: friend.name,
      isAi: friend.isAi,
      settings: settings,
      friendId: friend.id,
    );
    setState(() => _rooms.insert(0, room));
    await _saveRoom(room);
    if (mounted) await _openRoom(room);
  }

  Future<void> _saveRoom(ChatRoom room) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chatRooms')
          .doc(room.id)
          .set({
        'title': room.title,
        'partner': room.partner,
        'isAi': room.isAi,
        if (room.friendId != null) 'friendId': room.friendId,
        'settings': room.settings.toMap(),
        if (room.lastMessage != null) 'lastMessage': room.lastMessage,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('채팅방 정보를 저장하지 못했습니다: $error')),
        );
      }
    }
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          room: room,
          store: widget.store,
          friends: _friends.where((friend) => !friend.isDeleted).toList(),
          onChanged: () => _saveRoom(room),
          onAiSettingsChanged: (settings) =>
              _saveAiFriendSettings(room, settings),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Friend? _friendForRoom(ChatRoom room) {
    for (final friend in _friends) {
      if (room.friendId == friend.id) return friend;
    }
    return null;
  }

  Future<void> _saveAiFriendSettings(
    ChatRoom room,
    ChatSettings settings,
  ) async {
    if (!room.isAi || room.friendId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인된 사용자가 없어 AI 친구 설정을 저장할 수 없습니다.')),
        );
      }
      return;
    }
    final index = _friends.indexWhere((friend) => friend.id == room.friendId);
    final previous = index < 0 ? null : _friends[index];
    final updated = Friend(
      id: room.friendId!,
      name: settings.name,
      description: settings.role,
      type: 'ai',
      imageUrl: settings.aiProfileImageUrl,
      isFavorite: previous?.isFavorite ?? false,
      isHidden: previous?.isHidden ?? false,
      aiRole: settings.role,
      traits: settings.aiTraits,
      assistantInstructions: settings.instructionHistory,
    );
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chatFriends')
          .doc(updated.id)
          .set(updated.toMap(), SetOptions(merge: true));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 친구 설정을 저장하지 못했습니다: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      if (index < 0) {
        _friends.add(updated);
      } else {
        _friends[index] = updated;
      }
    });
  }

  Future<void> _toggleFriendHidden(Friend friend, bool hidden) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    final updated = Friend(
      id: friend.id,
      name: friend.name,
      description: friend.description,
      type: friend.type,
      imageUrl: friend.imageUrl,
      isFavorite: friend.isFavorite,
      isHidden: hidden,
      aiRole: friend.aiRole,
      traits: friend.traits,
      assistantInstructions: friend.assistantInstructions,
    );
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('chatFriends')
        .doc(friend.id)
        .set(updated.toMap(), SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      final index = _friends.indexWhere((item) => item.id == friend.id);
      if (index >= 0) _friends[index] = updated;
    });
  }

  Future<void> _deleteFriend(Friend friend) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    final userDocument = _firestore.collection('users').doc(user.uid);
    final rooms = await userDocument.collection('chatRooms').get();
    final matchingRooms = rooms.docs.where((document) {
      final data = document.data();
      final settings = data['settings'];
      final chatType = settings is Map ? settings['chatType'] as String? : null;
      final isOneToOne =
          chatType == null || chatType == 'ai_user' || chatType == 'user_user';
      if (!isOneToOne) return false;
      final roomFriendId = data['friendId'] as String?;
      if (roomFriendId != null && roomFriendId.isNotEmpty) {
        return roomFriendId == friend.id;
      }
      final isAi = data['isAi'];
      if (isAi is bool && isAi != friend.isAi) return false;
      final partner = data['partner'] as String? ?? '';
      final settingsName =
          settings is Map ? settings['name'] as String? ?? '' : '';
      final name = friend.name.trim().toLowerCase();
      return partner.trim().toLowerCase() == name ||
          settingsName.trim().toLowerCase() == name;
    }).toList();

    for (final room in matchingRooms) {
      await _deleteRoomDocument(room.reference);
    }

    final friendReference =
        userDocument.collection('chatFriends').doc(friend.id);
    if (friend.id == 'emma-ai' || friend.id == 'japanese-ai') {
      await friendReference.set({...friend.toMap(), 'isDeleted': true});
    } else {
      await friendReference.delete();
    }
    if (!mounted) return;
    setState(() {
      _friends.removeWhere((item) => item.id == friend.id);
      _rooms.removeWhere(
        (room) => matchingRooms.any((document) => document.id == room.id),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${friend.name} 친구와 1:1 채팅방 ${matchingRooms.length}개를 삭제했습니다.',
        ),
      ),
    );
  }

  Future<void> _deleteRoom(ChatRoom room) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    await _deleteRoomDocument(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chatRooms')
          .doc(room.id),
    );
    if (!mounted) return;
    setState(() => _rooms.removeWhere((item) => item.id == room.id));
  }

  Future<void> _deleteRoomDocument(
    DocumentReference<Map<String, dynamic>> roomReference,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    final userDocument = _firestore.collection('users').doc(user.uid);
    final messages = await roomReference.collection('messages').get();
    final roomImages = await roomReference.collection('galleryImages').get();
    final catalogImages = await userDocument
        .collection('chatGalleryImages')
        .where('roomId', isEqualTo: roomReference.id)
        .get();
    final trashedCatalogImages = catalogImages.docs
        .where((document) => document.data()['isTrashed'] == true)
        .toList();
    final trashedImageUrls = trashedCatalogImages
        .map((document) => document.data()['url'])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet();
    for (final document in trashedCatalogImages) {
      await document.reference.update({
        'roomId': FieldValue.delete(),
        'roomTitle': '갤러리',
        'albumId': FieldValue.delete(),
      });
    }
    final imageUrls = <String>{
      for (final document in messages.docs)
        if (document.data()['imageUrl'] case final String url)
          if (url.isNotEmpty && !trashedImageUrls.contains(url)) url,
      for (final document in roomImages.docs)
        if (document.data()['url'] case final String url)
          if (url.isNotEmpty && !trashedImageUrls.contains(url)) url,
      for (final document in catalogImages.docs)
        if (document.data()['url'] case final String url)
          if (url.isNotEmpty && !trashedImageUrls.contains(url)) url,
    };
    final storage = FirebaseStorage.instanceFor(
      app: Firebase.app(),
      bucket: 'gs://languagehungry.firebasestorage.app',
    );
    for (final url in imageUrls) {
      final reference = storage.refFromURL(url);
      final roomImagePrefix =
          'users/${user.uid}/chatRooms/${roomReference.id}/images/';
      final galleryImagePrefix = 'users/${user.uid}/chatGallery/';
      if (!reference.fullPath.startsWith(roomImagePrefix) &&
          !reference.fullPath.startsWith(galleryImagePrefix)) {
        continue;
      }
      try {
        await reference.delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }

    final documentsToDelete = <DocumentReference<Map<String, dynamic>>>[
      ...messages.docs.map((document) => document.reference),
      ...roomImages.docs.map((document) => document.reference),
      ...catalogImages.docs
          .where((document) => document.data()['isTrashed'] != true)
          .map((document) => document.reference),
    ];
    for (var start = 0; start < documentsToDelete.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, documentsToDelete.length).toInt();
      for (var index = start; index < end; index++) {
        batch.delete(documentsToDelete[index]);
      }
      await batch.commit();
    }
    await roomReference.delete();
  }

  DateTime? _dateFrom(Object? value) => switch (value) {
        Timestamp timestamp => timestamp.toDate(),
        DateTime date => date,
        int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
        _ => null,
      };

  Future<String?> _loadLatestMessage(
    DocumentReference<Map<String, dynamic>> room,
  ) async {
    final snapshot = await room
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final data = snapshot.docs.first.data();
    final message = data['text'] ?? data['message'] ?? data['content'];
    return message is String ? message : null;
  }

  void _addFriend() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('친구 추가'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '친구 아이디 또는 이메일',
              hintText: '예: friend@example.com',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _friends.add(
                    Friend(
                      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
                      name: text.split('@').first,
                      description: text,
                      type: 'human',
                    ),
                  );
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$text 님을 친구로 추가했습니다.')),
                );
              }
              Navigator.of(dialogContext).pop();
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  void _showMyQrCode() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'my_user_id_123';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('내 아이디 QR 코드'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.indigo.shade200, width: 2),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2_rounded,
                        size: 100, color: Colors.indigo),
                    SizedBox(height: 8),
                    Text('SCAN ME',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('ID: $email',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ChatGalleryScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          IconButton(
            onPressed: _createChat,
            tooltip: '새 채팅',
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_outlined), text: '친구목록'),
            Tab(icon: Icon(Icons.forum_outlined), text: '채팅방'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _FriendsTab(
                  friends: _friends,
                  onAddFriend: _addFriend,
                  onAddAiProfile: _addAiProfile,
                  onOpenGallery: _openGallery,
                  onShowMyQr: _showMyQrCode,
                  onToggleFavorite: (friend) {
                    setState(() => friend.isFavorite = !friend.isFavorite);
                  },
                  showHiddenFriends: _showHiddenFriends,
                  onToggleHiddenView: () {
                    setState(() => _showHiddenFriends = !_showHiddenFriends);
                  },
                  onToggleHidden: _toggleFriendHidden,
                  onDeleteFriend: _deleteFriend,
                  onStartChatWithFriend: _startChatWithFriend,
                ),
                _RoomsTab(
                  rooms: _rooms,
                  onOpen: _openRoom,
                  onCreate: _createChat,
                  onDelete: _deleteRoom,
                ),
              ],
            ),
    );
  }

  Future<void> _startChatWithFriend(
    Friend friend, {
    ChatSettings? initialSettings,
  }) async {
    if (!_startingFriendIds.add(friend.id)) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('로그인한 뒤 채팅을 시작할 수 있습니다.');
      }

      final roomCollection =
          _firestore.collection('users').doc(user.uid).collection('chatRooms');
      final roomSnapshot = await roomCollection.get();
      final matchingDocuments = roomSnapshot.docs
          .where(
            (document) => _roomDocumentMatchesFriend(document.data(), friend),
          )
          .toList()
        ..sort((left, right) {
          final leftDate = _dateFrom(left.data()['updatedAt']);
          final rightDate = _dateFrom(right.data()['updatedAt']);
          return (rightDate ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(leftDate ?? DateTime.fromMillisecondsSinceEpoch(0));
        });

      ChatRoom? room;
      if (matchingDocuments.isNotEmpty) {
        final document = matchingDocuments.first;
        room = _roomFromDocument(document);
        room.friendId = friend.id;
        room.lastMessage ??= await _loadLatestMessage(document.reference);
        final roomIndex =
            _rooms.indexWhere((candidate) => candidate.id == room!.id);
        if (roomIndex >= 0) {
          _rooms[roomIndex] = room;
        } else {
          _rooms.add(room);
        }
        await _saveRoom(room);
      } else {
        final settings = initialSettings ??
            ChatSettings(
              name: friend.name,
              partnerType: friend.isAi ? 'AI' : '타유저',
              role: friend.aiRole ?? friend.description,
              tone: '친근하게',
              saveEvery: 10,
              selectedSources: const [],
              aiProfileImageUrl: friend.imageUrl,
            );
        room = ChatRoom(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: '${friend.name}와의 대화',
          partner: friend.name,
          isAi: friend.isAi,
          settings: settings,
          friendId: friend.id,
        );
        _rooms.insert(0, room);
        await _saveRoom(room);
      }
      if (mounted) await _openRoom(room);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('채팅방을 확인하지 못했습니다: $error')),
        );
      }
    } finally {
      _startingFriendIds.remove(friend.id);
    }
  }

  bool _roomDocumentMatchesFriend(
    Map<String, dynamic> data,
    Friend friend,
  ) {
    final roomFriendId = data['friendId'] as String?;
    if (roomFriendId != null && roomFriendId.isNotEmpty) {
      return roomFriendId == friend.id;
    }
    final isAi = data['isAi'];
    if (isAi is bool && isAi != friend.isAi) return false;

    final settings = data['settings'];
    final settingsName = settings is Map ? settings['name'] as String? : null;
    final title = data['title'] as String? ?? '';
    final name = friend.name.trim().toLowerCase();
    return [
          data['partner'] as String?,
          settingsName,
        ]
            .whereType<String>()
            .any((candidate) => candidate.trim().toLowerCase() == name) ||
        title.trim().toLowerCase() == '${name}와의 대화';
  }
}

class _FriendsTab extends StatelessWidget {
  const _FriendsTab({
    required this.friends,
    required this.onAddFriend,
    required this.onAddAiProfile,
    required this.onOpenGallery,
    required this.onShowMyQr,
    required this.onToggleFavorite,
    required this.showHiddenFriends,
    required this.onToggleHiddenView,
    required this.onToggleHidden,
    required this.onDeleteFriend,
    required this.onStartChatWithFriend,
  });

  final List<Friend> friends;
  final VoidCallback onAddFriend;
  final VoidCallback onAddAiProfile;
  final VoidCallback onOpenGallery;
  final VoidCallback onShowMyQr;
  final ValueChanged<Friend> onToggleFavorite;
  final bool showHiddenFriends;
  final VoidCallback onToggleHiddenView;
  final Future<void> Function(Friend friend, bool hidden) onToggleHidden;
  final Future<void> Function(Friend friend) onDeleteFriend;
  final ValueChanged<Friend> onStartChatWithFriend;

  @override
  Widget build(BuildContext context) {
    final hiddenCount = friends.where((friend) => friend.isHidden).length;
    final sortedFriends = List<Friend>.from(
      friends.where((friend) => friend.isHidden == showHiddenFriends),
    )..sort((a, b) {
        if (a.isFavorite == b.isFavorite) return a.name.compareTo(b.name);
        return a.isFavorite ? -1 : 1;
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final buttonWidth = constraints.maxWidth >= 700
                ? (constraints.maxWidth - 36) / 4
                : (constraints.maxWidth - 12) / 2;
            final actions = [
              OutlinedButton.icon(
                onPressed: onAddFriend,
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('친구 추가', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: onAddAiProfile,
                icon: const Icon(Icons.smart_toy_rounded, size: 18),
                label: const Text('AI 친구 추가', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: onOpenGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('갤러리', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: onShowMyQr,
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                label: const Text('내 QR 생성', style: TextStyle(fontSize: 12)),
              ),
            ];
            return Wrap(
              spacing: 4,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  SizedBox(width: buttonWidth, child: action),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          '친구 및 AI 캐릭터 목록',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        if (hiddenCount > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onToggleHiddenView,
              icon: Icon(
                showHiddenFriends
                    ? Icons.people_alt_outlined
                    : Icons.visibility_off_outlined,
              ),
              label: Text(
                showHiddenFriends ? '친구 목록 보기' : '숨김 친구 보기 ($hiddenCount)',
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (sortedFriends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                showHiddenFriends ? '숨긴 친구가 없습니다.' : '친구가 없습니다.',
              ),
            ),
          ),
        ...sortedFriends.map(
          (friend) => Card(
            child: ListTile(
              leading: ChatAvatar(
                isAi: friend.isAi,
                imageUrl: friend.imageUrl,
              ),
              title: Row(
                children: [
                  Text(friend.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (friend.isAi) ...[
                    const SizedBox(width: 6),
                    Chip(
                      label: const Text('AI', style: TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              subtitle: Text(friend.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      friend.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: friend.isFavorite ? Colors.amber : Colors.grey,
                    ),
                    onPressed: () => onToggleFavorite(friend),
                    tooltip: '즐겨찾기',
                  ),
                  if (!friend.isHidden)
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      onPressed: () => onStartChatWithFriend(friend),
                      tooltip: '채팅 시작',
                    ),
                  PopupMenuButton<String>(
                    tooltip: '친구 관리',
                    onSelected: (action) async {
                      if (action == 'hide' || action == 'unhide') {
                        try {
                          await onToggleHidden(friend, action == 'hide');
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('친구 숨김 상태를 변경하지 못했습니다: $error'),
                              ),
                            );
                          }
                        }
                      } else if (action == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('친구와 대화 삭제'),
                            content: Text(
                              '${friend.name} 친구를 삭제하고 연결된 1:1 채팅방과 대화 내용을 모두 삭제할까요? '
                              '그룹 채팅방은 삭제되지 않습니다.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('취소'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('삭제'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await onDeleteFriend(friend);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('친구를 삭제하지 못했습니다: $error'),
                              ),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: friend.isHidden ? 'unhide' : 'hide',
                        child: Text(friend.isHidden ? '숨김 해제' : '친구 숨김'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('친구 및 1:1 대화 삭제'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab({
    required this.rooms,
    required this.onOpen,
    required this.onCreate,
    required this.onDelete,
  });

  final List<ChatRoom> rooms;
  final ValueChanged<ChatRoom> onOpen;
  final VoidCallback onCreate;
  final Future<void> Function(ChatRoom room) onDelete;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, size: 58, color: Colors.indigo),
              const SizedBox(height: 12),
              const Text('아직 채팅방이 없습니다.',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('AI 설정을 완료하고 첫 대화를 시작해 보세요.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('AI 설정하고 시작하기'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = rooms[index];
        return Card(
          child: ListTile(
            leading: ChatAvatar(
              isAi: room.isAi,
              imageUrl: room.settings.groupProfileImageUrl ??
                  room.settings.aiProfileImageUrl,
            ),
            title: Text(room.title),
            subtitle: Text(
              room.lastMessage ?? '대화를 시작해 보세요.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: room.lastMessage == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '채팅방 관리',
              onSelected: (action) async {
                if (action != 'delete') return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('채팅방 삭제'),
                    content: Text(
                      '"${room.title}" 채팅방과 저장된 대화 내용을 모두 삭제할까요?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await onDelete(room);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('채팅방을 삭제하지 못했습니다: $error')),
                    );
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('채팅방 삭제'),
                ),
              ],
            ),
            onTap: () => onOpen(room),
          ),
        );
      },
    );
  }
}
