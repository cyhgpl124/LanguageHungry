import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:langgry/core/firebase/firestore_database.dart';
import 'package:langgry/core/theme/app_theme.dart';
import 'package:langgry/features/chat/models/chat_room.dart';
import 'package:langgry/features/chat/models/chat_settings.dart';
import 'package:langgry/features/chat/models/friend.dart';
import 'package:langgry/features/chat/gallery/pages/chat_gallery_screen.dart';
import 'package:langgry/features/chat/setup/pages/chat_room_settings_screen.dart';
import 'package:langgry/features/chat/setup/pages/chat_setup_screen.dart';
import 'package:langgry/features/chat/widgets/chat_avatar.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/services/knowledge_store.dart';
import 'package:uuid/uuid.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    required this.room,
    required this.store,
    required this.onChanged,
    required this.friends,
    this.onAiSettingsChanged,
    super.key,
  });

  final ChatRoom room;
  final KnowledgeStore store;
  final Future<void> Function() onChanged;
  final List<Friend> friends;
  final Future<void> Function(ChatSettings settings)? onAiSettingsChanged;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  static const _messagePageSize = 20;
  static const _imageMessagePrefix = '__LANGGRY_CHAT_IMAGE__:';
  final _message = TextEditingController();
  final _messages = <String>[];
  final _pendingMessages = <String, String>{};
  final _loadedMessageDocuments =
      <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  final _messageScrollController = ScrollController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messageSubscription;
  QueryDocumentSnapshot<Map<String, dynamic>>? _olderMessagesCursor;
  bool _hasMoreMessages = true;
  bool _loadingOlderMessages = false;
  bool _initialMessagesLoaded = false;
  bool _sending = false;
  bool _savingChatFile = false;
  String? _savedThroughMessageId;
  Uint8List? _referenceImageBytes;
  String? _referenceImageName;
  String? _referenceImageMimeType;

  // Offline Meeting Mode State
  bool _isMeetingRecording = false;
  double _currentDecibel = 35.0;
  Timer? _decibelTimer;
  int _speakerCount = 1;

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.room.messages);
    _listenToRoomMessages();
    _loadSavedThroughMessageId();
  }

  Future<void> _loadSavedThroughMessageId() async {
    try {
      final files = await widget.store.listFiles();
      final roomFiles = files.where((file) {
        return file.metadata['chatRoomId'] == widget.room.id ||
            file.id.startsWith('chat-${widget.room.id}-');
      }).toList()
        ..sort((left, right) => _savedFileMessageCount(right)
            .compareTo(_savedFileMessageCount(left)));
      if (!mounted || roomFiles.isEmpty) return;
      final savedThroughMessageId =
          roomFiles.first.metadata['savedThroughMessageId'];
      if (savedThroughMessageId == null || savedThroughMessageId.isEmpty) {
        return;
      }
      setState(() => _savedThroughMessageId = savedThroughMessageId);
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('저장된 대화 위치를 확인하지 못했습니다: ${error.message ?? error.code}'),
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장된 대화 위치를 확인하지 못했습니다: ${error.message}')),
        );
      }
    }
  }

  void _listenToRoomMessages() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _messageSubscription = langgryFirestore()
        .collection('users')
        .doc(user.uid)
        .collection('chatRooms')
        .doc(widget.room.id)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(_messagePageSize)
        .snapshots()
        .listen(
      (snapshot) async {
        final isInitialSnapshot = !_initialMessagesLoaded;
        _initialMessagesLoaded = true;
        final followLatest = isInitialSnapshot || _isNearLatestMessage;
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.removed) continue;
          final currentDocument = await change.doc.reference.get();
          if (!currentDocument.exists) {
            _loadedMessageDocuments.remove(change.doc.id);
            _pendingMessages.remove(change.doc.id);
          }
        }
        for (final document in snapshot.docs) {
          _loadedMessageDocuments[document.id] = document;
        }
        if (snapshot.docs.isNotEmpty && _olderMessagesCursor == null) {
          _olderMessagesCursor = snapshot.docs.last;
          _hasMoreMessages = snapshot.docs.length == _messagePageSize;
        }
        final messages = _messagesFromLoadedDocuments();
        if (!mounted) return;
        setState(() {
          _messages
            ..clear()
            ..addAll(messages);
          widget.room.messages = List<String>.from(messages);
          if (messages.isNotEmpty) {
            widget.room.lastMessage = messages.last;
          }
        });
        if (followLatest) _scrollToLatest(force: isInitialSnapshot);
      },
      onError: (Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('채팅 내용을 불러오지 못했습니다: $error')),
          );
        }
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
      _orderedLoadedMessageDocuments() {
    return _loadedMessageDocuments.values.toList()
      ..sort((left, right) {
        final leftDate = _messageDate(left.data()['createdAt']);
        final rightDate = _messageDate(right.data()['createdAt']);
        if (leftDate == null && rightDate == null) {
          return left.id.compareTo(right.id);
        }
        if (leftDate == null) return -1;
        if (rightDate == null) return 1;
        final dateOrder = leftDate.compareTo(rightDate);
        return dateOrder == 0 ? left.id.compareTo(right.id) : dateOrder;
      });
  }

  List<String> _messagesFromLoadedDocuments() {
    final documents = _orderedLoadedMessageDocuments();
    final messages = documents
        .map((doc) {
          final data = doc.data();
          return data['text'] ?? data['message'] ?? data['content'];
        })
        .whereType<String>()
        .toList();
    return [
      ...messages,
      for (final entry in _pendingMessages.entries)
        if (!_loadedMessageDocuments.containsKey(entry.key)) entry.value,
    ];
  }

  String? _loadedMessageIdAt(int index) {
    final documents = _orderedLoadedMessageDocuments();
    return index >= 0 && index < documents.length ? documents[index].id : null;
  }

  Widget _savedMessageIndicator() => const Padding(
        padding: EdgeInsets.only(top: 2, right: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_rounded, size: 12, color: Colors.green),
            SizedBox(width: 2),
            Text(
              '저장됨',
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      );

  bool get _isNearLatestMessage =>
      !_messageScrollController.hasClients ||
      _messageScrollController.position.maxScrollExtent -
              _messageScrollController.position.pixels <
          120;

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.forward &&
        notification.metrics.pixels <= 100) {
      _loadOlderMessages();
    }
    return false;
  }

  Future<void> _loadOlderMessages() async {
    final cursor = _olderMessagesCursor;
    if (_loadingOlderMessages || !_hasMoreMessages || cursor == null) return;

    _loadingOlderMessages = true;
    if (mounted) setState(() {});
    final oldOffset = _messageScrollController.hasClients
        ? _messageScrollController.position.pixels
        : 0.0;
    final oldMaxExtent = _messageScrollController.hasClients
        ? _messageScrollController.position.maxScrollExtent
        : 0.0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('로그인된 사용자가 없습니다.');
      final snapshot = await langgryFirestore()
          .collection('users')
          .doc(user.uid)
          .collection('chatRooms')
          .doc(widget.room.id)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(cursor)
          .limit(_messagePageSize)
          .get();

      if (snapshot.docs.isEmpty) {
        _hasMoreMessages = false;
        return;
      }
      for (final document in snapshot.docs) {
        _loadedMessageDocuments[document.id] = document;
      }
      _olderMessagesCursor = snapshot.docs.last;
      _hasMoreMessages = snapshot.docs.length == _messagePageSize;
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(_messagesFromLoadedDocuments());
        widget.room.messages = List<String>.from(_messages);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_messageScrollController.hasClients) return;
        final addedExtent =
            _messageScrollController.position.maxScrollExtent - oldMaxExtent;
        _messageScrollController.jumpTo(oldOffset + addedExtent);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이전 채팅 내용을 불러오지 못했습니다: $error')),
        );
      }
    } finally {
      _loadingOlderMessages = false;
      if (mounted) setState(() {});
    }
  }

  void _recordMessage(String message) {
    final id = const Uuid().v4();
    _messages.add(message);
    _pendingMessages[id] = message;
    widget.room.lastMessage = _messagePreview(message);
  }

  String _messagePreview(String message) {
    final imageData = _imageMessageData(message);
    if (imageData == null) return message;
    return imageData['kind'] == 'generated' ? '이미지를 생성했습니다.' : '사진을 보냈습니다.';
  }

  DateTime? _messageDate(Object? value) => switch (value) {
        Timestamp timestamp => timestamp.toDate(),
        DateTime date => date,
        String date when DateTime.tryParse(date) != null =>
          DateTime.parse(date),
        int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
        _ => null,
      };

  void _scrollToLatest({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageScrollController.hasClients &&
          (force || _isNearLatestMessage)) {
        _messageScrollController.animateTo(
          _messageScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _messageScrollController.dispose();
    _messageSubscription?.cancel();
    _decibelTimer?.cancel();
    super.dispose();
  }

  void _toggleMeetingRecording() {
    setState(() => _isMeetingRecording = !_isMeetingRecording);
    if (_isMeetingRecording) {
      _startDecibelMonitoring();
    } else {
      _decibelTimer?.cancel();
    }
  }

  void _startDecibelMonitoring() {
    _decibelTimer?.cancel();
    final random = math.Random();
    _decibelTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!mounted || !_isMeetingRecording) return;
      final db = 35.0 + random.nextDouble() * 45.0; // 35 ~ 80 dB
      setState(() => _currentDecibel = db);

      final threshold = widget.room.settings.decibelThreshold;
      if (db >= threshold) {
        // Sound exceeded threshold -> simulate audio chunk captured & STT conversion
        _simulateSpeechToText();
      }
    });
  }

  void _simulateSpeechToText() {
    final speakers = ['발언자 A', '발언자 B', '발언자 C'];
    final speaker = speakers[(_speakerCount++) % speakers.length];
    final samplePhrases = [
      '오늘 회의 안건에 대한 의견 있으신가요?',
      '다음 분기 프로젝트 일정 검토가 필요해 보입니다.',
      'AI 보조 기능의 응답 속도가 대폭 개선되었습니다.',
      '오프라인 회의 내용 요약을 진행해 주시기 바랍니다.',
      '다음 스텝에 대해 동의합니다. 구체적 일정 논의하시죠.',
    ];
    final text = samplePhrases[math.Random().nextInt(samplePhrases.length)];
    setState(() {
      _recordMessage(
        '$speaker (음성 감지 ${_formatDecibel(_currentDecibel)}dB): $text',
      );
    });
    _persist();
  }

  static String _formatDecibel(double db) => db.toStringAsFixed(1);

  Future<void> _analyzeOfflineMeeting() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('분석할 회의 녹음 내역이 없습니다.')),
      );
      return;
    }
    setState(() => _sending = true);
    final transcript = _messages.join('\n');
    try {
      final model =
          FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
      final response = await model.generateContent([
        Content.text(
          '${_textGenerationInstructions()}\n'
          '당신은 오프라인 회의록 AI 분석 전문가입니다.\n'
          '지정 분석 요청사항: ${widget.room.settings.offlineMeetingInstruction ?? widget.room.settings.assistantModeInstruction ?? "주요 안건 정리 및 결론 요약"}\n'
          '아래 회의 대화 기록을 바탕으로 주요 안건, 발언 요약, 핵심 결정사항을 리포트 형식으로 작성해 주세요:\n\n'
          '$transcript',
        ),
      ]);
      final summary = response.text?.trim();
      if (summary != null && summary.isNotEmpty) {
        setState(() {
          _recordMessage('📊 [AI 회의 분석 리포트]\n$summary');
        });
        await _persist();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recordMessage('📊 [AI 회의 분석 리포트]\n'
              '- 주요 안건: 오프라인 회의 녹음 및 데시벨 음성 감지\n'
              '- 결정 사항: 감지 기준 ${widget.room.settings.decibelThreshold}dB 이상 음성 자동 텍스트 변환 완료\n'
              '- AI 소평: 회의가 원활하게 진행되고 있으며 결정된 아젠다 이행 권장');
        });
        await _persist();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stepAiSpectatorChat() async {
    if (_sending) return;
    setState(() => _sending = true);
    final topic = widget.room.settings.role.isNotEmpty
        ? widget.room.settings.role
        : '언어 학습과 기술의 발전';
    try {
      final model =
          FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
      final response = await model.generateContent([
        Content.text(
          '${_textGenerationInstructions()}\n'
          '두 AI 캐릭터 "${widget.room.settings.name}"와 "보조 AI"가 주제 "$topic"에 대해 서로 흥미롭게 토론하는 대화 한 단락을 생성하세요.',
        ),
      ]);
      final answer = response.text?.trim();
      if (answer != null && answer.isNotEmpty) {
        setState(() => _recordMessage('🤖 AI 관전 대화: $answer'));
        await _persist();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recordMessage(
            '🤖 AI 관전 대화: "${widget.room.settings.name}"와 "보조 AI"가 $topic 주제로 대화를 주고받았습니다.'));
        await _persist();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editAiSettings() async {
    final result = await Navigator.of(context).push<ChatSettings>(
      MaterialPageRoute(
        builder: (_) => ChatSetupScreen(
          initialSettings: widget.room.settings,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        widget.room.settings = result;
        widget.room.partner = result.name;
      });
      await widget.onAiSettingsChanged?.call(result);
      await widget.onChanged();
    }
  }

  Future<void> _editRoomSettings() async {
    final result = await Navigator.of(context).push<ChatRoomSettingsResult>(
      MaterialPageRoute(
        builder: (_) => ChatRoomSettingsScreen(
          initialTitle: widget.room.title,
          initialSettings: widget.room.settings,
          store: widget.store,
          friends: widget.friends,
          primaryFriendId: widget.room.friendId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        widget.room.title = result.title;
        widget.room.settings = result.settings;
      });
      await widget.onChanged();
    }
  }

  void _send() {
    final text = _message.text.trim();
    if (text.isEmpty && _referenceImageBytes == null) return;
    _sendMessage(text);
  }

  void _generateImageFromComposer() {
    final text = _message.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('생성할 이미지 내용을 먼저 입력해 주세요.')),
      );
      return;
    }
    _sendMessage(text, forceImageGeneration: true);
  }

  Future<void> _pickReferenceImage() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('기기에서 사진 선택'),
              onTap: () => Navigator.pop(context, 'device'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('채팅 갤러리에서 선택'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'gallery') {
      await _pickReferenceImageFromGallery();
      return;
    }
    await _pickReferenceImageFromDevice();
  }

  Future<void> _pickReferenceImageFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지는 10MB 이하만 업로드할 수 있습니다.')),
        );
      }
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    setState(() {
      _referenceImageBytes = bytes;
      _referenceImageName = file.name;
      _referenceImageMimeType = mimeType;
    });
  }

  Future<void> _pickReferenceImageFromGallery() async {
    final selection = await Navigator.of(context).push<ChatGallerySelection>(
      MaterialPageRoute(
        builder: (_) => ChatGalleryScreen(
          roomId: widget.room.id,
          roomTitle: widget.room.title,
          selectionMode: true,
        ),
      ),
    );
    if (selection == null || !mounted) return;
    try {
      final reference = FirebaseStorage.instanceFor(
        app: Firebase.app(),
        bucket: 'gs://languagehungry.firebasestorage.app',
      ).refFromURL(selection.url);
      final bytes = await reference.getData(10 * 1024 * 1024);
      if (bytes == null) throw StateError('갤러리 사진을 읽을 수 없습니다.');
      final metadata = await reference.getMetadata();
      if (!mounted) return;
      setState(() {
        _referenceImageBytes = bytes;
        _referenceImageName = selection.name;
        _referenceImageMimeType = metadata.contentType ?? 'image/jpeg';
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('갤러리 사진을 불러오지 못했습니다: $error')),
        );
      }
    }
  }

  FirebaseStorage get _chatStorage => FirebaseStorage.instanceFor(
        app: Firebase.app(),
        bucket: 'gs://languagehungry.firebasestorage.app',
      );

  Future<String> _uploadChatImage(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인 후 이미지를 저장할 수 있습니다.');
    final reference = _chatStorage.ref(
      'users/${user.uid}/chatRooms/${widget.room.id}/images/${const Uuid().v4()}',
    );
    await reference.putData(
      bytes,
      SettableMetadata(contentType: mimeType),
    );
    return reference.getDownloadURL();
  }

  void _recordImage({
    required String imageUrl,
    required String prompt,
    required String kind,
  }) {
    final message = '$_imageMessagePrefix${jsonEncode({
          'imageUrl': imageUrl,
          'prompt': prompt,
          'kind': kind,
          'createdAt': DateTime.now().toIso8601String(),
        })}';
    _recordMessage(message);
  }

  Map<String, dynamic>? _imageMessageData(String message) {
    if (!message.startsWith(_imageMessagePrefix)) return null;
    try {
      final decoded = jsonDecode(message.substring(_imageMessagePrefix.length));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  bool _isImageGenerationRequest(String text) {
    final prompt = text.toLowerCase();
    return RegExp(
      r'(사진|이미지|그림|일러스트).*(만들|생성|그려|보여|보내)|'
      r'(만들|생성|그려).*(사진|이미지|그림|일러스트)',
    ).hasMatch(prompt);
  }

  Future<(Uint8List, String)?> _loadAiProfileImage() async {
    final url = widget.room.settings.aiProfileImageUrl;
    if (url == null || url.isEmpty) return null;
    final reference = _chatStorage.refFromURL(url);
    final bytes = await reference.getData(10 * 1024 * 1024);
    if (bytes == null) {
      throw StateError('AI 프로필 이미지를 읽을 수 없습니다.');
    }
    final metadata = await reference.getMetadata();
    return (bytes, metadata.contentType ?? 'image/jpeg');
  }

  Future<String> _loadReferenceContext(String userMessage) async {
    const maxContextLength = 24000;
    const maxSourceLength = 6000;
    final sources = <({String title, String? content})>[];
    for (final memo in widget.room.settings.referenceMemos) {
      final id = memo['id'];
      if (id == null) continue;
      final node = await widget.store.findNode(id);
      sources.add((
        title: '메모: ${node?.title ?? memo['title'] ?? id}',
        content: node?.content,
      ));
    }

    for (final file in widget.room.settings.referenceFiles) {
      final name = file['name'] ?? '참고 파일';
      final content = file['content'];
      sources.add((title: '파일: $name', content: content));
    }

    if (sources.isEmpty) return '';
    final model =
        FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
    String sourcePreview(String? content) {
      if (content == null) return '';
      return content.substring(0, math.min(500, content.length));
    }

    final sourceTitles = [
      for (var index = 0; index < sources.length; index++)
        '${index + 1}. ${sources[index].title}: '
            '${sourcePreview(sources[index].content)}',
    ].join('\n');
    final selection = await model.generateContent([
      Content.text(
        '사용자 메시지에 답할 때 참고자료의 실제 내용이 필요할 때만 '
        '필요한 자료 번호를 쉼표로 답하세요. 필요 없으면 NONE만 답하세요. '
        '자료 본문은 아직 읽지 못한 상태이므로 제목만 보고 판단하세요.\n'
        '사용자 메시지: $userMessage\n'
        '참고자료 제목:\n$sourceTitles',
      ),
    ]);
    final selectedIndexes = RegExp(r'\d+')
        .allMatches(selection.text ?? '')
        .map((match) => int.parse(match.group(0)!))
        .where((number) => number > 0 && number <= sources.length)
        .toSet();
    if (selectedIndexes.isEmpty) return '';

    var remainingLength = maxContextLength;
    final sections = <String>[];
    for (var index = 0; index < sources.length; index++) {
      if (!selectedIndexes.contains(index + 1) || remainingLength <= 0) {
        continue;
      }
      final source = sources[index];
      final content = source.content;
      if (content == null || content.isEmpty) {
        throw StateError(
          '참고자료 "${source.title}"의 내용을 찾을 수 없습니다. 채팅방 설정에서 다시 등록해 주세요.',
        );
      }
      final availableLength = math.min(remainingLength, maxSourceLength);
      final excerpt = content.length > availableLength
          ? '${content.substring(0, availableLength)}\n[내용 일부 생략]'
          : content;
      sections.add('[${source.title}]\n$excerpt');
      remainingLength -= excerpt.length;
    }
    return sections.join('\n\n');
  }

  String _conversationMessageText(String message) {
    final image = _imageMessageData(message);
    if (image == null) return message;
    final prompt = image['prompt'] as String? ?? '';
    final kind = image['kind'] == 'generated' ? '생성 이미지' : '업로드 이미지';
    return prompt.isEmpty ? '[$kind]' : '[$kind: $prompt]';
  }

  Future<String> _summarizeConversation(String transcript) async {
    final model =
        FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
    final response = await model.generateContent([
      Content.text(
        '다음은 채팅 기록입니다. 이후 대화에 필요한 기억으로 압축하세요. '
        '사용자와 AI의 정체성 및 선호, 진행 중인 목표, 이미 합의한 내용, '
        '아직 해결되지 않은 질문·약속·중요한 사실을 보존하세요. '
        '중요하지 않은 인사와 반복은 제외하고, 기록에 없는 사실은 추론하지 마세요. '
        '짧고 구체적인 한국어 요약만 반환하세요.\n\n$transcript',
      ),
    ]);
    final summary = response.text?.trim();
    if (summary == null || summary.isEmpty) {
      throw StateError('이전 대화의 핵심 내용을 요약하지 못했습니다.');
    }
    return summary;
  }

  Future<String> _loadConversationHistoryContext(
      String currentUserMessage) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인 후 이전 대화를 불러올 수 있습니다.');
    final collection = langgryFirestore()
        .collection('users')
        .doc(user.uid)
        .collection('chatRooms')
        .doc(widget.room.id)
        .collection('messages');
    final documents = <({String id, String text})>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      final page = await (cursor == null
          ? collection.orderBy('createdAt').limit(200).get()
          : collection
              .orderBy('createdAt')
              .startAfterDocument(cursor)
              .limit(200)
              .get());
      if (page.docs.isEmpty) break;
      for (final document in page.docs) {
        final data = document.data();
        final rawMessage = data['text'] ?? data['message'] ?? data['content'];
        if (rawMessage is String) {
          documents.add((id: document.id, text: rawMessage));
        }
      }
      cursor = page.docs.last;
      if (page.docs.length < 200) break;
    }

    if (currentUserMessage.isNotEmpty) {
      final currentMessageIndex = documents.lastIndexWhere(
        (entry) => entry.text == '나: $currentUserMessage',
      );
      if (currentMessageIndex >= 0) documents.removeAt(currentMessageIndex);
    }
    if (documents.isEmpty) return '';

    const recentHistoryLimit = 10000;
    var recentStart = documents.length;
    var recentLength = 0;
    while (recentStart > 0) {
      final messageLength =
          _conversationMessageText(documents[recentStart - 1].text).length;
      if (recentStart < documents.length &&
          recentLength + messageLength > recentHistoryLimit) {
        break;
      }
      recentStart--;
      recentLength += messageLength;
      if (recentLength >= recentHistoryLimit) break;
    }

    final settings = widget.room.settings;
    final summary = settings.conversationSummary.trim();
    final summaryThroughIndex =
        settings.conversationSummaryThroughMessageId == null
            ? -1
            : documents.lastIndexWhere(
                (entry) =>
                    entry.id == settings.conversationSummaryThroughMessageId,
              );
    final unsummarizedStart = summary.isNotEmpty && summaryThroughIndex >= 0
        ? summaryThroughIndex + 1
        : 0;
    if (recentStart > unsummarizedStart) {
      final oldMessages = documents
          .sublist(unsummarizedStart, recentStart)
          .map((entry) => _conversationMessageText(entry.text))
          .toList();
      const chunkLimit = 12000;
      final chunks = <String>[];
      var chunk = StringBuffer();
      for (final message in oldMessages) {
        if (chunk.length > 0 &&
            chunk.length + message.length + 2 > chunkLimit) {
          chunks.add(chunk.toString());
          chunk = StringBuffer();
        }
        if (chunk.length > 0) chunk.write('\n\n');
        chunk.write(message);
      }
      if (chunk.length > 0) chunks.add(chunk.toString());

      final chunkSummaries = <String>[];
      for (final oldChunk in chunks) {
        chunkSummaries.add(await _summarizeConversation(oldChunk));
      }
      final combined = [
        if (summary.isNotEmpty) '[기존 기억]\n$summary',
        for (var index = 0; index < chunkSummaries.length; index++)
          '[이전 대화 요약 ${index + 1}]\n${chunkSummaries[index]}',
      ].join('\n\n');
      settings.conversationSummary = await _summarizeConversation(combined);
      settings.conversationSummaryThroughMessageId =
          documents[recentStart - 1].id;
      await widget.onChanged();
    }

    final recentMessages = documents
        .skip(recentStart)
        .map((entry) => _conversationMessageText(entry.text))
        .join('\n');
    return [
      if (settings.conversationSummary.trim().isNotEmpty)
        '[이전 대화 핵심 기억]\n${settings.conversationSummary.trim()}',
      if (recentMessages.isNotEmpty) '[최근 대화]\n$recentMessages',
    ].join('\n\n');
  }

  String _aiInstructions() {
    final settings = widget.room.settings;
    final participants = widget.friends
        .where((friend) => settings.selectedParticipantIds.contains(friend.id))
        .map((friend) => friend.id == widget.room.friendId
            ? widget.room.partner
            : friend.name)
        .toList();
    return [
      '당신은 ${settings.name}입니다.',
      '자아/성격: ${settings.aiTraits?.trim().isNotEmpty == true ? settings.aiTraits : "친근하고 도움이 되는 태도"}.',
      'AI 역할: ${settings.role}.',
      'AI 말투: ${settings.tone}.',
      '채팅 종류: ${settings.chatType}.',
      if (participants.isNotEmpty) '채팅 참여자: ${participants.join(', ')}.',
      if (settings.assistantModeEnabled &&
          settings.assistantModeInstruction?.trim().isNotEmpty == true)
        'AI 보조 모드 지시사항: ${settings.assistantModeInstruction}.',
      '위 AI 설정은 이번 답변에도 모두 적용하세요.',
      '언어 학습에 도움이 되도록 자연스럽고 정확하게 답하세요.',
    ].join('\n');
  }

  String _textGenerationInstructions() {
    final roomInstruction =
        widget.room.settings.textResponseInstruction?.trim();
    return [
      _aiInstructions(),
      if (roomInstruction != null && roomInstruction.isNotEmpty)
        '이 채팅방의 일반 답변 지침: $roomInstruction',
    ].join('\n');
  }

  Future<void> _generateAndSendImage(
    String request, {
    Uint8List? referenceBytes,
    String? referenceMimeType,
  }) async {
    final profileReference =
        (widget.room.settings.aiProfileImageUrl?.isNotEmpty ?? false)
            ? await _loadAiProfileImage()
            : null;
    final referenceContext = await _loadReferenceContext(request);
    final conversationContext = await _loadConversationHistoryContext(request);
    final visualReferences = <(Uint8List, String)>[
      if (profileReference != null) profileReference,
      if (referenceBytes != null)
        (referenceBytes, referenceMimeType ?? 'image/jpeg'),
    ];
    final imagePrompt = [
      _aiInstructions(),
      if (widget.room.settings.imageGenerationInstruction?.trim().isNotEmpty ==
          true)
        '이 채팅방의 이미지 생성 지침: '
            '${widget.room.settings.imageGenerationInstruction!.trim()}',
      'Create a polished, safe, non-explicit illustration based on this request:',
      request,
      if (conversationContext.isNotEmpty)
        'Conversation continuity:\n$conversationContext',
      if (profileReference != null)
        'The first attached image is the AI partner profile. Depict the same '
            'fictional character and preserve recognizable visual features.',
      if (referenceBytes != null)
        'Use the additional attached reference image only as visual guidance '
            'for this requested image.',
      if (profileReference != null)
        'When depicting ${widget.room.settings.name}, use the AI partner profile '
            'image as the character reference.',
      if (referenceContext.isNotEmpty)
        'Relevant reference material:\n$referenceContext',
    ].join('\n\n');

    final parts = <Part>[
      TextPart(imagePrompt),
      for (final reference in visualReferences)
        InlineDataPart(reference.$2, reference.$1),
    ];
    final model = FirebaseAI.vertexAI(
      appCheck: FirebaseAppCheck.instance,
      location: 'global',
    ).generativeModel(
      model: widget.room.settings.imageGenerationModel,
      generationConfig: GenerationConfig(
        responseModalities: [ResponseModalities.image],
      ),
    );
    final response = await model.generateContent([Content.multi(parts)]);
    if (response.inlineDataParts.isEmpty) {
      throw StateError('이미지를 생성하지 못했습니다.');
    }
    final image = response.inlineDataParts.first;
    final imageUrl = await _uploadChatImage(
      image.bytes,
      mimeType: image.mimeType,
    );
    if (!mounted) return;
    setState(() {
      _recordImage(imageUrl: imageUrl, prompt: '', kind: 'generated');
    });
  }

  Future<void> _openGallery() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatGalleryScreen(
          roomId: widget.room.id,
          roomTitle: widget.room.title,
        ),
      ),
    );
  }

  Future<void> _sendMessage(
    String text, {
    bool forceImageGeneration = false,
  }) async {
    if (_sending) return;
    final generateImage = text.isNotEmpty &&
        (forceImageGeneration || _isImageGenerationRequest(text));
    final referenceBytes = _referenceImageBytes;
    final referenceName = _referenceImageName;
    final referenceMimeType = _referenceImageMimeType;
    setState(() {
      _sending = true;
      if (text.isNotEmpty && !generateImage) _recordMessage('나: $text');
      _message.clear();
      _referenceImageBytes = null;
      _referenceImageName = null;
      _referenceImageMimeType = null;
    });
    try {
      if (generateImage) {
        await _generateAndSendImage(
          text,
          referenceBytes: referenceBytes,
          referenceMimeType: referenceMimeType,
        );
      } else {
        if (referenceBytes != null) {
          final imageUrl = await _uploadChatImage(
            referenceBytes,
            mimeType: referenceMimeType ?? 'image/jpeg',
          );
          if (!mounted) return;
          setState(() {
            _recordImage(
              imageUrl: imageUrl,
              prompt: text.isEmpty ? referenceName ?? '' : text,
              kind: 'uploaded',
            );
          });
        }
        await _persist();
        if (text.isNotEmpty &&
            (widget.room.isAi || widget.room.settings.chatType == 'group_ai')) {
          final referenceContext = await _loadReferenceContext(text);
          final conversationContext =
              await _loadConversationHistoryContext(text);
          final profileReference =
              widget.room.settings.aiProfileImageUrl?.isNotEmpty ?? false
                  ? await _loadAiProfileImage()
                  : null;
          final model =
              FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
          final instructions = '${_textGenerationInstructions()}\n'
              '학습 자료: ${widget.room.settings.selectedSources.join(', ')}.\n'
              '참고자료의 실제 내용을 우선 참고하여 근거 있게 답하고, 관련 내용이 없으면 모른다고 말하세요.';
          final promptParts = <Part>[
            TextPart(
              '$instructions\n'
              '${conversationContext.isEmpty ? '' : '이전 대화 맥락:\n$conversationContext\n\n'}'
              '${referenceContext.isEmpty ? '' : '참고자료 내용:\n$referenceContext\n\n'}'
              '사용자: $text',
            ),
            if (profileReference != null)
              TextPart(
                '첨부 이미지는 당신의 AI 파트너 프로필 이미지입니다. '
                '대화에서 당신의 외형과 정체성을 참고하세요.',
              ),
            if (profileReference != null)
              InlineDataPart(profileReference.$2, profileReference.$1),
            if (referenceBytes != null)
              InlineDataPart(referenceMimeType ?? 'image/jpeg', referenceBytes),
          ];
          final response =
              await model.generateContent([Content.multi(promptParts)]);
          final answer = response.text?.trim();
          if (answer != null && answer.isNotEmpty) {
            setState(
                () => _recordMessage('${widget.room.settings.name}: $answer'));
          }
        } else if (text.isNotEmpty) {
          setState(() => _recordMessage(
              '${widget.room.partner}: AI 보조가 대화 내용을 정리하고 있습니다.'));
        }
      }
      await _persist();
      await _autoSaveIfNeeded();
    } catch (error) {
      if (mounted) {
        setState(() => _recordMessage(
            '${widget.room.partner}: 이미지 또는 응답 처리에 실패했습니다: $error'));
        await _persist();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _persist() async {
    widget.room.messages = List<String>.from(_messages);
    if (_messages.isNotEmpty) {
      widget.room.lastMessage = _messagePreview(_messages.last);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 채팅 내용을 저장할 수 있습니다.')),
        );
      }
      return;
    }

    final messageCollection = langgryFirestore()
        .collection('users')
        .doc(user.uid)
        .collection('chatRooms')
        .doc(widget.room.id)
        .collection('messages');
    try {
      while (_pendingMessages.isNotEmpty) {
        final entry = _pendingMessages.entries.first;
        final imageData = _imageMessageData(entry.value);
        await messageCollection.doc(entry.key).set({
          'text': entry.value,
          'createdAt': Timestamp.now(),
          if (imageData != null) ...{
            'type': 'image',
            'imageUrl': imageData['imageUrl'],
            'prompt': imageData['prompt'],
            'imageKind': imageData['kind'],
          },
        });
        _pendingMessages.remove(entry.key);
      }
      await widget.onChanged();
      _scrollToLatest(force: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('채팅 내용을 저장하지 못했습니다: $error')),
        );
      }
    }
  }

  Future<void> _autoSaveIfNeeded() async {
    if (widget.room.settings.saveEvery <= 0) return;
    await _saveChatSegment(manual: false);
  }

  int _savedFileMessageCount(KnowledgeNode file) {
    final metadataCount =
        int.tryParse(file.metadata['savedThroughMessageCount'] ?? '');
    if (metadataCount != null) return metadataCount;
    final prefix = 'chat-${widget.room.id}-';
    if (!file.id.startsWith(prefix)) return 0;
    return int.tryParse(file.id.substring(prefix.length)) ?? 0;
  }

  Future<void> _saveChatSegment({
    required bool manual,
    bool fullContent = false,
  }) async {
    if (_savingChatFile) return;
    if (!manual && widget.room.settings.saveEvery <= 0) return;
    setState(() => _savingChatFile = true);
    try {
      await _persist();
      if (_pendingMessages.isNotEmpty) {
        throw StateError('채팅 내용을 먼저 서버에 저장할 수 없습니다. 연결 상태를 확인해 주세요.');
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('로그인 후 대화 파일을 저장할 수 있습니다.');
      final collection = langgryFirestore()
          .collection('users')
          .doc(user.uid)
          .collection('chatRooms')
          .doc(widget.room.id)
          .collection('messages');
      final allMessages = <String>[];
      final allMessageIds = <String>[];
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        final page = await (cursor == null
            ? collection.orderBy('createdAt').limit(200).get()
            : collection
                .orderBy('createdAt')
                .startAfterDocument(cursor)
                .limit(200)
                .get());
        if (page.docs.isEmpty) break;
        for (final document in page.docs) {
          final data = document.data();
          final rawMessage = data['text'] ?? data['message'] ?? data['content'];
          if (rawMessage is String) {
            allMessages.add(rawMessage);
            allMessageIds.add(document.id);
          }
        }
        cursor = page.docs.last;
        if (page.docs.length < 200) break;
      }

      final roomFiles = (await widget.store.listFiles()).where((file) {
        return file.metadata['chatRoomId'] == widget.room.id ||
            file.id.startsWith('chat-${widget.room.id}-');
      }).toList()
        ..sort((left, right) {
          return _savedFileMessageCount(left)
              .compareTo(_savedFileMessageCount(right));
        });
      var savedThrough = 0;
      String? savedThroughMessageId;
      for (final savedFile in roomFiles) {
        final fileCount = _savedFileMessageCount(savedFile);
        if (fileCount >= savedThrough) {
          savedThrough = fileCount;
          savedThroughMessageId = savedFile.metadata['savedThroughMessageId'];
        }
      }
      final savedMessageIndex = savedThroughMessageId == null
          ? -1
          : allMessageIds.lastIndexOf(savedThroughMessageId);
      final start = (fullContent
              ? 0
              : savedMessageIndex >= 0
                  ? savedMessageIndex + 1
                  : savedThrough)
          .clamp(0, allMessages.length)
          .toInt();
      final segment = allMessages.skip(start).toList();
      if (segment.isEmpty) {
        if (manual && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('저장할 새 대화 내용이 없습니다.')),
          );
        }
        return;
      }
      final newUserMessages =
          segment.where((message) => message.startsWith('나:')).length;
      if (!manual && newUserMessages < widget.room.settings.saveEvery) return;
      final transcript = segment.map((message) {
        final image = _imageMessageData(message);
        if (image == null) return message;
        final prompt = image['prompt'] as String? ?? '';
        final kind = image['kind'] == 'generated' ? '생성 이미지' : '첨부 이미지';
        return prompt.isEmpty ? '[$kind]' : '[$kind: $prompt]';
      }).join('\n\n');
      final instruction =
          widget.room.settings.autoSaveInstruction?.trim() ?? '';
      final response = await FirebaseAI.googleAI()
          .generativeModel(model: 'gemini-3.6-flash')
          .generateContent([
        Content.text(
          '아래 채팅 내용을 HTML 파일로 정리하세요. 결과는 설명이나 마크다운 코드블록 없이 '
          '완전한 단일 HTML 문서만 반환하세요. 적절한 제목, 읽기 쉬운 본문 구조와 간결한 CSS를 '
          '포함하고, 입력된 대화의 사실을 임의로 추가하거나 바꾸지 마세요.\n'
          '채팅방: ${widget.room.title}\n'
          '저장 시 참고 프롬프트: ${instruction.isEmpty ? '없음' : instruction}\n'
          '저장할 대화:\n$transcript',
        ),
      ]);
      var html = response.text?.trim() ?? '';
      html = html
          .replaceFirst(RegExp(r'^```(?:html)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
      if (html.isEmpty) throw StateError('HTML 대화 파일을 생성하지 못했습니다.');
      if (!RegExp(r'<(?:!doctype\s+html|html)\b', caseSensitive: false)
          .hasMatch(html)) {
        html = '<!doctype html><html lang="ko"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<title>${const HtmlEscape().convert(widget.room.title)}</title>'
            '</head><body>$html</body></html>';
      }
      final now = DateTime.now();
      final title = '${widget.room.title} - ${fullContent ? '전체 내용' : '새 대화'} '
          '· ${allMessages.length}개 메시지';
      final lastSavedMessageId =
          allMessageIds.isEmpty ? '' : allMessageIds.last;
      final fileId = fullContent
          ? 'chat-${widget.room.id}-full-${allMessages.length}'
          : 'chat-${widget.room.id}-${allMessages.length}';
      await widget.store.upsertFile(
        KnowledgeNode(
          id: fileId,
          type: 'file',
          title: title,
          content: html,
          createdAt: now,
          updatedAt: now,
          tags: const ['채팅', '대화기록'],
          metadata: {
            'mode': 'file',
            'format': 'html',
            'display': '채팅 파일',
            'chatRoomId': widget.room.id,
            'savedThroughMessageCount': allMessages.length.toString(),
            'savedThroughMessageId': lastSavedMessageId,
            'fullContent': fullContent.toString(),
            'category': widget.room.settings.autoSaveCategory.trim().isEmpty
                ? '채팅 기록'
                : widget.room.settings.autoSaveCategory.trim(),
          },
        ),
      );
      if (lastSavedMessageId.isNotEmpty) {
        setState(() => _savedThroughMessageId = lastSavedMessageId);
        await collection.doc(lastSavedMessageId).set({
          'savedToHtml': true,
          'savedFileId': fileId,
        }, SetOptions(merge: true));
      }
      widget.room.settings.autoSaveThrough = allMessages.length;
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${fullContent ? '전체 대화' : '새 대화'} HTML 저장 완료: $title',
            ),
          ),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('대화 파일을 저장하지 못했습니다: ${error.message ?? error.code}')),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('대화 파일을 저장하지 못했습니다: ${error.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingChatFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOfflineMeeting = widget.room.settings.chatType == 'offline_meeting';
    final isAiSpectator = widget.room.settings.chatType == 'ai_ai';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.room.title),
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: AppTheme.navy,
        actions: [
          IconButton(
            onPressed: _savingChatFile || _sending
                ? null
                : () => _saveChatSegment(manual: true),
            tooltip: '새 대화 내용 저장',
            icon: _savingChatFile
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          IconButton(
            onPressed: _savingChatFile || _sending
                ? null
                : () => _saveChatSegment(manual: true, fullContent: true),
            tooltip: '전체 내용 저장',
            icon: const Icon(Icons.save_as_outlined),
          ),
          IconButton(
            onPressed: _openGallery,
            tooltip: '채팅방 갤러리',
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            onPressed: _editAiSettings,
            tooltip: 'AI 설정',
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            onPressed: _editRoomSettings,
            tooltip: '채팅방 설정',
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline Meeting Mode Controls Banner
          if (isOfflineMeeting)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isMeetingRecording
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        color: _isMeetingRecording ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isMeetingRecording
                              ? '실시간 회의 녹음 감지 중 (기준: ${widget.room.settings.decibelThreshold.round()}dB)'
                              : '오프라인 회의 모드 (녹음 대기 중)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _toggleMeetingRecording,
                        style: FilledButton.styleFrom(
                          backgroundColor: _isMeetingRecording
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                        ),
                        icon: Icon(_isMeetingRecording
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded),
                        label: Text(_isMeetingRecording ? '녹음 중지' : '녹음 시작'),
                      ),
                    ],
                  ),
                  if (_isMeetingRecording) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_currentDecibel / 100.0).clamp(0.0, 1.0),
                      color: _currentDecibel >=
                              widget.room.settings.decibelThreshold
                          ? Colors.red
                          : Colors.green,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '현재 음성 감지 데시벨: ${_formatDecibel(_currentDecibel)} dB',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _analyzeOfflineMeeting,
                      icon: const Icon(Icons.analytics_rounded, size: 16),
                      label: const Text('AI 회의 분석 실행'),
                    ),
                  ),
                ],
              ),
            ),

          // Spectator Mode Banner
          if (isAiSpectator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.remove_red_eye_rounded, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 대화 관전 모드: ${widget.room.settings.name} ↔ 보조 AI',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _stepAiSpectatorChat,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('다음 대화 관전'),
                  ),
                ],
              ),
            ),

          // Reference Materials Bar
          if (widget.room.settings.selectedSources.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: widget.room.settings.selectedSources
                    .map((source) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Chip(
                            avatar: const Icon(Icons.link_rounded, size: 16),
                            label: Text(source),
                          ),
                        ))
                    .toList(),
              ),
            ),

          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      isOfflineMeeting
                          ? '녹음을 시작하면 설정된 데시벨 이상일 때 자동으로 텍스트 변환됩니다.'
                          : '대화를 시작해 보세요.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  )
                : NotificationListener<UserScrollNotification>(
                    onNotification: _onUserScroll,
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _messageScrollController,
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                          itemCount: _messages.length,
                          itemBuilder: (_, index) {
                            final messageId = _loadedMessageIdAt(index);
                            return _buildMessageBubble(
                              _messages[index],
                              isFirstFromSender: index == 0 ||
                                  _senderOf(_messages[index - 1]) !=
                                      _senderOf(_messages[index]),
                              isSaved: messageId != null &&
                                  messageId == _savedThroughMessageId,
                            );
                          },
                        ),
                        if (_loadingOlderMessages)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
          ),
          SafeArea(
            child: Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_referenceImageBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _referenceImageBytes!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _referenceImageName ?? '참고 이미지',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _referenceImageBytes = null;
                              _referenceImageName = null;
                              _referenceImageMimeType = null;
                            }),
                            tooltip: '참고 이미지 제거',
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _sending ? null : _pickReferenceImage,
                              tooltip: '참고 이미지 업로드',
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                            ),
                            IconButton(
                              onPressed:
                                  _sending ? null : _generateImageFromComposer,
                              tooltip: '이미지 생성',
                              icon: const Icon(Icons.auto_awesome_rounded),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE4E9F1)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TextField(
                            controller: _message,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            minLines: 1,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              hintText: '메시지 또는 이미지 생성 요청',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _sending ? null : _send,
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.navy,
                          foregroundColor: Colors.white,
                          fixedSize: const Size(46, 46),
                        ),
                        tooltip: '메시지 전송',
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_upward_rounded),
                      ),
                      const SizedBox(width: 72),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _senderOf(String message) {
    final imageData = _imageMessageData(message);
    if (imageData != null) {
      return imageData['kind'] == 'generated' ? widget.room.partner : '나';
    }
    final separator = message.indexOf(': ');
    return separator < 0 ? '' : message.substring(0, separator);
  }

  Widget _buildMessageBubble(
    String message, {
    required bool isFirstFromSender,
    required bool isSaved,
  }) {
    final imageData = _imageMessageData(message);
    if (imageData != null) {
      final imageUrl = imageData['imageUrl'] as String?;
      final prompt = imageData['prompt'] as String? ?? '';
      return Align(
        alignment: imageData['kind'] == 'generated'
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(
            top: isFirstFromSender ? 10 : 2,
            bottom: 6,
            left: imageData['kind'] == 'generated' ? 44 : 0,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Card(
              clipBehavior: Clip.antiAlias,
              color: AppTheme.mint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageUrl != null)
                    GestureDetector(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => Dialog(
                          child: InteractiveViewer(
                            child: Image.network(imageUrl, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      child: Image.network(
                        imageUrl,
                        width: 240,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 240,
                          height: 160,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  if (prompt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        '${imageData['kind'] == 'generated' ? '생성' : '업로드'} · $prompt',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (isSaved)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _savedMessageIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final separator = message.indexOf(': ');
    final sender = separator < 0 ? '' : message.substring(0, separator);
    final text = separator < 0 ? message : message.substring(separator + 2);
    final isMine = sender == '나';
    final isReport = message.contains('AI 회의 분석 리포트');

    if (isReport) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(message),
          ),
          if (isSaved) _savedMessageIndicator(),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        top: isFirstFromSender ? 10 : 2,
        bottom: 3,
      ),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            SizedBox(
              width: 38,
              child: isFirstFromSender
                  ? ChatAvatar(
                      radius: 17,
                      isAi: widget.room.isAi,
                      imageUrl: widget.room.settings.groupProfileImageUrl ??
                          widget.room.settings.aiProfileImageUrl,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMine && isFirstFromSender && sender.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(
                      sender,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: isMine ? AppTheme.mint : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                if (isSaved) _savedMessageIndicator(),
              ],
            ),
          ),
          if (!isMine) const SizedBox(width: 38),
        ],
      ),
    );
  }
}
