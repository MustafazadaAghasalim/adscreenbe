# Clerk Authentication for Flutter/Android

This guide shows how to integrate Clerk authentication into your Flutter Android application.

## 📱 Important Note

**Clerk does not have an official Flutter SDK yet.** However, you can integrate Clerk into your Flutter app using one of these approaches:

### Option 1: WebView Integration (Recommended for Quick Setup)
Use Clerk's hosted authentication pages in a WebView.

### Option 2: REST API Integration (More Control)
Use Clerk's REST API directly with HTTP requests.

### Option 3: Custom Auth with Clerk Backend
Use your Next.js backend (with Clerk) as the auth provider for your Flutter app.

---

## 🚀 Approach 1: WebView Integration

### Step 1: Add Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  webview_flutter: ^4.4.0
  shared_preferences: ^2.2.2
  http: ^1.1.0
```

Run:
```bash
flutter pub get
```

### Step 2: Create Clerk WebView Service

Create `lib/services/clerk_auth_service.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClerkAuthService {
  static const String _tokenKey = 'clerk_session_token';
  
  // Your Clerk Frontend API URL
  static const String clerkFrontendApi = 'YOUR_CLERK_FRONTEND_API';
  
  Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }
  
  Future<void> saveSessionToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }
  
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
  
  Future<bool> isAuthenticated() async {
    final token = await getSessionToken();
    return token != null && token.isNotEmpty;
  }
}

class ClerkSignInScreen extends StatefulWidget {
  const ClerkSignInScreen({Key? key}) : super(key: key);

  @override
  State<ClerkSignInScreen> createState() => _ClerkSignInScreenState();
}

class _ClerkSignInScreenState extends State<ClerkSignInScreen> {
  late final WebViewController _controller;
  final ClerkAuthService _authService = ClerkAuthService();

  @override
  void initState() {
    super.initState();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            // Extract session token from cookies or URL
            final cookies = await _controller.runJavaScriptReturningResult(
              'document.cookie',
            );
            
            // Parse and save the session token
            // This is a simplified example
            if (cookies.toString().contains('__session')) {
              await _authService.saveSessionToken(cookies.toString());
              if (mounted) {
                Navigator.of(context).pop(true);
              }
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://your-clerk-app.clerk.accounts.dev/sign-in'),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In'),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
```

---

## 🔧 Approach 2: REST API Integration

### Step 1: Add HTTP Package

Already in your `pubspec.yaml`:
```yaml
dependencies:
  http: ^1.1.0
  shared_preferences: ^2.2.2
```

### Step 2: Create Clerk API Service

Create `lib/services/clerk_api_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ClerkApiService {
  static const String baseUrl = 'https://api.clerk.com/v1';
  static const String publishableKey = 'YOUR_PUBLISHABLE_KEY';
  static const String secretKey = 'YOUR_SECRET_KEY'; // ⚠️ Never expose in production!
  
  static const String _sessionTokenKey = 'clerk_session_token';
  static const String _userIdKey = 'clerk_user_id';

  // Sign in with email and password
  Future<Map<String, dynamic>?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/client/sign_ins'),
        headers: {
          'Authorization': 'Bearer $publishableKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'identifier': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data);
        return data;
      }
      return null;
    } catch (e) {
      print('Sign in error: $e');
      return null;
    }
  }

  // Sign up with email and password
  Future<Map<String, dynamic>?> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/client/sign_ups'),
        headers: {
          'Authorization': 'Bearer $publishableKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email_address': email,
          'password': password,
          'first_name': firstName,
          'last_name': lastName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }
      return null;
    } catch (e) {
      print('Sign up error: $e');
      return null;
    }
  }

  // Get current user
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final sessionToken = await getSessionToken();
    if (sessionToken == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/me'),
        headers: {
          'Authorization': 'Bearer $sessionToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Get user error: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_userIdKey);
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getSessionToken();
    return token != null && token.isNotEmpty;
  }

  // Private helper methods
  Future<void> _saveSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (data['client']?['sessions']?.isNotEmpty == true) {
      final session = data['client']['sessions'][0];
      await prefs.setString(_sessionTokenKey, session['id']);
      await prefs.setString(_userIdKey, session['user']['id']);
    }
  }

  Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenKey);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }
}
```

### Step 3: Create Sign In Screen

Create `lib/screens/sign_in_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../services/clerk_api_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({Key? key}) : super(key: key);

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _clerkService = ClerkApiService();
  bool _isLoading = false;

  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);

    final result = await _clerkService.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (result != null && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignIn,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Sign In'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
```

---

## 🌐 Approach 3: Use Next.js Backend (Recommended)

This is the **most secure** approach. Your Flutter app communicates with your Next.js backend, which handles Clerk authentication.

### Backend Setup (Next.js)

Create `app/api/auth/verify/route.ts`:

```typescript
import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";

export async function GET() {
  const { userId } = await auth();
  
  if (!userId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  
  return NextResponse.json({ userId, authenticated: true });
}
```

Create `app/api/auth/session/route.ts`:

```typescript
import { auth, currentUser } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";

export async function GET() {
  const { userId } = await auth();
  const user = await currentUser();
  
  if (!userId || !user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  
  return NextResponse.json({
    userId: user.id,
    email: user.emailAddresses[0]?.emailAddress,
    firstName: user.firstName,
    lastName: user.lastName,
  });
}
```

### Flutter Setup

Create `lib/services/backend_auth_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BackendAuthService {
  static const String backendUrl = 'https://your-nextjs-app.vercel.app';
  static const String _sessionTokenKey = 'session_token';

  Future<Map<String, dynamic>?> verifySession(String sessionToken) async {
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/api/auth/session'),
        headers: {
          'Authorization': 'Bearer $sessionToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Verify session error: $e');
      return null;
    }
  }

  Future<void> saveSessionToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
  }

  Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getSessionToken();
    if (token == null) return false;
    
    final user = await verifySession(token);
    return user != null;
  }
}
```

---

## ⚠️ Security Best Practices

### 1. **Never Expose Secret Keys in Flutter**
```dart
// ❌ WRONG - Never do this
static const String secretKey = 'sk_test_xxxxx';
```

### 2. **Use Backend for Sensitive Operations**
Always verify authentication on your backend, not just in the Flutter app.

### 3. **Secure Token Storage**
Use `flutter_secure_storage` instead of `shared_preferences` for production:

```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
```

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const storage = FlutterSecureStorage();

// Save
await storage.write(key: 'session_token', value: token);

// Read
final token = await storage.read(key: 'session_token');
```

---

## 📚 Recommended Approach

For your Adscreen project, I recommend **Approach 3** (Next.js Backend):

1. ✅ Most secure (secret keys stay on server)
2. ✅ Centralized authentication logic
3. ✅ Easy to maintain
4. ✅ Works with your existing Next.js app
5. ✅ Can share user sessions across web and mobile

---

## 🚀 Next Steps

1. Choose your integration approach
2. Set up the necessary services in your Flutter app
3. Create sign-in/sign-up UI screens
4. Test authentication flow
5. Implement secure token storage
6. Add error handling and loading states

---

## 📖 Resources

- [Clerk Documentation](https://clerk.com/docs)
- [Clerk REST API](https://clerk.com/docs/reference/backend-api)
- [Flutter WebView](https://pub.dev/packages/webview_flutter)
- [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)
