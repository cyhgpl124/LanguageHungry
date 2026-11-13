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

  String localizedName(String localeCode) {
    const names = <String, Map<String, String>>{
      '한국어': {
        'ko': '한국어',
        'en': 'Korean',
        'ja': '韓国語',
        'zh': '韩语',
        'es': 'coreano',
        'fr': 'coréen',
        'de': 'Koreanisch',
      },
      '영어': {
        'ko': '영어',
        'en': 'English',
        'ja': '英語',
        'zh': '英语',
        'es': 'inglés',
        'fr': 'anglais',
        'de': 'Englisch',
      },
      '일본어': {
        'ko': '일본어',
        'en': 'Japanese',
        'ja': '日本語',
        'zh': '日语',
        'es': 'japonés',
        'fr': 'japonais',
        'de': 'Japanisch',
      },
      '중국어': {
        'ko': '중국어',
        'en': 'Chinese',
        'ja': '中国語',
        'zh': '中文',
        'es': 'chino',
        'fr': 'chinois',
        'de': 'Chinesisch',
      },
      '스페인어': {
        'ko': '스페인어',
        'en': 'Spanish',
        'ja': 'スペイン語',
        'zh': '西班牙语',
        'es': 'español',
        'fr': 'espagnol',
        'de': 'Spanisch',
      },
      '프랑스어': {
        'ko': '프랑스어',
        'en': 'French',
        'ja': 'フランス語',
        'zh': '法语',
        'es': 'francés',
        'fr': 'français',
        'de': 'Französisch',
      },
      '독일어': {
        'ko': '독일어',
        'en': 'German',
        'ja': 'ドイツ語',
        'zh': '德语',
        'es': 'alemán',
        'fr': 'allemand',
        'de': 'Deutsch',
      },
    };

    return names[storageName]?[localeCode] ?? nativeName;
  }

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

  static String localeCodeForStorageName(String? storageName) {
    return switch (storageName) {
      '영어' => 'en',
      '일본어' => 'ja',
      '중국어' => 'zh',
      '스페인어' => 'es',
      '프랑스어' => 'fr',
      '독일어' => 'de',
      _ => 'ko',
    };
  }

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
