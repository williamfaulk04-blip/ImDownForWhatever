class PollOption {
  const PollOption({required this.id, required this.text, required this.votes});

  final int id;
  final String text;
  final int votes;

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
    id: json['id'] as int,
    text: json['text'] as String,
    votes: json['votes'] as int,
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'votes': votes};
}

class PollState {
  const PollState({
    required this.roomCode,
    required this.topic,
    required this.status,
    required this.timeLeft,
    required this.options,
  });

  final String roomCode;
  final String topic;
  final String status;
  final int timeLeft;
  final List<PollOption> options;

  factory PollState.fromJson(Map<String, dynamic> json) => PollState(
    roomCode: json['room_code'] as String,
    topic: json['topic'] as String,
    status: json['status'] as String,
    timeLeft: json['time_left'] as int,
    options: (json['options'] as List<dynamic>)
        .map((option) => PollOption.fromJson(option as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'room_code': roomCode,
    'topic': topic,
    'status': status,
    'time_left': timeLeft,
    'options': options.map((option) => option.toJson()).toList(),
  };

  PollState copyWith({int? timeLeft, String? status}) => PollState(
    roomCode: roomCode,
    topic: topic,
    status: status ?? this.status,
    timeLeft: timeLeft ?? this.timeLeft,
    options: options,
  );
}
