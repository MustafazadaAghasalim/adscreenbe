class ServerConfig {
  // Set to true for local development (Android Emulator uses 10.0.2.2)
  static const bool useLocal = false;
  
  // Local (Android Emulator): http://10.0.2.2:3000
  // Local (iOS Simulator): http://localhost:3000
  // Local (Physical Device via USB Debugging): http://127.0.0.1:3000 (Requires: adb reverse tcp:3000 tcp:3000)
  // Local (Physical Device via LAN): Use your computer's LAN IP (e.g., http://192.168.1.x:3000)
  // Production: https://adscreen.be
  static const String baseUrl = useLocal
      ? "http://10.0.2.2:3000" // Default for Emulator. Update this for physical devices.
      : "https://adscreen.be"; // Production URL

  static const String updateEndpoint = "$baseUrl/api/update_tablet_status";
  static const String adRetrievalEndpoint = "$baseUrl/api/get_ads_for_tablet";
  static const String healthCheckEndpoint = "$baseUrl/health";
  static const String socketServerUrl = baseUrl;
  static const String intruderAlertEndpoint = "$baseUrl/api/upload_intruder_alert";
  static const int updateIntervalSeconds = 30;
  static const String deviceSettingsEndpoint = "$baseUrl/api/admin/get_device_settings";

  // Module 1: backend JSON config polling
  static const String tabletConfigEndpoint = "$baseUrl/api/tablet/config";

  // Module 2: MQTT command bus
  static const String mqttHost = "adscreen.be";
  static const int mqttPort = 1883;
  static const String mqttUsername = "adscreen_tablet";
  static const String mqttPassword = "change-me-in-prod";
}
