import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:langgry/features/chat/models/chat_settings.dart';
import 'package:uuid/uuid.dart';

class ChatSetupScreen extends StatefulWidget {
  const ChatSetupScreen({
    this.initialSettings,
    this.isRoomCreation = false,
    super.key,
  });

  final ChatSettings? initialSettings;
  final bool isRoomCreation;

  @override
  State<ChatSetupScreen> createState() => _ChatSetupScreenState();
}

class _ChatSetupScreenState extends State<ChatSetupScreen> {
  final _name = TextEditingController(text: 'Emma');
  final _role = TextEditingController(text: '친절한 언어 학습 보조');
  final _traits = TextEditingController(text: '공감 능력이 뛰어남, 세심하게 교정해줌');

  String _partnerType = 'AI';
  String _tone = '친근하게';
  String? _profileImageUrl;
  Uint8List? _profileImageBytes;
  String? _profileImageContentType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    if (settings != null) {
      _name.text = settings.name;
      _partnerType = settings.partnerType;
      _role.text = settings.role;
      _tone = settings.tone;
      final savedImageUrl = settings.aiProfileImageUrl;
      if (savedImageUrl != null &&
          (savedImageUrl.startsWith('https://') ||
              savedImageUrl.startsWith('http://'))) {
        _profileImageUrl = savedImageUrl;
      }
      _traits.text = settings.aiTraits ?? _traits.text;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _traits.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final selected = await _pickImage();
    if (selected == null || !mounted) return;
    setState(() {
      _profileImageBytes = selected.$1;
      _profileImageContentType = selected.$2;
    });
  }

  Future<(Uint8List, String?)?> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return (bytes, picked.mimeType);
  }

  Future<String> _uploadImage({
    required Uint8List bytes,
    required String folder,
    required String? contentType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('로그인 후 이미지를 저장할 수 있습니다.');
    }
    final storage = FirebaseStorage.instanceFor(
      app: Firebase.app(),
      bucket: 'gs://languagehungry.firebasestorage.app',
    );
    final image = storage.ref('users/${user.uid}/$folder/${const Uuid().v4()}');
    await image.putData(
      bytes,
      SettableMetadata(contentType: contentType ?? 'image/jpeg'),
    );
    return image.getDownloadURL();
  }

  Future<void> _saveAndReturn() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      var imageUrl = _profileImageUrl;
      if (_profileImageBytes != null) {
        imageUrl = await _uploadImage(
          bytes: _profileImageBytes!,
          folder: 'ai-profiles',
          contentType: _profileImageContentType,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        ChatSettings(
          name: _name.text.trim().isEmpty ? 'AI 보조' : _name.text.trim(),
          partnerType: _partnerType,
          role: _role.text.trim(),
          tone: _tone,
          saveEvery: widget.initialSettings?.saveEvery ?? 10,
          selectedSources:
              widget.initialSettings?.selectedSources ?? const <String>[],
          chatType: widget.initialSettings?.chatType ?? 'ai_user',
          selectedParticipantIds:
              widget.initialSettings?.selectedParticipantIds ?? const [],
          assistantModeInstruction:
              widget.initialSettings?.assistantModeInstruction,
          assistantModeEnabled:
              widget.initialSettings?.assistantModeEnabled ?? false,
          imageGenerationInstruction:
              widget.initialSettings?.imageGenerationInstruction,
          imageGenerationModel: widget.initialSettings?.imageGenerationModel ??
              'gemini-3.1-flash-image',
          textResponseInstruction:
              widget.initialSettings?.textResponseInstruction,
          offlineMeetingInstruction:
              widget.initialSettings?.offlineMeetingInstruction,
          instructionHistory:
              widget.initialSettings?.instructionHistory ?? const [],
          decibelThreshold: widget.initialSettings?.decibelThreshold ?? 50.0,
          aiProfileImageUrl: imageUrl,
          groupProfileImageUrl: widget.initialSettings?.groupProfileImageUrl,
          referenceMemos: widget.initialSettings?.referenceMemos ?? const [],
          referenceFiles: widget.initialSettings?.referenceFiles ?? const [],
          aiTraits: _traits.text.trim(),
          autoSaveCategory: widget.initialSettings?.autoSaveCategory ?? '채팅 기록',
          autoSaveInstruction: widget.initialSettings?.autoSaveInstruction,
          autoSaveThrough: widget.initialSettings?.autoSaveThrough ?? 0,
          conversationSummary:
              widget.initialSettings?.conversationSummary ?? '',
          conversationSummaryThroughMessageId:
              widget.initialSettings?.conversationSummaryThroughMessageId,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 프로필을 저장하지 못했습니다: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialSettings != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? 'AI 설정'
              : widget.isRoomCreation
                  ? 'AI 설정'
                  : '새 AI 친구 만들기',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Profile Image Registration
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: _profileImageBytes != null
                      ? MemoryImage(_profileImageBytes!)
                      : _profileImageUrl != null
                          ? NetworkImage(_profileImageUrl!)
                          : null,
                  child: _profileImageBytes == null && _profileImageUrl == null
                      ? const Icon(Icons.smart_toy_rounded, size: 48)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt_rounded, size: 16),
                      color: Colors.white,
                      onPressed: _pickProfileImage,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Basic AI Details
          _section(
            'AI 기본 설정',
            Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'AI 이름'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _traits,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'AI 기본 특성 (자아/성격 설정)',
                    hintText: '예: 친근하고 경청하는 태도, 세심한 교정',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _role,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'AI 역할',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _tone,
                  decoration: const InputDecoration(labelText: 'AI 말투'),
                  items: const ['친근하게', '차분하게', '선생님처럼', '간결하게']
                      .map((tone) =>
                          DropdownMenuItem(value: tone, child: Text(tone)))
                      .toList(),
                  onChanged: (value) => setState(() => _tone = value ?? _tone),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _saveAndReturn,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saving
                  ? '이미지 저장 중...'
                  : widget.isRoomCreation
                      ? 'AI 설정 완료'
                      : isEditing
                          ? 'AI 설정 저장'
                          : 'AI 아바타 추가',
            ),
          ),
        ],
      ),
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
