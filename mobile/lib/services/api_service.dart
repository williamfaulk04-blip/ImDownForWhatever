import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/poll_model.dart';

class ApiConfig {
  static const String _configuredBase = String.fromEnvironment(
    'FASTPOLL_API_BASE',
    defaultValue: '',
  );

  static String get baseUrl {
    if (_configuredBase.isNotEmpty) return _configuredBase;
    return Platform.isAndroid
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';
  }
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> createRoom({
    required String topic,
    required List<String> options,
    required int duration,
  }) async {
    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'topic': topic,
        'options': options,
        'duration': duration,
      }),
    );
    if (response.statusCode != 201) {
      throw HttpException('Could not create room (${response.statusCode})');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['room_code']
        as String;
  }

  void close() => _client.close();
}

class PollSocket {
  PollSocket({required String roomCode, required String clientId})
    : _channel = WebSocketChannel.connect(
        Uri.parse(
          '${ApiConfig.baseUrl.replaceFirst('http', 'ws')}/ws/$roomCode/$clientId',
        ),
      );

  final WebSocketChannel _channel;

  Stream<PollState> get states => _channel.stream.map((message) {
    final json = jsonDecode(message as String) as Map<String, dynamic>;
    if (json['event'] == 'ERROR') {
      throw StateError(json['message'] as String);
    }
    return PollState.fromJson(json);
  });

  void castVote(int optionId) {
    _channel.sink.add(
      jsonEncode({'action': 'CAST_VOTE', 'option_id': optionId}),
    );
  }

  Future<void> close() async => _channel.sink.close();
}
