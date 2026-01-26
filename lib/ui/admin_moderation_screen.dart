import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'phone_auth_dialog.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  User? _currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    _currentUser = _auth.currentUser;
    if (_currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final docSnap = await _firestore.collection('users').doc(_currentUser!.uid).get();
    if (docSnap.exists) {
      if (mounted) {
        setState(() {
          _userData = docSnap.data();
          _isLoading = false;
        });
      }
    } else {
      // User exists in Auth but not Firestore? Create default
       if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void _loginSuccess() {
    _checkUserStatus();
  }

  Future<void> _updateStatus(String uid, String newStatus) async {
    if (newStatus == 'banned') {
       // Ideally delete or ban
       await _firestore.collection('users').doc(uid).delete();
    } else {
       await _firestore.collection('users').doc(uid).update({'status': newStatus});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 1. Not Logged In
    if (_currentUser == null) {
      return Scaffold(
        body: Stack(
          children: [
             // Background Image or Gradient
             Container(color: Colors.black87),
             Center(
               child: ElevatedButton(
                 child: const Text("Login with Phone"),
                 onPressed: () {
                   showDialog(
                     context: context,
                     builder: (_) => PhoneAuthDialog(onSuccess: _loginSuccess),
                   );
                 },
               ),
             ),
          ],
        ),
      );
    }

    final role = _userData?['role'] ?? 'driver';
    final status = _userData?['status'] ?? 'pending';
    
    // 2. Pending Approval
    if (status == 'pending' && role != 'admin') {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_empty, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              Text(
                "Wait for Approval",
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Your account is pending review by an Administrator."),
              ),
              ElevatedButton(
                onPressed: () => _auth.signOut().then((_) => _checkUserStatus()),
                child: const Text("Sign Out"),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Admin Dashboard (If blocked or not admin, show access denied actually, but code above handles pending)
    if (role != 'admin') {
       return const Scaffold(body: Center(child: Text("Access Denied: Drivers use the Kiosk App.")));
    }

    // 4. Admin View - Moderation List
    return Scaffold(
      appBar: AppBar(
        title: const Text("Moderation Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _auth.signOut().then((_) => _checkUserStatus()),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No pending requests."));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final uid = docs[index].id;
              final email = data['email'] ?? 'No Email';
              final phone = data['phone'] ?? 'No Phone';

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(email),
                  subtitle: Text(phone),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _updateStatus(uid, 'active'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.block, color: Colors.red),
                        onPressed: () => _updateStatus(uid, 'banned'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
