class ChatSettings {
  ChatSettings({
    required this.name,
    required this.partnerType,
    required this.role,
    required this.tone,
    required this.saveEvery,
    required this.selectedSources,
    this.chatType = 'ai_user',
    this.selectedParticipantIds = const [],
    this.assistantModeInstruction,
    this.assistantModeEnabled = false,
    this.imageGenerationInstruction,
    this.imageGenerationModel = 'gemini-3.1-flash-image',
    this.textResponseInstruction,
    this.offlineMeetingInstruction,
    this.instructionHistory = const [],
    this.decibelThreshold = 50.0,
    this.aiProfileImageUrl,
    this.groupProfileImageUrl,
    this.referenceMemos = const [],
    this.referenceFiles = const [],
    this.aiTraits,
    this.autoSaveCategory = '채팅 기록',
    this.autoSaveInstruction,
    this.autoSaveThrough = 0,
    this.conversationSummary = '',
    this.conversationSummaryThroughMessageId,
  });

  String name;
  String partnerType;
  String role;
  String tone;
  int saveEvery;
  List<String> selectedSources;

  String
      chatType; // 'ai_user', 'user_user', 'group_ai', 'ai_ai', 'offline_meeting'
  List<String> selectedParticipantIds;
  String? assistantModeInstruction;
  bool assistantModeEnabled;
  String? imageGenerationInstruction;
  String imageGenerationModel;
  String? textResponseInstruction;
  String? offlineMeetingInstruction;
  List<String> instructionHistory;
  double decibelThreshold;
  String? aiProfileImageUrl;
  String? groupProfileImageUrl;
  List<Map<String, String>> referenceMemos; // [{'id': '...', 'title': '...'}]
  List<Map<String, String>> referenceFiles; // [{'url': '...', 'name': '...'}]
  String? aiTraits;
  String autoSaveCategory;
  String? autoSaveInstruction;
  int autoSaveThrough;
  String conversationSummary;
  String? conversationSummaryThroughMessageId;

  Map<String, dynamic> toMap() => {
        'name': name,
        'partnerType': partnerType,
        'role': role,
        'tone': tone,
        'saveEvery': saveEvery,
        'selectedSources': selectedSources,
        'chatType': chatType,
        'selectedParticipantIds': selectedParticipantIds,
        'assistantModeInstruction': assistantModeInstruction,
        'assistantModeEnabled': assistantModeEnabled,
        'imageGenerationInstruction': imageGenerationInstruction,
        'imageGenerationModel': imageGenerationModel,
        'textResponseInstruction': textResponseInstruction,
        'offlineMeetingInstruction': offlineMeetingInstruction,
        'instructionHistory': instructionHistory,
        'decibelThreshold': decibelThreshold,
        'aiProfileImageUrl': aiProfileImageUrl,
        'groupProfileImageUrl': groupProfileImageUrl,
        'referenceMemos': referenceMemos,
        'referenceFiles': referenceFiles,
        'aiTraits': aiTraits,
        'autoSaveCategory': autoSaveCategory,
        'autoSaveInstruction': autoSaveInstruction,
        'autoSaveThrough': autoSaveThrough,
        'conversationSummary': conversationSummary,
        'conversationSummaryThroughMessageId':
            conversationSummaryThroughMessageId,
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
        chatType: map['chatType'] as String? ?? 'ai_user',
        selectedParticipantIds: (map['selectedParticipantIds'] as List?)
                ?.whereType<String>()
                .toList() ??
            <String>[],
        assistantModeInstruction: map['assistantModeInstruction'] as String?,
        assistantModeEnabled: map['assistantModeEnabled'] as bool? ??
            ((map['assistantModeInstruction'] as String?)?.isNotEmpty ?? false),
        imageGenerationInstruction:
            map['imageGenerationInstruction'] as String?,
        imageGenerationModel: switch (map['imageGenerationModel'] as String?) {
          'gemini-3-pro-image-preview' => 'gemini-3-pro-image',
          final model? => model,
          null => 'gemini-3.1-flash-image',
        },
        textResponseInstruction: map['textResponseInstruction'] as String?,
        offlineMeetingInstruction: map['offlineMeetingInstruction'] as String?,
        instructionHistory: (map['instructionHistory'] as List?)
                ?.whereType<String>()
                .toList() ??
            <String>[],
        decibelThreshold: (map['decibelThreshold'] as num?)?.toDouble() ?? 50.0,
        aiProfileImageUrl: map['aiProfileImageUrl'] as String?,
        groupProfileImageUrl: map['groupProfileImageUrl'] as String?,
        referenceMemos: (map['referenceMemos'] as List?)
                ?.map((item) => Map<String, String>.from(item as Map))
                .toList() ??
            <Map<String, String>>[],
        referenceFiles: (map['referenceFiles'] as List?)
                ?.map((item) => Map<String, String>.from(item as Map))
                .toList() ??
            <Map<String, String>>[],
        aiTraits: map['aiTraits'] as String?,
        autoSaveCategory: map['autoSaveCategory'] as String? ?? '채팅 기록',
        autoSaveInstruction: map['autoSaveInstruction'] as String?,
        autoSaveThrough: (map['autoSaveThrough'] as num?)?.toInt() ?? 0,
        conversationSummary: map['conversationSummary'] as String? ?? '',
        conversationSummaryThroughMessageId:
            map['conversationSummaryThroughMessageId'] as String?,
      );
}
