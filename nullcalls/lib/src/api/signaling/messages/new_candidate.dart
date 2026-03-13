class NewCandidate {
  final String candidate;

  const NewCandidate({required this.candidate});

  factory NewCandidate.fromJson(Map<String, dynamic> json) {
    return NewCandidate(
      candidate: json['candidate'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'candidate': candidate,
    };
  }
}
