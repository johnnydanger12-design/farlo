class PosIntegration {
  const PosIntegration({
    required this.provider,
    required this.externalMerchantId,
    required this.environment,
    required this.enabled,
    this.cloverOrderTypeId,
    this.cloverEmployeeId,
    this.squareLocationId,
  });

  factory PosIntegration.fromMap(Map<String, dynamic> map) {
    return PosIntegration(
      provider: map['provider'] as String,
      externalMerchantId: map['external_merchant_id'] as String,
      environment: map['environment'] as String,
      enabled: map['enabled'] as bool,
      cloverOrderTypeId: map['clover_order_type_id'] as String?,
      cloverEmployeeId: map['clover_employee_id'] as String?,
      squareLocationId: map['square_location_id'] as String?,
    );
  }

  final String provider;
  final String externalMerchantId;
  final String environment;
  final bool enabled;
  final String? cloverOrderTypeId;
  final String? cloverEmployeeId;
  final String? squareLocationId;

  String get providerLabel {
    switch (provider) {
      case 'clover':
        return 'Clover';
      case 'square':
        return 'Square';
      default:
        return provider;
    }
  }
}
