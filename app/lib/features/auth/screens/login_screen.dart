import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/core/widgets/app_face_swap_logo.dart';
import 'package:face_swap_video/features/auth/widgets/auth_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final Uri _termsUri = Uri.parse('https://baoganai.com/terms');
  static final Uri _privacyUri = Uri.parse('https://baoganai.com/privacy');

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _agreed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _phoneController.text = auth.suggestedPhone;
  }

  Future<void> _loadPrimarySimPhone() async {
    final auth = context.read<AuthProvider>();
    final previousSuggestion = auth.suggestedPhone;
    await auth.loadSuggestedPhone();
    if (!mounted) return;

    final shouldApplyDetectedPhone =
        _phoneController.text.trim().isEmpty ||
        _phoneController.text.trim() == previousSuggestion;
    if (shouldApplyDetectedPhone && auth.suggestedPhone.trim().isNotEmpty) {
      _phoneController.text = auth.suggestedPhone;
      _showMessage('已尝试读取本机号码；你也可以手动修改手机号');
    } else {
      _showMessage('未读取到本机号码，请手动输入手机号');
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_validateAgreement()) return;
    try {
      await context.read<AuthProvider>().sendCode(_phoneController.text);
      if (!mounted) return;
      setState(() => _message = '验证码已发送（当前为测试模式，请输入6位数字验证码）');
    } on ArgumentError catch (error) {
      _showMessage(error.message.toString());
    }
  }

  Future<void> _login() async {
    if (!_validateAgreement()) return;
    try {
      await context.read<AuthProvider>().loginWithSms(
        phone: _phoneController.text,
        code: _codeController.text,
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    } on ArgumentError catch (error) {
      _showMessage(error.message.toString());
    }
  }

  bool _validateAgreement() {
    if (_agreed) return true;
    _showMessage('请先阅读并同意用户协议和隐私政策');
    return false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  Future<void> _openLegalPage(Uri uri, String title) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showMessage('无法打开$title，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: AppFaceSwapLogo(
                          key: ValueKey('auth-app-logo'),
                          size: 72,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '手机号登录 / 注册',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '测试阶段使用 Mock 短信验证，任意手机号和6位数字验证码都可以通过',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildTextField(
                        key: const ValueKey('auth-phone-field'),
                        controller: _phoneController,
                        label: '手机号',
                        hint: '请输入手机号',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('auth-detect-phone-button'),
                          onPressed: auth.isLoadingSuggestedPhone
                              ? null
                              : _loadPrimarySimPhone,
                          icon: const Icon(Icons.sim_card_outlined, size: 16),
                          label: Text(
                            auth.isLoadingSuggestedPhone
                                ? '正在读取本机号码'
                                : '可选：读取本机号码自动填入',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(
                              alpha: 0.72,
                            ),
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              key: const ValueKey('auth-code-field'),
                              controller: _codeController,
                              label: '验证码',
                              hint: '请输入6位验证码',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 46,
                            child: FilledButton.tonal(
                              key: const ValueKey('auth-send-code-button'),
                              onPressed: auth.canSendCode ? _sendCode : null,
                              child: Text(
                                auth.codeCountdownSeconds > 0
                                    ? '${auth.codeCountdownSeconds}秒'
                                    : auth.isSendingCode
                                    ? '发送中'
                                    : '获取验证码',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildAgreement(),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          key: const ValueKey('auth-message'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          key: const ValueKey('auth-login-button'),
                          onPressed: auth.isLoggingIn ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            auth.isLoggingIn ? '登录中...' : '登录 / 注册',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '登录即代表你确认拥有素材授权，并同意仅用于合规 AI 生成。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.34),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    required TextInputType keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFA855F7), width: 1.4),
        ),
      ),
    );
  }

  Widget _buildAgreement() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          key: const ValueKey('auth-agreement-checkbox'),
          value: _agreed,
          activeColor: const Color(0xFF7C3AED),
          onChanged: (value) => setState(() => _agreed = value ?? false),
        ),
        Expanded(
          child: Wrap(
            children: [
              Text(
                '我已阅读并同意',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
              ),
              _buildLegalLink(
                key: const ValueKey('auth-terms-link'),
                label: '《用户协议》',
                uri: _termsUri,
              ),
              Text(
                '和',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
              ),
              _buildLegalLink(
                key: const ValueKey('auth-privacy-link'),
                label: '《隐私政策》',
                uri: _privacyUri,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegalLink({
    required Key key,
    required String label,
    required Uri uri,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => _openLegalPage(uri, label),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFA855F7),
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFA855F7),
        ),
      ),
    );
  }
}
