/// The face-scan profile.
///
/// Deliberately tiny: gender is the only thing this app asks for, it is
/// optional, and it is never read by the geometry, scoring or feedback code.
/// Height, weight, age and BMI used to live here and have moved to the separate
/// BMI Calculator (`lib/core/bmi.dart`), which stores nothing.
///
/// Nothing here reaches the network; the app has no accounts or uploads.
class UserProfile {
  const UserProfile({this.gender});

  /// Null means "not answered", which is different from "prefer not to say".
  final Gender? gender;

  bool get isEmpty => gender == null;

  Map<String, Object?> toJson() => <String, Object?>{'gender': gender?.name};

  /// Reads only the gender. Older files also carried age, height, weight and
  /// BMI; those keys are ignored here so an old profile still opens, and the
  /// body-composition fields stop being carried forward.
  static UserProfile? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Gender? gender = genderFromName(json['gender']);
    if (gender == null) {
      return null;
    }
    return UserProfile(gender: gender);
  }

  @override
  String toString() => 'UserProfile(gender: ${gender?.name ?? 'not answered'})';
}

/// The four options the onboarding offers, in order.
///
/// "Another identity / prefer to self-describe" is one option because the app
/// does not need a free-text identity to draw a face outline; "Prefer not to
/// say" is separate because it is an answer, not a blank.
enum Gender {
  male('Male'),
  female('Female'),
  selfDescribe('Another identity / prefer to self-describe'),
  preferNotToSay('Prefer not to say');

  const Gender(this.label);

  final String label;
}

/// Maps a stored name back to a value. Unknown or retired names return null
/// rather than being guessed.
Gender? genderFromName(Object? name) {
  if (name is! String) {
    return null;
  }
  for (final Gender gender in Gender.values) {
    if (gender.name == name) {
      return gender;
    }
  }
  return null;
}
