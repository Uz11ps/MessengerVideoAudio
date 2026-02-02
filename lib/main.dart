import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:messenger_app/core/api_service.dart';
import 'package:messenger_app/data/repositories/auth_repository.dart';
import 'package:messenger_app/data/repositories/chat_repository.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';
import 'package:messenger_app/logic/blocs/chat_bloc.dart';
import 'package:messenger_app/presentation/screens/auth_screen.dart';
import 'package:messenger_app/presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Note: Firebase initialization requires google-services.json (Android) and GoogleService-Info.plist (iOS)
  // For this task, we assume they will be provided by the user as per the contract.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ApiService apiService;
  late final AuthRepository authRepository;

  @override
  void initState() {
    super.initState();
    apiService = ApiService();
    authRepository = AuthRepository(apiService: apiService);
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: apiService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(authRepository: authRepository)..add(AuthStarted()),
          ),
        ],
        child: MaterialApp(
          title: 'Messenger App',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
          ),
          home: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              print('Main: Current state is $state');
              if (state is AuthAuthenticated) {
                print('Main: Navigating to HomeScreen for user ${state.user.id}');
                
                return RepositoryProvider(
                  create: (context) {
                    final currentToken = apiService.token ?? '';
                    print('Main: Creating ChatRepository with token: $currentToken');
                    return ChatRepository(
                      apiService: apiService,
                      currentUserId: state.user.id,
                      token: currentToken,
                    );
                  },
                  child: BlocProvider(
                    create: (context) => ChatBloc(
                      chatRepository: context.read<ChatRepository>(),
                    ),
                    child: const HomeScreen(),
                  ),
                );
              }
              if (state is AuthUnauthenticated || state is AuthFailure || state is AuthOtpSent) {
                return const AuthScreen();
              }
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ),
      ),
    );
  }
}
