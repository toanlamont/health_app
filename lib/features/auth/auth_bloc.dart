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
class AuthVerify extends AuthEvent {
  final String email, code;
  AuthVerify(this.email, this.code);
}
class AuthResendCode extends AuthEvent {
  final String email;
  AuthResendCode(this.email);
}

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
/// Signed up (or tried to log in) but the emailed code hasn't been entered.
///
/// Carries its own [busy]/[error]/[info] rather than going through
/// AuthLoading/AuthError, which would swap the code screen for the login one.
class AuthNeedsVerification extends AuthState {
  final String email;
  final bool busy;
  final String? error;
  final String? info;
  AuthNeedsVerification(this.email, {this.busy = false, this.error, this.info});
}

/// What the API sends back as the 403 detail for an unverified account.
const _notVerified = 'EMAIL_NOT_VERIFIED';

String _detail(DioException e, String fallback) {
  final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
  return detail is String ? detail : fallback;
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final _api = ApiClient();

  AuthBloc() : super(AuthInitial()) {
    on<AuthCheckToken>(_onCheckToken);
    on<AuthLogin>(_onLogin);
    on<AuthRegister>(_onRegister);
    on<AuthLogout>(_onLogout);
    on<AuthVerify>(_onVerify);
    on<AuthResendCode>(_onResendCode);
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
      if (e.response?.statusCode == 403 && _detail(e, '') == _notVerified) {
        // The code from sign-up has likely expired by now, so send a fresh
        // one. A 429 just means one went out a moment ago.
        try {
          await _api.dio.post('/auth/resend-code', data: {'email': event.email});
        } on DioException catch (_) {}
        emit(AuthNeedsVerification(
          event.email,
          info: 'Tài khoản chưa xác thực. Mã mới đã được gửi tới email của bạn.',
        ));
        return;
      }
      emit(AuthError(_detail(e, 'Đăng nhập thất bại')));
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
      // The account can't log in until the emailed code is entered; a
      // successful /verify-email hands back the token.
      emit(AuthNeedsVerification(
        event.email,
        info: 'Mã xác thực đã được gửi tới ${event.email}',
      ));
    } on DioException catch (e) {
      emit(AuthError(_detail(e, 'Đăng ký thất bại')));
    }
  }

  Future<void> _onVerify(AuthVerify event, Emitter<AuthState> emit) async {
    emit(AuthNeedsVerification(event.email, busy: true));
    try {
      final res = await _api.dio.post('/auth/verify-email', data: {
        'email': event.email,
        'code': event.code,
      });
      await _api.saveToken(res.data['access_token']);
      emit(AuthAuthenticated());
    } on DioException catch (e) {
      emit(AuthNeedsVerification(
        event.email,
        error: _detail(e, 'Không xác thực được, thử lại sau'),
      ));
    }
  }

  Future<void> _onResendCode(AuthResendCode event, Emitter<AuthState> emit) async {
    emit(AuthNeedsVerification(event.email, busy: true));
    try {
      await _api.dio.post('/auth/resend-code', data: {'email': event.email});
      emit(AuthNeedsVerification(event.email, info: 'Đã gửi lại mã'));
    } on DioException catch (e) {
      emit(AuthNeedsVerification(
        event.email,
        error: _detail(e, 'Không gửi lại được mã, thử lại sau'),
      ));
    }
  }

  Future<void> _onLogout(AuthLogout event, Emitter<AuthState> emit) async {
    await _api.clearToken();
    emit(AuthUnauthenticated());
  }
}
