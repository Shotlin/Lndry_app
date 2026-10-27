import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/core/constants/app_constants.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage extends StorageService {
  _Storage({required super.prefs});
  final Map<String, String> secure = {};
  @override
  Future<void> saveSecure(String key, String value) async => secure[key] = value;
  @override
  Future<String?> getSecure(String key) async => secure[key];
  @override
  Future<void> deleteSecure(String key) async => secure.remove(key);
}

class _Repo extends MockCustomerRepository {
  _Repo({this.profileError});
  final Object? profileError;
  int refreshCalls = 0;

  @override
  Future<TokenPair> refreshTokens() async {
    refreshCalls++;
    return super.refreshTokens();
  }

  @override
  Future<UserModel> getProfile() async {
    if (profileError != null) throw profileError!;
    return const UserModel(id: 'u1', name: 'Sayan', phone: '9999999999', role: UserRole.customer);
  }
}

DioException _http(int status) => DioException(
      requestOptions: RequestOptions(path: '/users/me'),
      response: Response(requestOptions: RequestOptions(path: '/users/me'), statusCode: status),
      type: DioExceptionType.badResponse,
    );

DioException get _offline => DioException(
      requestOptions: RequestOptions(path: '/users/me'),
      type: DioExceptionType.connectionError,
    );

Future<(AuthNotifier, _Storage, _Repo)> _start({Object? profileError, bool cachedUser = true}) async {
  SharedPreferences.setMockInitialValues({
    'fresh_install_reset_done_v3': true,
    if (cachedUser) ...{
      AppConstants.keyUserId: 'u1',
      'user_name': 'Sayan',
      'user_phone': '9999999999',
    },
  });
  final prefs = await SharedPreferences.getInstance();
  final storage = _Storage(prefs: prefs)
    ..secure[AppConstants.keyAccessToken] = 'access-1'
    ..secure[AppConstants.keyRefreshToken] = 'refresh-1';
  final repo = _Repo(profileError: profileError);
  final notifier = AuthNotifier(repo, storage);
  await Future<void>.delayed(const Duration(milliseconds: 80)); // let _init finish
  return (notifier, storage, repo);
}

void main() {
  group('restoring the session at app start', () {
    test('a valid session opens signed in WITHOUT rotating the refresh token', () async {
      final (auth, storage, repo) = await _start();
      expect(auth.state, isA<AuthAuthenticated>());
      expect(repo.refreshCalls, 0, reason: 'rotating at every launch raced with the home requests and logged people out');
      expect(storage.secure[AppConstants.keyRefreshToken], 'refresh-1');
    });

    test('REGRESSION: no internet at launch keeps the user signed in (it used to show the login screen)', () async {
      final (auth, storage, _) = await _start(profileError: _offline);
      expect(auth.state, isA<AuthAuthenticated>());
      expect((auth.state as AuthAuthenticated).user.name, 'Sayan');
      expect(storage.secure[AppConstants.keyRefreshToken], 'refresh-1', reason: 'the saved login must survive a bad signal');
    });

    test('a server hiccup (500) also keeps the user signed in', () async {
      final (auth, storage, _) = await _start(profileError: _http(500));
      expect(auth.state, isA<AuthAuthenticated>());
      expect(storage.secure[AppConstants.keyAccessToken], 'access-1');
    });

    test('a definite rejection (401 after the refresh attempt failed) signs out and clears the tokens', () async {
      final (auth, storage, _) = await _start(profileError: _http(401));
      expect(auth.state, isA<AuthUnauthenticated>());
      expect(storage.secure, isEmpty);
    });

    test('offline with nothing cached falls back to the login screen (cannot invent a user)', () async {
      final (auth, _, _) = await _start(profileError: _offline, cachedUser: false);
      expect(auth.state, isA<AuthUnauthenticated>());
    });
  });
}
