/// A single historical weight entry, optionally with a progress picture and description
class WeightRecord {
  final String id;
  final DateTime date;
  final double weightKg;
  final String? progressPictureBase64; 
  final String? description;           

  const WeightRecord({
    required this.id,
    required this.date,
    required this.weightKg,
    this.progressPictureBase64,
    this.description,
  });

  /// BMI for this specific record, given the user's (largely static)
  /// height. Returns null if height is missing or non-positive — callers
  /// must handle that as an empty state, never as 0 or NaN.
  double? bmiGiven(double? heightCm) {
    if (heightCm == null || heightCm <= 0) return null;
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  factory WeightRecord.fromMap(String id, Map<String, dynamic> map) {
    return WeightRecord(
      id: id,
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 0.0,
      progressPictureBase64: map['progressPictureBase64'] as String?,
      description: map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'weightKg': weightKg,
      'progressPictureBase64': progressPictureBase64,
      'description': description,
    };
  }

  WeightRecord copyWith({
    DateTime? date,
    double? weightKg,
    String? progressPictureBase64,
    bool clearProgressPicture = false,
    String? description,
    bool clearDescription = false,
  }) {
    return WeightRecord(
      id: id,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
      progressPictureBase64: clearProgressPicture
          ? null
          : (progressPictureBase64 ?? this.progressPictureBase64),
      description: clearDescription ? null : (description ?? this.description),
    );
  }
}