/// App Configuration - Development vs Production
class AppConfig {
  /// Debug mode - development'ta true, production'ta false
  static const bool debugMode = bool.fromEnvironment('DEBUG_MODE', defaultValue: false);
  
  /// Verbose logging - performance troubleshooting için
  static const bool verboseLogging = debugMode && false; // false by default
}
