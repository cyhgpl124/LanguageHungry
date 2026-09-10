class LanguageDisplay {
  const LanguageDisplay({
    required this.storageName,
    required this.nativeName,
    required this.flag,
  });

  final String storageName;
  final String nativeName;
  final String flag;

  String get label => '$flag $nativeName';

  static const _languages = <LanguageDisplay>[
    LanguageDisplay(storageName: '한국어', nativeName: '한국어', flag: '🇰🇷'),
    LanguageDisplay(storageName: '영어', nativeName: 'English', flag: '🇺🇸'),
    LanguageDisplay(storageName: '일본어', nativeName: '日本語', flag: '🇯🇵'),
    LanguageDisplay(storageName: '중국어', nativeName: '中文', flag: '🇨🇳'),
    LanguageDisplay(storageName: '스페인어', nativeName: 'Español', flag: '🇪🇸'),
    LanguageDisplay(storageName: '프랑스어', nativeName: 'Français', flag: '🇫🇷'),
    LanguageDisplay(storageName: '독일어', nativeName: 'Deutsch', flag: '🇩🇪'),
  ];

  static List<LanguageDisplay> get all => _languages;

  static LanguageDisplay fromStorageName(String storageName) {
    return _languages.firstWhere(
      (language) => language.storageName == storageName,
      orElse: () => LanguageDisplay(
        storageName: storageName,
        nativeName: storageName,
        flag: '🌐',
      ),
    );
  }
}
