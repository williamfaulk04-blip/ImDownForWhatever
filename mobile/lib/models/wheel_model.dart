class WheelActivity {
  WheelActivity.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String;

  final String id;
  final String name;
}

class WheelCategory {
  WheelCategory.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      activities = (json['activities'] as List)
          .map((item) => WheelActivity.fromJson(item as Map<String, dynamic>))
          .toList();

  final String id;
  final String name;
  final List<WheelActivity> activities;
}

class WheelState {
  WheelState.fromJson(Map<String, dynamic>? json)
    : spinId = json?['spin_id'] as String?,
      phase = json?['phase'] as String?,
      selectedCategoryId = json?['selected_category_id'] as String?,
      selectedActivityId = json?['selected_activity_id'] as String?,
      result = json?['result'] as String?,
      status = json?['status'] as String? ?? 'idle';

  final String? spinId;
  final String? phase;
  final String? selectedCategoryId;
  final String? selectedActivityId;
  final String? result;
  final String status;
}
