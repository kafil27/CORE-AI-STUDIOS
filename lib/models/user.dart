class UserModel {
  final String uid;
  final String email;
  final String? name;
  final String? profilePicture;
  final DateTime signUpDate;
  final int tokens;

  UserModel({
    required this.uid,
    required this.email,
    this.name,
    this.profilePicture,
    required this.signUpDate,
    this.tokens = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'profilePicture': profilePicture,
      'signUpDate': signUpDate.toIso8601String(),
      'tokens': tokens,
    };
  }

  static UserModel fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'],
      email: map['email'],
      name: map['name'],
      profilePicture: map['profilePicture'],
      signUpDate: DateTime.parse(map['signUpDate']),
      tokens: map['tokens'],
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? name,
    String? profilePicture,
    DateTime? signUpDate,
    int? tokens,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      profilePicture: profilePicture ?? this.profilePicture,
      signUpDate: signUpDate ?? this.signUpDate,
      tokens: tokens ?? this.tokens,
    );
  }
} 