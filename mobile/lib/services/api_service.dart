import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/poll_model.dart';

class ApiConfig {
  static const _configuredBase = String.fromEnvironment('FASTPOLL_API_BASE');
  static String get baseUrl => _configuredBase.isNotEmpty
      ? _configuredBase
      : Platform.isAndroid
      ? 'http://10.0.2.2:8000'
      : 'http://localhost:8000';
}

class ApiFailure implements Exception {
  ApiFailure(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

// Scoped by server as well as code so development servers never share credentials.
class SessionStore {
  static String _key(String code) => 'room:${ApiConfig.baseUrl}:$code';
  static Future<RoomSession?> read(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(code));
    if (raw == null) return null;
    try {
      return RoomSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_key(code));
      return null;
    }
  }

  static Future<void> save(RoomSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(session.roomCode), jsonEncode(session.toJson()));
  }

  static Future<void> remove(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(code));
  }
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    RoomSession? session,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${ApiConfig.baseUrl}$path'),
    );
    request.headers['Content-Type'] = 'application/json';
    if (session != null) {
      request.headers['Authorization'] = 'Bearer ${session.token}';
    }
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 12));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      final detail = json['detail'];
      throw ApiFailure(
        detail is String
            ? detail
            : 'Please check your name, topic, and options.',
        response.statusCode,
      );
    }
    return json;
  }

  Future<RoomSession> enter({
    required String name,
    String? code,
    void Function(String)? onProgress,
  }) async {
    onProgress?.call("Checking your saved room session…");
    final saved = code == null ? null : await SessionStore.read(code);
    try {
      onProgress?.call(
        code == null ? 'Creating your room…' : 'Joining your room…',
      );
      final json = await _request(
        'POST',
        code == null ? '/api/rooms' : '/api/rooms/$code/join',
        body: {'name': name, if (saved != null) 'session_token': saved.token},
      );
      final session = RoomSession.fromJson(json);
      onProgress?.call('Saving your place in the room…');
      await SessionStore.save(session);
      return session;
    } on ApiFailure catch (error) {
      if (code != null && (error.status == 401 || error.status == 404)) {
        await SessionStore.remove(code);
      }
      rethrow;
    }
  }

  Future<void> createPoll(
    RoomSession session, {
    required String topic,
    required List<String> options,
    required int duration,
  }) async {
    await _request(
      'POST',
      '/api/rooms/${session.roomCode}/polls',
      session: session,
      body: {'topic': topic, 'options': options, 'duration': duration},
    );
  }

  Future<void> setOpen(RoomSession session, bool open) async {
    await _request(
      'PATCH',
      '/api/rooms/${session.roomCode}',
      session: session,
      body: {'is_open': open},
    );
  }

  Future<void> closePoll(RoomSession session, String pollId) async {
    await _request(
      'POST',
      '/api/rooms/${session.roomCode}/polls/$pollId/close',
      session: session,
    );
  }

  void close() => _client.close();
}

class RoomSocket {
  RoomSocket(this.session);
  final RoomSession session;
  final _events = StreamController<Map<String, dynamic>>();
  Stream<Map<String, dynamic>> get events => _events.stream;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  void _emit(Map<String, dynamic> event) {
    if (!_closed) _events.add(event);
  }

  Future<void> connect() async {
    if (_closed) return;
    _emit({'event': 'CONNECTING', 'message': 'Connecting to your room…'});
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse(
          '${ApiConfig.baseUrl.replaceFirst('http', 'ws')}/ws/${session.roomCode}',
        ),
      );
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _subscription = channel.stream.listen(
        (raw) {
          try {
            final event = jsonDecode(raw as String) as Map<String, dynamic>;
            if (event['event'] == 'STATE_UPDATE') _attempt = 0;
            _emit(event);
          } catch (_) {
            _emit({
              'event': 'ERROR',
              'message': 'Could not read the room update.',
            });
          }
        },
        onError: (Object error) {
          /* onDone schedules a single retry */
        },
        onDone: () {
          if (_closed) return;
          if (channel.closeCode == 4401 || channel.closeCode == 4404) {
            _emit({
              'event': 'SESSION_ENDED',
              'message': 'This room session has ended. Go back and join again.',
            });
          } else {
            _scheduleRetry();
          }
        },
      );
      _emit({'event': 'CONNECTING', 'message': 'Joining the live lobby…'});
      channel.sink.add(jsonEncode({'session_token': session.token}));
    } catch (_) {
      unawaited(_channel?.sink.close());
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_closed || (_retry?.isActive ?? false)) return;
    final delay = [1, 2, 4, 8, 15][_attempt.clamp(0, 4)];
    _emit({
      'event': 'CONNECTING',
      'message': 'Connection interrupted. Trying again in ${delay}s…',
    });
    _attempt++;
    _retry = Timer(Duration(seconds: delay), () {
      unawaited(connect());
    });
  }

  void vote(String pollId, int option) => _channel?.sink.add(
    jsonEncode({'action': 'CAST_VOTE', 'poll_id': pollId, 'option_id': option}),
  );
  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _events.close();
  }
}
