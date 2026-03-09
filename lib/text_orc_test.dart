import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextRecognitionPage extends StatefulWidget {
  const TextRecognitionPage({super.key});

  @override
  State<TextRecognitionPage> createState() => _TextRecognitionPageState();
}

class _TextRecognitionPageState extends State<TextRecognitionPage> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  File? _imageFile;
  String _resultText = '';
  bool _isProcessing = false;

  Future<void> _pickImageAndReadText() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() {
      _imageFile = File(file.path);
      _resultText = '';
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      setState(() {
        _resultText = recognizedText.text;
      });
    } catch (e) {
      setState(() {
        _resultText = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ML Kit Text Recognition')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _isProcessing ? null : _pickImageAndReadText,
              child: const Text('เลือกรูปภาพ'),
            ),
            const SizedBox(height: 16),
            if (_imageFile != null)
              Image.file(_imageFile!, height: 220, fit: BoxFit.contain),
            const SizedBox(height: 16),
            if (_isProcessing) const CircularProgressIndicator(),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _resultText.isEmpty ? 'ยังไม่มีผลลัพธ์' : _resultText,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
