import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

class ChatService {
  Future<String> sendMessage(String message) async {
    try {
      final uri = Uri.parse("${ServerConfig.baseUrl}/api/chat");
      final body = {
        "messages": [
          {"role": "user", "content": message}
        ]
      };

      print("ChatService: Sending: $message");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        // Assume response is plain text or JSON with 'response' field.
        // Prompt says: "Display the response text from the server."
        // Let's assume it returns { "response": "Hello..." } or just text.
        // We'll try to parse JSON, fall back to body.
        try {
          final data = json.decode(response.body);
          return data['response'] ?? data['message'] ?? response.body; 
        } catch (_) {
          return response.body;
        }
      } else {
        return "Error: Server returned ${response.statusCode}";
      }
    } catch (e) {
      return "Error: $e";
    }
  }
}
