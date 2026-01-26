import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart'; // Better for general files

class AdUploaderView extends StatefulWidget {
  const AdUploaderView({super.key});

  @override
  State<AdUploaderView> createState() => _AdUploaderViewState();
}

class _AdUploaderViewState extends State<AdUploaderView> {
  bool _uploading = false;
  String? _statusMessage;

  Future<void> _pickAndUpload() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: false,
      );

      if (result != null) {
        Uint8List? fileBytes = result.files.first.bytes;
        String fileName = result.files.first.name;
        
        if (fileBytes == null) return;

        setState(() {
          _uploading = true;
          _statusMessage = "Uploading $fileName...";
        });

        // 1. Upload to Storage
        final storageRef = FirebaseStorage.instance.ref().child('ads/$fileName');
        final uploadTask = storageRef.putData(fileBytes); // putData for Web/Bytes

        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();

        // 2. Save Metadata to Firestore
        await FirebaseFirestore.instance.collection('ads').add({
          'name': fileName,
          'url': downloadUrl,
          'type': _getFileType(fileName),
          'uploaded_at': FieldValue.serverTimestamp(),
          'active': true,
        });

        setState(() {
          _uploading = false;
          _statusMessage = "Upload Successful!";
        });
      }
    } catch (e) {
      setState(() {
        _uploading = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  String _getFileType(String name) {
    if (name.endsWith('.mp4')) return 'video';
    return 'image';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_upload, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 16),
              const Text(
                'Upload New Ad',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Supports Images and MP4 Videos'),
              const SizedBox(height: 24),
              if (_uploading) 
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Select File'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(_statusMessage!, style: const TextStyle(color: Colors.green)),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
