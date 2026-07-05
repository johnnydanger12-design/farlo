enum DataExportStatus { pending, processing, completed, failed, expired }

class DataExportRequest {
  const DataExportRequest({
    required this.id,
    required this.status,
    required this.requestedAt,
    this.completedAt,
    this.expiresAt,
    this.downloadUrl,
    this.errorMessage,
  });

  final String id;
  final DataExportStatus status;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final String? downloadUrl;
  final String? errorMessage;

  bool get isActive =>
      status == DataExportStatus.pending || status == DataExportStatus.processing;
  bool get isReady => status == DataExportStatus.completed && downloadUrl != null;

  factory DataExportRequest.fromMap(Map<String, dynamic> m) => DataExportRequest(
        id: m['id'] as String,
        status: _statusFromString(m['status'] as String),
        requestedAt: DateTime.parse(m['requested_at'] as String),
        completedAt: m['completed_at'] == null ? null : DateTime.parse(m['completed_at'] as String),
        expiresAt: m['expires_at'] == null ? null : DateTime.parse(m['expires_at'] as String),
        downloadUrl: m['download_url'] as String?,
        errorMessage: m['error_message'] as String?,
      );

  static DataExportStatus _statusFromString(String s) => switch (s) {
        'pending' => DataExportStatus.pending,
        'processing' => DataExportStatus.processing,
        'completed' => DataExportStatus.completed,
        'failed' => DataExportStatus.failed,
        _ => DataExportStatus.expired,
      };
}
