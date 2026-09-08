import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'features/home/presentation/home_screen/home_screen.dart';
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
  runApp(MyApp(repository: FirebaseAuthRepository()));
}

class MyApp extends StatefulWidget {
  const MyApp({required this.repository, super.key});

  final AuthRepository repository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthBloc _authBloc;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
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
            onCompleted: () {
              _authBloc.add(const AuthProfileUpdated());
              _router.go('/home');
            },
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
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
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
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            final path = _router.routeInformationProvider.value.uri.path;
            if (state is AuthAuthenticated) {
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
          child: MaterialApp.router(
            title: 'LANGGRY',
            theme: AppTheme.light,
            routerConfig: _router,
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
