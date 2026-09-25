class RoomSession {
  const RoomSession({
    required this.roomCode,
    required this.token,
    required this.name,
  });
  final String roomCode;
  final String token;
  final String name;
  factory RoomSession.fromJson(Map<String, dynamic> json) => RoomSession(
    roomCode: json['room_code'] as String,
    token: json['session_token'] as String,
    name: json['name'] as String,
  );
  Map<String, dynamic> toJson() => {
    'room_code': roomCode,
    'session_token': token,
    'name': name,
  };
}

class Participant {
  Participant.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      isHost = json['is_host'] as bool,
      online = json['online'] as bool;
  final String name;
  final bool isHost;
  final bool online;
}

class PollOption {
  PollOption.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      text = json['text'] as String,
      votes = json['votes'] as int;
  final int id;
  final String text;
  final int votes;
}

class PollState {
  PollState.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      topic = json['topic'] as String,
      status = json['status'] as String,
      timeLeft = json['time_left'] as int,
      selectedOption = json['selected_option'] as int?,
      winnerIds = (json['winner_ids'] as List).cast<int>(),
      options = (json['options'] as List)
          .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
          .toList();
  final String id;
  final String topic;
  final String status;
  final int timeLeft;
  final int? selectedOption;
  final List<int> winnerIds;
  final List<PollOption> options;
  int get totalVotes =>
      options.fold(0, (total, option) => total + option.votes);
  String get result {
    if (winnerIds.isEmpty) return 'No votes this round';
    final names = options
        .where((o) => winnerIds.contains(o.id))
        .map((o) => o.text)
        .join(' & ');
    return winnerIds.length == 1 ? 'Winner: $names' : 'It’s a tie: $names';
  }
}

class RoomState {
  RoomState.fromJson(Map<String, dynamic> json)
    : isHost = json['is_host'] as bool,
      isOpen = json['is_open'] as bool,
      participants = (json['participants'] as List)
          .map((p) => Participant.fromJson(p as Map<String, dynamic>))
          .toList(),
      poll = json['poll'] == null
          ? null
          : PollState.fromJson(json['poll'] as Map<String, dynamic>);
  final bool isHost;
  final bool isOpen;
  final List<Participant> participants;
  final PollState? poll;
}
