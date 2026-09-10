import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings._(this.locale);

  final Locale locale;

  static AppStrings of(BuildContext context) =>
      AppStrings._(Localizations.localeOf(context));

  String get home =>
      _text('홈', 'Home', 'ホーム', '首页', 'Inicio', 'Accueil', 'Startseite');
  String get chat => _text('채팅', 'Chat', 'チャット', '聊天', 'Chat', 'Chat', 'Chat');
  String get files =>
      _text('파일', 'Files', 'ファイル', '文件', 'Archivos', 'Fichiers', 'Dateien');
  String get notes =>
      _text('메모', 'Notes', 'メモ', '笔记', 'Notas', 'Notes', 'Notizen');
  String get myPage =>
      _text('마이페이지', 'Profile', 'マイページ', '个人中心', 'Perfil', 'Profil', 'Profil');
  String get refresh => _text('새로고침', 'Refresh', '更新', '刷新', 'Actualizar',
      'Actualiser', 'Aktualisieren');
  String get logout => _text('로그아웃', 'Log out', 'ログアウト', '退出登录',
      'Cerrar sesión', 'Se déconnecter', 'Abmelden');
  String get nativeLanguage => _text('모국어', 'Native language', '母語', '母语',
      'Idioma nativo', 'Langue maternelle', 'Muttersprache');
  String get learningLanguage => _text('배우는 언어', 'Learning languages', '学習言語',
      '学习语言', 'Idiomas de aprendizaje', 'Langues étudiées', 'Lernsprachen');
  String get startChat => _text('채팅 시작', 'Start chat', 'チャットを始める', '开始聊天',
      'Iniciar chat', 'Démarrer le chat', 'Chat starten');
  String get changeLanguages => _text(
      '언어 설정 다시하기',
      'Change languages',
      '言語設定を変更',
      '重新设置语言',
      'Cambiar idiomas',
      'Changer les langues',
      'Sprachen ändern');
  String get attendanceAndStudy => _text(
      '출석과 공부 시간',
      'Attendance and study time',
      '出席と学習時間',
      '出勤和学习时间',
      'Asistencia y tiempo de estudio',
      'Présence et temps d’étude',
      'Anwesenheit und Lernzeit');
  String get attendanceCheck => _text('출석 체크', 'Check in', '出席チェック', '签到',
      'Registrar asistencia', 'Pointer', 'Einchecken');
  String get reviewRecommendation => _text(
      '오늘의 복습 추천',
      'Today’s review',
      '今日の復習',
      '今日复习推荐',
      'Repaso de hoy',
      'Révision du jour',
      'Heutige Wiederholung');
  String get noReviews => _text(
      '오늘은 복습할 항목이 없어요.',
      'No reviews for today.',
      '今日は復習項目がありません。',
      '今天没有复习项目。',
      'No hay repasos para hoy.',
      'Aucune révision aujourd’hui.',
      'Heute keine Wiederholungen.');
  String get retry => _text('다시 시도', 'Try again', '再試行', '重试', 'Reintentar',
      'Réessayer', 'Erneut versuchen');
  String get homeLoadError => _text(
      '홈 정보를 불러오지 못했어요.',
      'Could not load home data.',
      'ホーム情報を読み込めませんでした。',
      '无法加载主页信息。',
      'No se pudo cargar el inicio.',
      'Impossible de charger l’accueil.',
      'Startdaten konnten nicht geladen werden.');

  String streak(int days) => _text(
      '$days일 연속',
      '$days day streak',
      '$days日連続',
      '连续 $days 天',
      'Racha de $days días',
      'Série de $days jours',
      '$days Tage in Folge');
  String studyMinutes(int minutes) => _text(
      '누적 공부 시간  $minutes분',
      'Total study time  $minutes min',
      '累積学習時間 $minutes分',
      '累计学习时间 $minutes 分钟',
      'Tiempo total $minutes min',
      'Temps total $minutes min',
      'Lernzeit gesamt $minutes Min.');
  String reviewCount(int count) => _text(
      '$count개의 항목을 복습해 보세요.',
      'Review $count items.',
      '$count個を復習しましょう。',
      '复习 $count 个项目。',
      'Repasa $count elementos.',
      'Révisez $count éléments.',
      '$count Elemente wiederholen.');

  String _text(String ko, String en, String ja, String zh, String es, String fr,
      String de) {
    return switch (locale.languageCode) {
      'en' => en,
      'ja' => ja,
      'zh' => zh,
      'es' => es,
      'fr' => fr,
      'de' => de,
      _ => ko,
    };
  }
}
