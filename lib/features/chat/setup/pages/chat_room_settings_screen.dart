import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:langgry/features/chat/models/chat_settings.dart';
import 'package:langgry/features/chat/models/friend.dart';
import 'package:langgry/features/chat/services/chat_reference_file.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/services/knowledge_store.dart';

class ChatRoomSettingsResult {
  const ChatRoomSettingsResult({
    required this.title,
    required this.settings,
  });

  final String title;
  final ChatSettings settings;
}

class ChatRoomSettingsScreen extends StatefulWidget {
  const ChatRoomSettingsScreen({
    required this.initialTitle,
    required this.initialSettings,
    required this.store,
    required this.friends,
    this.primaryFriendId,
    super.key,
  });

  final String initialTitle;
  final ChatSettings initialSettings;
  final KnowledgeStore store;
  final List<Friend> friends;
  final String? primaryFriendId;

  @override
  State<ChatRoomSettingsScreen> createState() => _ChatRoomSettingsScreenState();
}

class _ChatRoomSettingsScreenState extends State<ChatRoomSettingsScreen> {
  late final TextEditingController _title;
  late final TextEditingController _assistantInstruction;
  late final TextEditingController _imageGenerationInstruction;
  late final TextEditingController _textResponseInstruction;
  late final TextEditingController _meetingInstruction;
  late final TextEditingController _groupProfileImage;
  late final TextEditingController _autoSaveCategory;
  late final TextEditingController _autoSaveInstruction;
  late String _chatType;
  late int _saveEvery;
  late double _decibelThreshold;
  late bool _assistantMode;
  late String _imageGenerationModel;
  late String? _groupProfileImageUrl;
  late final Set<String> _participantIds;
  late final List<Map<String, String>> _referenceMemos;
  late final List<Map<String, String>> _referenceFiles;
  late final List<String> _instructionHistory;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _title = TextEditingController(text: widget.initialTitle);
    _assistantInstruction =
        TextEditingController(text: settings.assistantModeInstruction ?? '');
    _imageGenerationInstruction = TextEditingController(
      text: settings.imageGenerationInstruction ?? '',
    );
    _textResponseInstruction = TextEditingController(
      text: settings.textResponseInstruction ?? '',
    );
    _meetingInstruction = TextEditingController(
      text: settings.offlineMeetingInstruction ??
          (settings.chatType == 'offline_meeting'
              ? settings.assistantModeInstruction
              : null) ??
          '주요 회의 안건 및 결론 요약',
    );
    _groupProfileImage =
        TextEditingController(text: settings.groupProfileImageUrl ?? '');
    _autoSaveCategory = TextEditingController(text: settings.autoSaveCategory);
    _autoSaveInstruction =
        TextEditingController(text: settings.autoSaveInstruction ?? '');
    _chatType = settings.chatType;
    _saveEvery = settings.saveEvery;
    _decibelThreshold = settings.decibelThreshold;
    _assistantMode = settings.assistantModeEnabled ||
        (settings.chatType != 'offline_meeting' &&
            (settings.assistantModeInstruction?.isNotEmpty ?? false));
    _imageGenerationModel = settings.imageGenerationModel;
    _groupProfileImageUrl = settings.groupProfileImageUrl;
    _participantIds = settings.selectedParticipantIds.toSet();
    if (widget.primaryFriendId case final friendId?) {
      _participantIds.add(friendId);
    }
    _referenceMemos = settings.referenceMemos
        .map((memo) => Map<String, String>.from(memo))
        .toList();
    _referenceFiles = settings.referenceFiles
        .map((file) => Map<String, String>.from(file))
        .toList();
    _instructionHistory = List<String>.from(settings.instructionHistory);
  }

  @override
  void dispose() {
    _title.dispose();
    _assistantInstruction.dispose();
    _imageGenerationInstruction.dispose();
    _textResponseInstruction.dispose();
    _meetingInstruction.dispose();
    _groupProfileImage.dispose();
    _autoSaveCategory.dispose();
    _autoSaveInstruction.dispose();
    super.dispose();
  }

  Future<void> _addMemo() async {
    final nodes = await widget.store.listNodes();
    final memos = nodes.where((node) => node.mode == 'memo').toList();
    if (!mounted) return;
    final selected = await showDialog<KnowledgeNode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('저장된 메모 선택'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: memos.isEmpty
              ? const Center(child: Text('저장된 메모가 없습니다.'))
              : ListView.builder(
                  itemCount: memos.length,
                  itemBuilder: (context, index) {
                    final memo = memos[index];
                    return ListTile(
                      title: Text(memo.title),
                      subtitle: Text(
                        memo.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(dialogContext).pop(memo),
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
    if (selected == null ||
        _referenceMemos.any((memo) => memo['id'] == selected.id)) {
      return;
    }
    setState(() {
      _referenceMemos.add({'id': selected.id, 'title': selected.title});
    });
  }

  Future<void> _addTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final existingIndex =
        _referenceFiles.indexWhere((item) => item['name'] == file.name);
    if (existingIndex >= 0 &&
        (_referenceFiles[existingIndex]['content']?.isNotEmpty ?? false)) {
      return;
    }
    try {
      final content = readChatReferenceText(file);
      final retainedFiles = [
        for (var index = 0; index < _referenceFiles.length; index++)
          if (index != existingIndex) _referenceFiles[index],
      ];
      if (chatReferenceContentsBytes([
            ...retainedFiles,
            {'content': content},
          ]) >
          maxChatReferenceContentsBytes) {
        throw StateError('참고 텍스트 파일 전체 용량은 256KB 이하로 등록해 주세요.');
      }
      if (!mounted) return;
      setState(() {
        final reference = {
          'url': file.name,
          'name': file.name,
          'content': content,
        };
        if (existingIndex >= 0) {
          _referenceFiles[existingIndex] = reference;
        } else {
          _referenceFiles.add(reference);
        }
      });
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('UTF-8 텍스트 파일만 참고자료로 등록할 수 있습니다.')),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  void _removeReference(String title, VoidCallback remove) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('참고 자료 삭제'),
        content: Text('"$title" 참고 자료를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(remove);
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  ChatSettings _updatedSettings() {
    final original = widget.initialSettings;
    final assistantInstruction = _assistantInstruction.text.trim();
    final selectedSources = [
      ..._referenceMemos
          .map((memo) => memo['title']!)
          .where((title) => title.isNotEmpty),
      ..._referenceFiles
          .map((file) => file['name']!)
          .where((name) => name.isNotEmpty),
    ];
    return ChatSettings(
      name: original.name,
      partnerType: original.partnerType,
      role: original.role,
      tone: original.tone,
      saveEvery: _saveEvery,
      selectedSources: selectedSources,
      chatType: _chatType,
      selectedParticipantIds: _participantIds.toList(),
      assistantModeInstruction:
          assistantInstruction.isEmpty ? null : assistantInstruction,
      assistantModeEnabled: _assistantMode,
      imageGenerationInstruction:
          _imageGenerationInstruction.text.trim().isEmpty
              ? null
              : _imageGenerationInstruction.text.trim(),
      imageGenerationModel: _imageGenerationModel,
      textResponseInstruction: _textResponseInstruction.text.trim().isEmpty
          ? null
          : _textResponseInstruction.text.trim(),
      offlineMeetingInstruction: _meetingInstruction.text.trim(),
      instructionHistory: _instructionHistory,
      decibelThreshold: _decibelThreshold,
      aiProfileImageUrl: original.aiProfileImageUrl,
      groupProfileImageUrl: _groupProfileImageUrl,
      referenceMemos: _referenceMemos,
      referenceFiles: _referenceFiles,
      aiTraits: original.aiTraits,
      autoSaveCategory: _autoSaveCategory.text.trim(),
      autoSaveInstruction: _autoSaveInstruction.text.trim().isEmpty
          ? null
          : _autoSaveInstruction.text.trim(),
      autoSaveThrough: original.autoSaveThrough,
      conversationSummary: original.conversationSummary,
      conversationSummaryThroughMessageId:
          original.conversationSummaryThroughMessageId,
    );
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방 이름을 입력해 주세요.')),
      );
      return;
    }
    Navigator.of(context).pop(
      ChatRoomSettingsResult(title: title, settings: _updatedSettings()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showAssistantMode =
        _chatType != 'user_user' && _chatType != 'offline_meeting';
    return Scaffold(
      appBar: AppBar(title: const Text('채팅방 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            '기본 설정',
            Column(
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '채팅방 이름'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _chatType,
                  decoration: const InputDecoration(labelText: '채팅 종류'),
                  items: const [
                    DropdownMenuItem(value: 'ai_user', child: Text('AI와 사용자')),
                    DropdownMenuItem(
                      value: 'user_user',
                      child: Text('사용자와 사용자'),
                    ),
                    DropdownMenuItem(
                      value: 'group_ai',
                      child: Text('그룹 대화와 AI 보조'),
                    ),
                    DropdownMenuItem(
                      value: 'ai_ai',
                      child: Text('AI와 AI (관전 모드)'),
                    ),
                    DropdownMenuItem(
                      value: 'offline_meeting',
                      child: Text('오프라인 회의'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _chatType = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _saveEvery,
                  decoration: const InputDecoration(labelText: '자동 저장 주기'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('저장 안함')),
                    DropdownMenuItem(value: -1, child: Text('사용자 요청시')),
                    DropdownMenuItem(value: 5, child: Text('5번째 사용자 메시지마다')),
                    DropdownMenuItem(value: 10, child: Text('10번째 사용자 메시지마다')),
                    DropdownMenuItem(value: 20, child: Text('20번째 사용자 메시지마다')),
                    DropdownMenuItem(value: 50, child: Text('50번째 사용자 메시지마다')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _saveEvery = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _autoSaveCategory,
                  decoration: const InputDecoration(
                    labelText: '생성 파일 분류',
                    hintText: '예: 채팅 기록',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _autoSaveInstruction,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '자동 저장 시 참고할 프롬프트',
                    hintText: '예: 대화의 핵심 내용과 결정 사항을 보기 좋게 정리해 주세요.',
                    helperText: '저장 대상 대화를 HTML 파일로 구성할 때 참고합니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          _section(
            '채팅 참여자',
            widget.friends.isEmpty
                ? const Text('선택할 수 있는 친구가 없습니다.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.friends.map((friend) {
                      final selected = _participantIds.contains(friend.id);
                      return FilterChip(
                        selected: selected,
                        label: Text(friend.name),
                        avatar: Icon(
                          friend.isAi ? Icons.smart_toy_rounded : Icons.person,
                          size: 18,
                        ),
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _participantIds.add(friend.id);
                            } else {
                              _participantIds.remove(friend.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
          ),
          if (_chatType == 'group_ai' || _chatType == 'user_user')
            _section(
              '그룹 프로필',
              TextField(
                controller: _groupProfileImage,
                onChanged: (value) => _groupProfileImageUrl =
                    value.trim().isEmpty ? null : value.trim(),
                decoration: const InputDecoration(
                  labelText: '그룹 프로필 이미지 URL',
                  helperText: '선택 사항',
                ),
              ),
            ),
          _section(
            '첨부 자료',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'AI가 사용자 메시지를 검토해 관련 자료가 필요할 때만 본문을 프롬프트에 포함합니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addMemo,
                      icon: const Icon(Icons.sticky_note_2_rounded),
                      label: const Text('메모 추가'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _addTextFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('.txt 첨부'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final memo in _referenceMemos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.note_alt_rounded),
                    title: Text(memo['title'] ?? '메모'),
                    trailing: IconButton(
                      tooltip: '삭제',
                      onPressed: () => _removeReference(
                        memo['title'] ?? '메모',
                        () => _referenceMemos.remove(memo),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                for (final file in _referenceFiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_rounded),
                    title: Text(file['name'] ?? '파일'),
                    trailing: IconButton(
                      tooltip: '삭제',
                      onPressed: () => _removeReference(
                        file['name'] ?? '파일',
                        () => _referenceFiles.remove(file),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                if (_referenceMemos.isEmpty && _referenceFiles.isEmpty)
                  const Text('첨부된 자료가 없습니다.'),
              ],
            ),
          ),
          _section(
            'AI 답변 프롬프트',
            Column(
              children: [
                TextField(
                  controller: _imageGenerationInstruction,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '이미지 생성 시 참고할 프롬프트',
                    hintText: '예: 따뜻한 파스텔 색감의 수채화 스타일로 그려 주세요.',
                    helperText: '이 채팅방에서 이미지 생성 요청을 할 때만 적용됩니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _imageGenerationModel,
                  decoration: const InputDecoration(
                    labelText: '이미지 생성 모델 수준',
                    helperText: '선택한 모델이 이 채팅방의 이미지 생성에 사용됩니다.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'gemini-2.5-flash-image',
                      child: Text('빠른 생성 · Gemini 2.5 Flash Image'),
                    ),
                    DropdownMenuItem(
                      value: 'gemini-3.1-flash-image',
                      child: Text('균형 · Gemini 3.1 Flash Image'),
                    ),
                    DropdownMenuItem(
                      value: 'gemini-3-pro-image',
                      child: Text('고품질 · Gemini 3 Pro Image'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _imageGenerationModel = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textResponseInstruction,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '일반 답변 시 참고할 프롬프트',
                    hintText: '예: 먼저 쉬운 한국어로 설명한 뒤 핵심 표현을 정리해 주세요.',
                    helperText: '이 채팅방의 텍스트 답변에만 적용됩니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          if (showAssistantMode)
            _section(
              'AI 보조 모드',
              Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('보조 모드 활성화'),
                    value: _assistantMode,
                    onChanged: (value) =>
                        setState(() => _assistantMode = value),
                  ),
                  if (_assistantMode)
                    TextField(
                      controller: _assistantInstruction,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '보조 모드 지시사항',
                        hintText: '예: 사용자의 문법을 교정하고 핵심 표현을 설명해 주세요.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
            ),
          if (_chatType == 'offline_meeting')
            _section(
              '회의 감지 및 분석',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('음성 감지 기준: ${_decibelThreshold.round()} dB'),
                  Slider(
                    value: _decibelThreshold,
                    min: 30,
                    max: 90,
                    divisions: 12,
                    label: '${_decibelThreshold.round()} dB',
                    onChanged: (value) =>
                        setState(() => _decibelThreshold = value),
                  ),
                  TextField(
                    controller: _meetingInstruction,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '회의 분석 지시사항',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('채팅방 설정 저장'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ),
      );
}
