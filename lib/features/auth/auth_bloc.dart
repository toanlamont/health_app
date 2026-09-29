import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api_client.dart';

// Events
sealed class AuthEvent {}
class AuthLogin extends AuthEvent {
  final String email, password;
  AuthLogin(this.email, this.password);
}
class AuthRegister extends AuthEvent {
  final String email, password, fullName;
  AuthRegister(this.email, this.password, this.fullName);
}
class AuthCheckToken extends AuthEvent {}
class AuthLogout extends AuthEvent {}

// States
sealed class AuthState {}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthAuthenticated extends AuthState {}
class AuthUnauthenticated extends AuthState {}
class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final _api = ApiClient();

  AuthBloc() : super(AuthInitial()) {
    on<AuthCheckToken>(_onCheckToken);
    on<AuthLogin>(_onLogin);
    on<AuthRegister>(_onRegister);
    on<AuthLogout>(_onLogout);
  }

  Future<void> _onCheckToken(AuthCheckToken event, Emitter<AuthState> emit) async {
    final token = await _api.getToken();
    if (token != null) {
      try {
        await _api.dio.get('/auth/me');
        emit(AuthAuthenticated());
      } catch (_) {
        await _api.clearToken();
        emit(AuthUnauthenticated());
      }
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLogin(AuthLogin event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final res = await _api.dio.post('/auth/login', data: {
        'email': event.email,
        'password': event.password,
      });
      await _api.saveToken(res.data['access_token']);
      emit(AuthAuthenticated());
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? 'Login failed';
      emit(AuthError(msg.toString()));
    }
  }

  Future<void> _onRegister(AuthRegister event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _api.dio.post('/auth/register', data: {
        'email': event.email,
        'password': event.password,
        'full_name': event.fullName,
      });
      // Auto login after register
      final res = await _api.dio.post('/auth/login', data: {
        'email': event.email,
        'password': event.password,
      });
      await _api.saveToken(res.data['access_token']);
      emit(AuthAuthenticated());
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? 'Registration failed';
      emit(AuthError(msg.toString()));
    }
  }

  Future<void> _onLogout(AuthLogout event, Emitter<AuthState> emit) async {
    await _api.clearToken();
    emit(AuthUnauthenticated());
  }
}
