import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth_bloc.dart';

/// Entering the 6-digit code emailed at sign-up.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  /// Matches the API's resend cooldown.
  static const _cooldown = 60;

  final _code = TextEditingController();
  Timer? _timer;
  int _wait = _cooldown;

  @override
  void initState() {
    super.initState();
    // A code was just sent on the way here.
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _wait = _cooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_wait <= 1) t.cancel();
      setState(() => _wait--);
    });
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.length != 6) return;
    context.read<AuthBloc>().add(AuthVerify(widget.email, code));
  }

  void _resend() {
    _code.clear();
    context.read<AuthBloc>().add(AuthResendCode(widget.email));
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại đăng nhập',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.read<AuthBloc>().add(AuthLogout()),
        ),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is! AuthNeedsVerification) return;
          final text = state.error ?? state.info;
          if (text == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text),
              backgroundColor: state.error != null
                  ? theme.colorScheme.error
                  : null,
            ),
          );
        },
        builder: (context, state) {
          final busy = state is AuthNeedsVerification && state.busy;
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Xác thực email',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhập mã 6 số đã gửi tới\n${widget.email}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: 12,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '••••••',
                      ),
                      onChanged: (v) {
                        if (v.length == 6) _submit();
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Xác nhận'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: busy || _wait > 0 ? null : _resend,
                      child: Text(
                        _wait > 0 ? 'Gửi lại mã sau ${_wait}s' : 'Gửi lại mã',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
