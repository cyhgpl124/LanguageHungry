import 'dart:convert';

import 'package:file_picker/file_picker.dart';

const maxChatReferenceFileBytes = 128 * 1024;
const maxChatReferenceContentsBytes = 256 * 1024;

String readChatReferenceText(PlatformFile file) {
  final bytes = file.bytes;
  if (bytes == null) {
    throw StateError('파일 내용을 읽을 수 없습니다. 다시 선택해 주세요.');
  }
  if (bytes.length > maxChatReferenceFileBytes) {
    throw StateError('참고 텍스트 파일은 128KB 이하만 등록할 수 있습니다.');
  }
  final content = utf8.decode(bytes);
  if (content.trim().isEmpty) {
    throw StateError('파일에 참고할 내용이 없습니다.');
  }
  return content;
}

int chatReferenceContentsBytes(Iterable<Map<String, String>> files) {
  return files.fold<int>(
    0,
    (total, file) => total + utf8.encode(file['content'] ?? '').length,
  );
}
