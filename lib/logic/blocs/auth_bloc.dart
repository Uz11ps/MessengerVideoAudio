import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:messenger_app/data/models/user_model.dart';
import 'package:messenger_app/data/repositories/auth_repository.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {}

class AuthPhoneSubmitted extends AuthEvent {
  final String phoneNumber;
  AuthPhoneSubmitted(this.phoneNumber);
  @override
  List<Object?> get props => [phoneNumber];
}

class AuthEmailSubmitted extends AuthEvent {
  final String email;
  final String password;
  final bool isRegister;
  final String? displayName;
  AuthEmailSubmitted({
    required this.email, 
    required this.password, 
    this.isRegister = false,
    this.displayName,
  });
  @override
  List<Object?> get props => [email, password, isRegister, displayName];
}

class AuthOtpSubmitted extends AuthEvent {
  final String verificationId;
  final String smsCode;
  AuthOtpSubmitted(this.verificationId, this.smsCode);
  @override
  List<Object?> get props => [verificationId, smsCode];
}

class AuthLoggedOut extends AuthEvent {}

class AuthUserUpdated extends AuthEvent {
  final Map<String, dynamic> userData;
  AuthUserUpdated(this.userData);
  @override
  List<Object?> get props => [userData];
}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthOtpSent extends AuthState {
  final String verificationId;
  AuthOtpSent(this.verificationId);
  @override
  List<Object?> get props => [verificationId];
}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthFailure extends AuthState {
  final String message;
  AuthFailure(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    on<AuthStarted>((event, emit) async {
      // Сначала пытаемся загрузить сохраненного пользователя
      var user = await _authRepository.loadSavedUser();
      if (user == null) {
        // Если нет сохраненного, проверяем текущего
        user = _authRepository.currentUser;
      }
      if (user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(AuthUnauthenticated());
      }
    });

    on<AuthPhoneSubmitted>((event, emit) async {
      emit(AuthLoading());
      try {
        final result = await _authRepository.sendOtp(event.phoneNumber);
        if (result['success'] == true) {
          emit(AuthOtpSent(event.phoneNumber));
        } else {
          // Используем сообщение от сервера или дефолтное
          final errorMessage = result['message'] ?? 'Ошибка отправки SMS кода';
          emit(AuthFailure(errorMessage));
        }
      } catch (e) {
        emit(AuthFailure('Ошибка сети: ${e.toString()}'));
      }
    });

    on<AuthEmailSubmitted>((event, emit) async {
      emit(AuthLoading());
      try {
        UserModel? user;
        if (event.isRegister) {
          user = await _authRepository.registerEmail(
            event.email, 
            event.password, 
            event.displayName ?? ''
          );
        } else {
          user = await _authRepository.loginEmail(event.email, event.password);
        }
        
        if (user != null) {
          emit(AuthAuthenticated(user));
        } else {
          emit(AuthFailure('Ошибка авторизации'));
        }
      } catch (e) {
        // Убираем префикс "Exception: " для более чистого сообщения
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        emit(AuthFailure(errorMessage));
      }
    });

    on<AuthOtpSubmitted>((event, emit) async {
      emit(AuthLoading());
      try {
        final user = await _authRepository.verifyOtp(event.verificationId, event.smsCode);
        if (user != null) {
          emit(AuthAuthenticated(user));
        } else {
          emit(AuthFailure('Неверный код подтверждения'));
        }
      } catch (e) {
        // Убираем префикс "Exception: " для более чистого сообщения
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        emit(AuthFailure(errorMessage));
      }
    });

    on<AuthLoggedOut>((event, emit) async {
      await _authRepository.signOut();
      emit(AuthUnauthenticated());
    });

    on<AuthUserUpdated>((event, emit) async {
      if (state is AuthAuthenticated) {
        // Обновляем данные пользователя из полученных данных
        final updatedUser = UserModel.fromMap(event.userData);
        emit(AuthAuthenticated(updatedUser));
      }
    });
  }
}

// Internal events to bridge Firebase callbacks to Bloc
class _InternalOtpSent extends AuthEvent {
  final String verificationId;
  _InternalOtpSent(this.verificationId);
}

class _InternalAuthSuccess extends AuthEvent {
  final UserModel user;
  _InternalAuthSuccess(this.user);
}

class _InternalAuthFailure extends AuthEvent {
  final String message;
  _InternalAuthFailure(this.message);
}
