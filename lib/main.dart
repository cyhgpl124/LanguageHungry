import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/find_account/presentation/find_account_screen/find_account_screen.dart';
import 'features/auth/login/presentation/login_screen/login_screen.dart';
import 'features/auth/onboarding/presentation/additional_info_screen.dart';
import 'features/auth/onboarding/presentation/language_selection_screen.dart';
import 'features/auth/onboarding/presentation/verify_email_screen.dart';
import 'features/auth/sign_up/presentation/sign_up_screen/sign_up_screen.dart';
import 'features/auth/splash/presentation/splash_screen/splash_screen.dart';
import 'features/auth/terms/presentation/terms_screen/terms_screen.dart';
import 'features/chat/presentation/chat_screens.dart';
import 'features/home/presentation/home_screen/home_screen.dart';
import 'features/knowledge/data/knowledge_database.dart';
import 'features/knowledge/data/cloud_first_knowledge_store.dart';
import 'features/knowledge/data/mobile_cloud_handoff_service.dart';
import 'features/knowledge/presentation/file_parsing_screen.dart';
import 'features/knowledge/presentation/memo_workspace_screen.dart';
import 'features/knowledge/presentation/workspace_shell.dart';
import 'features/market/presentation/market_screen.dart';
import 'features/profile/presentation/my_page.dart';
import 'features/profile/presentation/edit_profile_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaEnterpriseProvider(
        '6Ld9nq4tAAAAAKtaAfbvEJdGHFUUb8E1c2DRTbUh',
      ),
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
  }
  FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance);
  final localStore = SqliteKnowledgeStore();
  final isCloudFirst =
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
  final knowledgeStore = isCloudFirst
      ? CloudFirstKnowledgeStore(localStore: localStore)
      : localStore;
  await knowledgeStore.initialize();
  runApp(
    MyApp(
      repository: FirebaseAuthRepository(),
      knowledgeStore: knowledgeStore,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    required this.repository,
    required this.knowledgeStore,
    super.key,
  });

  final AuthRepository repository;
  final KnowledgeStore knowledgeStore;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthBloc _authBloc;
  late final GoRouter _router;
  late final MobileCloudHandoffService _mobileCloudHandoff;
  bool _mobileCloudSyncStarted = false;
  Locale _locale = const Locale('ko');

  void _applyNativeLanguage(String? language) {
    final code = switch (language) {
      '영어' => 'en',
      '일본어' => 'ja',
      '중국어' => 'zh',
      '스페인어' => 'es',
      '프랑스어' => 'fr',
      '독일어' => 'de',
      _ => 'ko',
    };
    if (mounted) setState(() => _locale = Locale(code));
  }

  Future<void> _finishLanguageSetup() async {
    final data = await widget.repository.loadHomeData();
    _applyNativeLanguage(data.activeNativeLanguage ??
        (data.nativeLanguages.isEmpty ? null : data.nativeLanguages.first));
    _authBloc.add(const AuthProfileUpdated());
    _router.go('/home');
  }

  Future<void> _changeActiveLanguage(
    String nativeLanguage,
    String learningLanguage,
  ) async {
    final data = await widget.repository.loadHomeData();
    await widget.repository.saveLanguagePreferences(
      nativeLanguages: data.nativeLanguages,
      learningLanguages: data.learningLanguages,
      activeNativeLanguage: nativeLanguage,
      activeLearningLanguage: learningLanguage,
    );
    _applyNativeLanguage(nativeLanguage);
  }

  Future<void> _activateMobileCloudData() async {
    try {
      await _mobileCloudHandoff.activate();
    } finally {
      _mobileCloudSyncStarted = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _mobileCloudHandoff = MobileCloudHandoffService(
      localStore: widget.knowledgeStore,
    );
    _authBloc = AuthBloc(widget.repository);
    _router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => SplashScreen(
            onFinished: () => _authBloc.add(const AuthStarted()),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(
            onSignUp: () => context.go('/sign-up'),
            onFindAccount: () => context.go('/find-account'),
            onLoginSuccess: (user) {
              if (user.needsEmailVerification) {
                _router.go('/verify-email');
              } else if (user.needsAdditionalInfo) {
                _router.go('/additional-info');
              } else if (user.needsLanguageSetup) {
                _router.go('/language-selection');
              } else {
                _router.go('/home');
              }
            },
          ),
        ),
        GoRoute(
          path: '/sign-up',
          builder: (context, state) => SignUpScreen(
            onTerms: () => context.push('/terms'),
          ),
        ),
        GoRoute(
          path: '/additional-info',
          builder: (context, state) => AdditionalInfoScreen(
            onTerms: () => context.push('/terms'),
            onCompleted: () {
              _authBloc.add(const AuthProfileUpdated());
              _router.go('/language-selection');
            },
          ),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (context, state) => VerifyEmailScreen(
            onVerified: () => _authBloc.add(const AuthProfileUpdated()),
          ),
        ),
        GoRoute(
          path: '/language-selection',
          builder: (context, state) => LanguageSelectionScreen(
            onCompleted: _finishLanguageSetup,
          ),
        ),
        GoRoute(
          path: '/find-account',
          builder: (context, state) => const FindAccountScreen(),
        ),
        GoRoute(
          path: '/terms',
          builder: (context, state) => const TermsScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => WorkspaceShell(
            store: widget.knowledgeStore,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => HomeScreen(
                onLanguageSettings: () => _router.go('/language-selection'),
                onLanguageChanged: _changeActiveLanguage,
                onStartChat: () => _router.go('/chat?start=1'),
              ),
            ),
            GoRoute(
              path: '/chat',
              builder: (context, state) => ChatWorkspaceScreen(
                store: widget.knowledgeStore,
                autoStart: state.uri.queryParameters['start'] == '1',
              ),
            ),
            GoRoute(
              path: '/file-import',
              builder: (context, state) =>
                  FileParsingScreen(store: widget.knowledgeStore),
            ),
            GoRoute(
              path: '/knowledge-list',
              builder: (context, state) =>
                  MemoWorkspaceScreen(store: widget.knowledgeStore),
            ),
            GoRoute(
              path: '/market',
              builder: (context, state) => const MarketScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => MyPage(
                onLanguageSettings: () => _router.go('/language-selection'),
                onEditProfile: () async {
                  await _router.push<bool>('/profile/edit');
                },
              ),
            ),
            GoRoute(
              path: '/profile/edit',
              builder: (context, state) => const EditProfileScreen(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: widget.repository,
      child: BlocProvider.value(
        value: _authBloc,
        child: MaterialApp.router(
          title: 'LANGGRY',
          theme: AppTheme.light,
          locale: _locale,
          supportedLocales: const [
            Locale('ko'),
            Locale('en'),
            Locale('ja'),
            Locale('zh'),
            Locale('es'),
            Locale('fr'),
            Locale('de'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
          builder: (context, child) => BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              final path = _router.routeInformationProvider.value.uri.path;
              if (state is AuthAuthenticated) {
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.android ||
                        defaultTargetPlatform == TargetPlatform.iOS)) {
                  if (!_mobileCloudSyncStarted) {
                    _mobileCloudSyncStarted = true;
                    unawaited(_activateMobileCloudData());
                  }
                }
                if (state.user.needsEmailVerification &&
                    path != '/verify-email') {
                  _router.go('/verify-email');
                } else if (state.user.needsAdditionalInfo &&
                    path != '/additional-info') {
                  _router.go('/additional-info');
                } else if (state.user.needsLanguageSetup &&
                    path != '/language-selection') {
                  _router.go('/language-selection');
                } else if (!state.user.needsAdditionalInfo &&
                    !state.user.needsLanguageSetup &&
                    path != '/home') {
                  _router.go('/home');
                }
              } else if (state is AuthFailure) {
                if (path == '/splash') {
                  _router.go('/login');
                }
              } else if (state is AuthUnauthenticated && path != '/login') {
                _router.go('/login');
              }
            },
            child: child!,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _authBloc.close();
    super.dispose();
  }
}
