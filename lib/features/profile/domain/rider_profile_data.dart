import 'dart:convert';
import 'dart:typed_data';

class RiderProfile {
  const RiderProfile({
    required this.fullName,
    required this.userName,
    required this.phoneNumber,
    this.email = '',
    this.photoBytes,
    this.hasCompletedPersonalInfo = false,
  });

  final String fullName;
  final String userName;
  final String phoneNumber;
  final String email;
  final Uint8List? photoBytes;
  final bool hasCompletedPersonalInfo;

  String get displayName {
    final name = fullName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return 'Rider';
  }

  /// First token of [fullName], used for greetings like "Good morning, James".
  String get firstName {
    final name = fullName.trim();
    if (name.isEmpty) {
      return 'Rider';
    }
    return name.split(RegExp(r'\s+')).first;
  }

  static String timeOfDayGreeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 17) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  String get displayUserName {
    final name = userName.trim().replaceFirst(RegExp(r'^@+'), '');
    if (name.isNotEmpty) {
      return name;
    }
    return 'rider';
  }

  RiderProfile copyWith({
    String? fullName,
    String? userName,
    String? phoneNumber,
    String? email,
    Uint8List? photoBytes,
    bool clearPhoto = false,
    bool? hasCompletedPersonalInfo,
  }) {
    return RiderProfile(
      fullName: fullName ?? this.fullName,
      userName: userName ?? this.userName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      photoBytes: clearPhoto ? null : photoBytes ?? this.photoBytes,
      hasCompletedPersonalInfo:
          hasCompletedPersonalInfo ?? this.hasCompletedPersonalInfo,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fullName': fullName,
      'userName': userName,
      'phoneNumber': phoneNumber,
      'email': email,
      'hasCompletedPersonalInfo': hasCompletedPersonalInfo,
      if (photoBytes != null) 'photoBase64': base64Encode(photoBytes!),
    };
  }

  factory RiderProfile.fromJson(Map<String, dynamic> json) {
    Uint8List? photo;
    final encoded = json['photoBase64'];
    if (encoded is String && encoded.isNotEmpty) {
      try {
        photo = base64Decode(encoded);
      } on Object {
        photo = null;
      }
    }

    return RiderProfile(
      fullName: (json['fullName'] as String?)?.trim() ?? '',
      userName: (json['userName'] as String?)?.trim() ?? '',
      phoneNumber: (json['phoneNumber'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim().toLowerCase() ?? '',
      photoBytes: photo,
      hasCompletedPersonalInfo: json['hasCompletedPersonalInfo'] == true,
    );
  }
}
