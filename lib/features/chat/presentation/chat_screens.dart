import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ai/firebase_ai.dart';

import '../../knowledge/data/knowledge_store.dart';
import '../../knowledge/domain/entities/knowledge_node.dart';

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.title,
    required this.partner,
    required this.isAi,
    required this.settings,
  });

  final String id;
  final String title;
  final String partner;
  final bool isAi;
  ChatSettings settings;
  List<String> messages = <String>[];
}

class ChatSettings {
  ChatSettings({
    required this.name,
    required this.partnerType,
    required this.role,
    required this.tone,
    required this.saveEvery,
    required this.selectedSources,
  });

  String name;
  String partnerType;
  String role;
  String tone;
  int saveEvery;
  List<String> selectedSources;

  Map<String, dynamic> toMap() => {
        'name': name,
        'partnerType': partnerType,
        'role': role,
        'tone': tone,
        'saveEvery': saveEvery,
        'selectedSources': selectedSources,
      };

  factory ChatSettings.fromMap(Map<String, dynamic> map) => ChatSettings(
        name: map['name'] as String? ?? 'AI 보조',
        partnerType: map['partnerType'] as String? ?? 'AI',
        role: map['role'] as String? ?? '언어 학습 보조',
        tone: map['tone'] as String? ?? '친근하게',
        saveEvery: (map['saveEvery'] as num?)?.toInt() ?? 10,
        selectedSources:
            (map['selectedSources'] as List?)?.whereType<String>().toList() ??
                <String>[],
      );
}

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
  final _firestore = FirebaseFirestore.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _rooms.isEmpty) _createChat();
      });
    }
  }

  Future<void> _loadRooms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chatRooms')
          .orderBy('updatedAt', descending: true)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final settings = data['settings'] is Map
            ? Map<String, dynamic>.from(data['settings'] as Map)
            : <String, dynamic>{};
        final room = ChatRoom(
          id: doc.id,
          title: data['title'] as String? ?? '채팅방',
          partner: data['partner'] as String? ?? 'AI 보조',
          isAi: data['isAi'] as bool? ?? true,
          settings: ChatSettings.fromMap(settings),
        );
        room.messages =
            (data['messages'] as List?)?.whereType<String>().toList() ??
                <String>[];
        _rooms.add(room);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createChat() async {
    final settings = await Navigator.of(context).push<ChatSettings>(
      MaterialPageRoute(builder: (_) => const ChatSetupScreen()),
    );
    if (settings == null || !mounted) return;
    final room = ChatRoom(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: '${settings.name}와의 새 대화',
      partner: settings.name,
      isAi: settings.partnerType == 'AI',
      settings: settings,
    );
    setState(() => _rooms.add(room));
    await _saveRoom(room);
    _openRoom(room);
  }

  Future<void> _saveRoom(ChatRoom room) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('chatRooms')
        .doc(room.id)
        .set({
      'title': room.title,
      'partner': room.partner,
      'isAi': room.isAi,
      'settings': room.settings.toMap(),
      'messages': room.messages,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          room: room,
          store: widget.store,
          onChanged: () => _saveRoom(room),
        ),
      ),
    );
    if (mounted) setState(() {});
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
                _FriendsTab(onStartChat: _createChat),
                _RoomsTab(
                    rooms: _rooms, onOpen: _openRoom, onCreate: _createChat),
              ],
            ),
    );
  }
}

class _FriendsTab extends StatelessWidget {
  const _FriendsTab({required this.onStartChat});

  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final friends = [
      ('나', '내 학습 보조', Icons.person_rounded, Colors.indigo),
      ('Emma', 'AI 영어 회화 코치', Icons.smart_toy_rounded, Colors.teal),
      ('일본어 선생님', 'AI 학습 대상자', Icons.auto_awesome_rounded, Colors.orange),
      ('친구 추가', '타유저를 등록하세요', Icons.person_add_alt_rounded, Colors.grey),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xffeff2ff),
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('새로운 대화 시작'),
            subtitle: const Text('상대와 AI 보조 설정을 먼저 구성합니다.'),
            trailing: FilledButton(
              onPressed: onStartChat,
              child: const Text('시작'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...friends.map(
          (friend) => Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: friend.$4.withValues(alpha: .14),
                foregroundColor: friend.$4,
                child: Icon(friend.$3),
              ),
              title: Text(friend.$1),
              subtitle: Text(friend.$2),
              trailing: friend.$1 == '친구 추가'
                  ? IconButton(
                      onPressed: () => _message(context, '친구 추가 기능을 준비하고 있어요.'),
                      icon: const Icon(Icons.add_rounded),
                    )
                  : IconButton(
                      onPressed: onStartChat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab({
    required this.rooms,
    required this.onOpen,
    required this.onCreate,
  });

  final List<ChatRoom> rooms;
  final ValueChanged<ChatRoom> onOpen;
  final VoidCallback onCreate;

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
            leading: CircleAvatar(
              child: Icon(room.isAi ? Icons.smart_toy_rounded : Icons.person),
            ),
            title: Text(room.title),
            subtitle: Text('${room.partner} · ${room.settings.tone}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpen(room),
          ),
        );
      },
    );
  }
}

class ChatSetupScreen extends StatefulWidget {
  const ChatSetupScreen({this.initialSettings, super.key});

  final ChatSettings? initialSettings;

  @override
  State<ChatSetupScreen> createState() => _ChatSetupScreenState();
}

class _ChatSetupScreenState extends State<ChatSetupScreen> {
  final _name = TextEditingController(text: 'Emma');
  final _role = TextEditingController(text: '친절한 언어 학습 보조');
  String _partnerType = 'AI';
  String _tone = '친근하게';
  int _saveEvery = 10;
  final _sources = <String>{};

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    if (settings != null) {
      _name.text = settings.name;
      _partnerType = settings.partnerType;
      _role.text = settings.role;
      _tone = settings.tone;
      _saveEvery = settings.saveEvery;
      _sources.addAll(settings.selectedSources);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('AI 이름', TextField(controller: _name)),
          _section(
            '대화 상대',
            DropdownButtonFormField<String>(
              initialValue: _partnerType,
              items: const ['AI', '타유저', '나']
                  .map((type) =>
                      DropdownMenuItem(value: type, child: Text(type)))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _partnerType = value ?? _partnerType),
            ),
          ),
          _section('AI 역할', TextField(controller: _role, maxLines: 2)),
          _section(
            'AI 말투',
            DropdownButtonFormField<String>(
              initialValue: _tone,
              items: const ['친근하게', '차분하게', '선생님처럼', '간결하게']
                  .map((tone) =>
                      DropdownMenuItem(value: tone, child: Text(tone)))
                  .toList(),
              onChanged: (value) => setState(() => _tone = value ?? _tone),
            ),
          ),
          _section(
            '대화 저장 주기',
            DropdownButtonFormField<int>(
              initialValue: _saveEvery,
              items: const [5, 10, 20, 50]
                  .map((itemCount) => DropdownMenuItem(
                      value: itemCount, child: Text('$itemCount번째 대화마다')))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _saveEvery = value ?? _saveEvery),
            ),
          ),
          _section(
            '채팅에 사용할 자료',
            Column(
              children: [
                _source('리스트', Icons.table_chart_outlined),
                _source('플롯', Icons.account_tree_outlined),
                _source('메모', Icons.note_alt_outlined),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              ChatSettings(
                name: _name.text.trim().isEmpty ? 'AI 보조' : _name.text.trim(),
                partnerType: _partnerType,
                role: _role.text.trim(),
                tone: _tone,
                saveEvery: _saveEvery,
                selectedSources: _sources.toList(),
              ),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('설정 완료하고 채팅 시작'),
          ),
        ],
      ),
    );
  }

  Widget _source(String label, IconData icon) {
    return CheckboxListTile(
      value: _sources.contains(label),
      onChanged: (checked) => setState(() {
        if (checked == true) {
          _sources.add(label);
        } else {
          _sources.remove(label);
        }
      }),
      secondary: Icon(icon),
      title: Text(label),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    required this.room,
    required this.store,
    required this.onChanged,
    super.key,
  });

  final ChatRoom room;
  final KnowledgeStore store;
  final Future<void> Function() onChanged;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _message = TextEditingController();
  final _messages = <String>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.room.messages);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _editSettings() async {
    final result = await Navigator.of(context).push<ChatSettings>(
      MaterialPageRoute(
        builder: (_) => ChatSetupScreen(initialSettings: widget.room.settings),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.room.settings = result);
    }
  }

  void _send() {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    _sendMessage(text);
  }

  Future<void> _sendMessage(String text) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _messages.add('나: $text');
      _message.clear();
    });
    await _persist();
    if (widget.room.isAi) {
      try {
        final model =
            FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
        final response = await model.generateContent([
          Content.text(
            '당신은 ${widget.room.settings.name}입니다. '
            '역할: ${widget.room.settings.role}. '
            '말투: ${widget.room.settings.tone}. '
            '학습 자료: ${widget.room.settings.selectedSources.join(', ')}. '
            '대화에 자연스럽게 답하고 언어 학습에 도움이 되도록 하세요.\n'
            '사용자: $text',
          ),
        ]);
        final answer = response.text?.trim();
        if (answer != null && answer.isNotEmpty) {
          setState(() => _messages.add('${widget.room.partner}: $answer'));
        }
      } catch (error) {
        if (mounted) {
          setState(() => _messages.add(
              '${widget.room.partner}: AI 응답을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.'));
        }
      }
    } else {
      setState(() =>
          _messages.add('${widget.room.partner}: AI 보조가 대화 내용을 정리하고 있습니다.'));
    }
    await _persist();
    await _autoSaveIfNeeded();
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _persist() async {
    widget.room.messages = List<String>.from(_messages);
    await widget.onChanged();
  }

  Future<void> _autoSaveIfNeeded() async {
    final userMessages =
        _messages.where((message) => message.startsWith('나:')).length;
    if (userMessages == 0 ||
        userMessages % widget.room.settings.saveEvery != 0) {
      return;
    }
    final now = DateTime.now();
    await widget.store.upsertNode(
      KnowledgeNode(
        id: 'chat-${widget.room.id}-$userMessages',
        type: 'knowledge',
        title: '${widget.room.title} - $userMessages번째 대화',
        content: _messages.join('\n\n'),
        tags: const ['채팅', '대화기록'],
        createdAt: now,
        updatedAt: now,
        metadata: const {'mode': 'file', 'display': '채팅 파일'},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.title),
        actions: [
          IconButton(
            onPressed: _editSettings,
            tooltip: 'AI 설정',
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
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
                ? const Center(child: Text('대화를 시작해 보세요.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_messages[index]),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _message,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '메시지를 입력하세요',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
