import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  const AuthSession({required this.phone});

  final String phone;
}

abstract class AuthSessionStore {
  Future<AuthSession?> load();
  Future<void> save(AuthSession session);
  Future<void> clear();
}

class SharedPreferencesAuthSessionStore implements AuthSessionStore {
  static const String _phoneKey = 'auth.session.phone';
  static const String _authenticatedKey = 'auth.session.authenticated';

  @override
  Future<AuthSession?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final isAuthenticated = preferences.getBool(_authenticatedKey) ?? false;
    final phone = preferences.getString(_phoneKey);
    if (!isAuthenticated || phone == null || phone.isEmpty) {
      return null;
    }
    return AuthSession(phone: phone);
  }

  @override
  Future<void> save(AuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_authenticatedKey, true);
    await preferences.setString(_phoneKey, session.phone);
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_authenticatedKey);
    await preferences.remove(_phoneKey);
  }
}
