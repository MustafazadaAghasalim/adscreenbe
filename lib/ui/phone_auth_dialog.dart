import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pinput/pinput.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PhoneAuthDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  
  const PhoneAuthDialog({super.key, required this.onSuccess});

  @override
  State<PhoneAuthDialog> createState() => _PhoneAuthDialogState();
}

class _PhoneAuthDialogState extends State<PhoneAuthDialog> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String _phoneNumber = '';
  String _verificationId = '';
  bool _codeSent = false;
  String? _smsCode;
  bool _isLoading = false;

  void _verifyPhone() async {
    setState(() => _isLoading = true);
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: _phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification Failed: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _isLoading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error: $e");
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      UserCredential userCred = await _auth.signInWithCredential(credential);
      await _checkAndCreateUser(userCred.user);
      widget.onSuccess();
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Failed: $e')),
      );
    }
  }

  Future<void> _verifyCode() async {
    if (_smsCode == null || _smsCode!.length < 6) return;
    setState(() => _isLoading = true);
    
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: _smsCode!,
    );
    await _signInWithCredential(credential);
  }

  Future<void> _checkAndCreateUser(User? user) async {
    if (user == null) return;
    
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnap = await docRef.get();

    if (!docSnap.exists) {
      // New User Logic
      final role = (user.email == 'neapqlmg@gmail.com') ? 'admin' : 'driver';
      final status = (role == 'admin') ? 'active' : 'pending';

      await docRef.set({
        'uid': user.uid,
        'phone': user.phoneNumber,
        'email': user.email, // Might be null for phone auth
        'role': role,
        'status': status,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Glassmorphism Style
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.white.withOpacity(0.1),
        shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.4),
                Colors.white.withOpacity(0.1),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Phone Verification",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              if (!_codeSent) ...[
                IntlPhoneField(
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(),
                    ),
                    filled: true,
                    fillColor: Colors.white10,
                  ),
                  initialCountryCode: 'BE', // Default to Belgium
                  style: const TextStyle(color: Colors.white),
                  dropdownTextStyle: const TextStyle(color: Colors.white),
                  onChanged: (phone) {
                    _phoneNumber = phone.completeNumber;
                  },
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _verifyPhone,
                        child: const Text("Send SMS Code"),
                      ),
              ] else ...[
                 Pinput(
                   length: 6,
                   onCompleted: (pin) {
                     _smsCode = pin;
                     _verifyCode();
                   },
                   defaultPinTheme: PinTheme(
                     width: 56,
                     height: 56,
                     textStyle: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600),
                     decoration: BoxDecoration(
                       border: Border.all(color: Colors.white30),
                       borderRadius: BorderRadius.circular(20),
                       color: Colors.white10,
                     ),
                   ),
                 ),
                 const SizedBox(height: 20),
                 _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _verifyCode,
                        child: const Text("Verify & Login"),
                      ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
