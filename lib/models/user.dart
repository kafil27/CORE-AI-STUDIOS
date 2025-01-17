class UserModel {
  final String uid;
  final String email;
  final String? name;
  final String? profilePicture;
  final int tokens;
  final DateTime signUpDate;

  UserModel({
    required this.uid,
    required this.email,
    this.name,
    this.profilePicture,
    required this.tokens,
    required this.signUpDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'profilePicture': profilePicture,
      'tokens': tokens,
      'signUpDate': signUpDate.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'],
      profilePicture: map['profilePicture'],
      tokens: map['tokens'] ?? 0,
      signUpDate: map['signUpDate'] != null 
          ? DateTime.parse(map['signUpDate']) 
          : DateTime.now(),
    );
  }
} 