const _unchangedTarget = Object();

/// Display calibration is separate from slide typography. A null target is an
/// explicitly windowed rehearsal, never a request to choose another monitor.
class OutputProfile {
  const OutputProfile({
    required this.id,
    required this.name,
    this.displayId,
    this.scale = 1,
    this.safeInset = 0,
  });

  static const version = 1;
  final String id;
  final String name;
  final String? displayId;
  final double scale;
  final double safeInset;

  bool get isRehearsal => displayId == null;
  double get effectiveScale => scale * (1 - 2 * safeInset);

  void validate({bool allowEmptyName = false}) {
    if (id.trim().isEmpty || id.length > 200) {
      throw const FormatException('Output profile needs a valid identifier.');
    }
    if ((!allowEmptyName && name.trim().isEmpty) || name.length > 120) {
      throw const FormatException(
        'Name the output profile using 1–120 characters.',
      );
    }
    if (displayId != null &&
        (displayId!.trim().isEmpty || displayId!.length > 1000)) {
      throw const FormatException(
        'Choose an available display or windowed rehearsal.',
      );
    }
    if (!scale.isFinite ||
        scale < .75 ||
        scale > 1 ||
        !safeInset.isFinite ||
        safeInset < 0 ||
        safeInset > .12) {
      throw const FormatException(
        'Output scale must be 75–100% and safe inset 0–12%.',
      );
    }
  }

  OutputProfile copyWith({
    String? id,
    String? name,
    Object? displayId = _unchangedTarget,
    double? scale,
    double? safeInset,
  }) => OutputProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    displayId: identical(displayId, _unchangedTarget)
        ? this.displayId
        : displayId as String?,
    scale: scale ?? this.scale,
    safeInset: safeInset ?? this.safeInset,
  );

  Map<String, Object?> toMap() => {
    'version': version,
    'id': id,
    'name': name,
    'displayId': displayId,
    'scale': scale,
    'safeInset': safeInset,
  };

  factory OutputProfile.fromMap(Map<String, Object?> map) {
    if (map['version'] != version) {
      throw const FormatException('Unsupported output profile version.');
    }
    if (map['id'] is! String ||
        map['name'] is! String ||
        (map['displayId'] != null && map['displayId'] is! String) ||
        (map['scale'] != null && map['scale'] is! num) ||
        (map['safeInset'] != null && map['safeInset'] is! num)) {
      throw const FormatException('Invalid output profile fields.');
    }
    final profile = OutputProfile(
      id: map['id']! as String,
      name: map['name']! as String,
      displayId: map['displayId'] as String?,
      scale: (map['scale'] as num?)?.toDouble() ?? 1,
      safeInset: (map['safeInset'] as num?)?.toDouble() ?? 0,
    );
    profile.validate();
    return profile;
  }

  @override
  bool operator ==(Object other) =>
      other is OutputProfile &&
      id == other.id &&
      name == other.name &&
      displayId == other.displayId &&
      scale == other.scale &&
      safeInset == other.safeInset;

  @override
  int get hashCode => Object.hash(id, name, displayId, scale, safeInset);
}
