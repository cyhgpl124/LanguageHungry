import 'chat_settings.dart';

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.title,
    required this.partner,
    required this.isAi,
    required this.settings,
    this.friendId,
    this.lastMessage,
    this.updatedAt,
  });

  final String id;
  String title;
  String partner;
  final bool isAi;
  String? friendId;
  String? lastMessage;
  ChatSettings settings;
  List<String> messages = <String>[];
  DateTime? updatedAt;
}
