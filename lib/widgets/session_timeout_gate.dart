import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/biometric_service.dart';
import '../services/preferences_service.dart';
import '../utils/localization_helper.dart';

typedef SessionActiveCheck = bool Function();
typedef BiometricAvailabilityCheck = Future<bool> Function();
typedef BiometricNameLoader = Future<String> Function();
typedef BiometricUnlock = Future<BiometricAuthResult> Function();

DateTime _systemNow() => DateTime.now();

class SessionTimeoutGate extends StatefulWidget {
  const SessionTimeoutGate({
    super.key,
    required this.child,
    required this.isSessionActive,
    required this.isBiometricAvailable,
    required this.loadBiometricName,
    required this.authenticate,
    required this.onSignInAgain,
    this.timeout = const Duration(minutes: 3),
    this.clock = _systemNow,
  });

  final Widget child;
  final SessionActiveCheck isSessionActive;
  final BiometricAvailabilityCheck isBiometricAvailable;
  final BiometricNameLoader loadBiometricName;
  final BiometricUnlock authenticate;
  final Future<void> Function() onSignInAgain;
  final Duration timeout;
  final DateTime Function() clock;

  @override
  State<SessionTimeoutGate> createState() => _SessionTimeoutGateState();
}

class _SessionTimeoutGateState extends State<SessionTimeoutGate>
    with WidgetsBindingObserver {
  static const Duration _biometricAttemptTimeout = Duration(seconds: 30);

  Timer? _inactivityTimer;
  late DateTime _lastActivityAt;
  bool _locked = false;
  bool _checkingBiometrics = false;
  bool _biometricAvailable = false;
  bool _authenticating = false;
  bool _signingOut = false;
  bool _authenticationFailed = false;
  String _biometricName = 'Biometric';

  @override
  void initState() {
    super.initState();
    _lastActivityAt = widget.clock();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _scheduleTimer();
  }

  @override
  void didUpdateWidget(covariant SessionTimeoutGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeout != widget.timeout) {
      _lastActivityAt = widget.clock();
      _scheduleTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _locked) return;

    final inactiveFor = widget.clock().difference(_lastActivityAt);
    if (inactiveFor >= widget.timeout) {
      _handleTimeout();
    } else {
      _scheduleTimer();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _recordActivity();
    }
    return false;
  }

  void _recordActivity([Object? _]) {
    if (_locked) return;
    _lastActivityAt = widget.clock();
    if (_inactivityTimer?.isActive != true) {
      _scheduleTimer();
    }
  }

  void _scheduleTimer() {
    _inactivityTimer?.cancel();
    if (_locked) return;

    final elapsed = widget.clock().difference(_lastActivityAt);
    final remaining = widget.timeout - elapsed;
    _inactivityTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _handleTimeout,
    );
  }

  void _handleTimeout() {
    if (!mounted || _locked) return;

    final inactiveFor = widget.clock().difference(_lastActivityAt);
    if (inactiveFor < widget.timeout) {
      _scheduleTimer();
      return;
    }

    if (!widget.isSessionActive()) {
      _lastActivityAt = widget.clock();
      _scheduleTimer();
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _locked = true;
      _authenticationFailed = false;
    });
    PreferencesService.setSessionLocked(true);
    _prepareBiometricUnlock();
  }

  Future<void> _prepareBiometricUnlock() async {
    if (_checkingBiometrics) return;
    setState(() => _checkingBiometrics = true);

    var available = false;
    var name = _biometricName;
    try {
      available = await widget.isBiometricAvailable();
      if (available) {
        name = LocalizationHelper.localizeBiometricName(
          await widget.loadBiometricName(),
        );
      }
    } catch (_) {
      available = false;
    }

    if (!mounted || !_locked) return;
    setState(() {
      _checkingBiometrics = false;
      _biometricAvailable = available;
      _biometricName = name;
    });

    if (available) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _locked) {
        await _unlockWithBiometrics();
      }
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_authenticating || !_locked || !_biometricAvailable) return;
    setState(() {
      _authenticating = true;
      _authenticationFailed = false;
    });

    BiometricAuthResult result = BiometricAuthResult.error;
    try {
      result = await widget.authenticate().timeout(
        _biometricAttemptTimeout,
        onTimeout: () => BiometricAuthResult.error,
      );
    } catch (_) {
      result = BiometricAuthResult.error;
    }

    if (!mounted) return;

    if (result == BiometricAuthResult.cancelled) {
      setState(() {
        _authenticating = false;
      });

      setState(() {
        _authenticationFailed = false;
      });
      return;
    }

    if (result == BiometricAuthResult.success && widget.isSessionActive()) {
      setState(() {
        _locked = false;
        _authenticating = false;
        _authenticationFailed = false;
      });
      PreferencesService.setSessionLocked(false);
      _lastActivityAt = widget.clock();
      _scheduleTimer();
      return;
    }

    setState(() {
      _authenticating = false;
      _authenticationFailed = true;
    });
  }

  Future<void> _signInAgain() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await PreferencesService.setSessionLocked(false);

      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await widget.onSignInAgain();
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      });
      await completer.future;
    } finally {
      if (mounted) {
        setState(() {
          _locked = false;
          _signingOut = false;
        });
        _lastActivityAt = widget.clock();
        _scheduleTimer();
      }
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _recordActivity,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _recordActivity,
        onPointerMove: _recordActivity,
        onPointerSignal: _recordActivity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: _locked,
              child: ExcludeSemantics(
                excluding: _locked,
                child: TickerMode(enabled: !_locked, child: widget.child),
              ),
            ),
            Offstage(
              offstage: !_locked,
              child: _buildLockScreen(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockScreen(BuildContext context) {
    final theme = Theme.of(context);
    final message = _checkingBiometrics
        ? 'session_checking_biometrics'.tr()
        : !_biometricAvailable
        ? 'session_biometric_unavailable'.tr()
        : _authenticationFailed
        ? 'session_biometric_failed'.tr()
        : 'session_locked_message'.tr();

    return Material(
      color: const Color(0xFFF4F7FC),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14001B44),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEAF1FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_clock_rounded,
                          size: 36,
                          color: Color(0xFF0247C4),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'session_locked_title'.tr(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF162033),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          color: const Color(0xFF667085),
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (_biometricAvailable)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _authenticating
                                ? null
                                : _unlockWithBiometrics,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0247C4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: _authenticating
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.fingerprint_rounded),
                            label: Text(
                              _authenticating
                                  ? 'session_verifying'.tr()
                                  : 'session_unlock_with_biometric'.tr(
                                      namedArgs: {
                                        'biometric': _biometricName,
                                      },
                                    ),
                            ),
                          ),
                        ),
                      if (_biometricAvailable) const SizedBox(height: 12),
                      TextButton(
                        onPressed: _signingOut ? null : _signInAgain,
                        child: Text(
                          _signingOut
                              ? 'session_signing_out'.tr()
                              : 'session_sign_in_again'.tr(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
