/// True only after Purchases.configure() has successfully run.
/// Guards every Purchases.* call — the native SDK throws a Swift fatalError
/// (uncatchable by Dart) if any method is called before configure().
bool rcConfigured = false;
