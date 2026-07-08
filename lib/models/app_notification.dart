class AppNotification {
  final String? id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final String? createdAt;

  const AppNotification({
    this.id,
    this.type = '',
    this.title = '',
    this.message = '',
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> data, {String? id}) {
    return AppNotification(
      id: id ?? data['id'],
      type: data['type'] ?? '',
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      isRead: data['isRead'] ?? false,
      createdAt: data['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'title': title,
      'message': message,
      'isRead': isRead,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
