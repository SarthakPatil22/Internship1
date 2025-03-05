import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Transformation',
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isProcessing = false;
  bool _cameraClosed = false;
  Uint8List? _transformedImageBytes;

  @override
  void initState() {
    super.initState();
    // Choose the front camera if available; otherwise, use the first camera.
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _controller = CameraController(frontCamera, ResolutionPreset.medium);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    if (!_cameraClosed) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _captureAndTransform() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Capture image from the camera
      final image = await _controller.takePicture();
      File imageFile = File(image.path);

      // Use the backend API endpoint
      var uri = Uri.parse("http://127.0.0.1:3000/upload-image");
      var request = http.MultipartRequest("POST", uri);
      request.files.add(await http.MultipartFile.fromPath("image", imageFile.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Dispose of the camera once the image is captured and processed.
        await _controller.dispose();
        setState(() {
          _transformedImageBytes = response.bodyBytes;
          _isProcessing = false;
          _cameraClosed = true;
        });
      } else {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: ${response.statusCode}")));
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Image Transformation")),
      body: _cameraClosed ? _buildTransformedImageView() : _buildCameraPreview(),
    );
  }

  Widget _buildCameraPreview() {
    if (!_controller.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(child: CameraPreview(_controller)),
        if (_isProcessing)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text("Processing image..."),
                CircularProgressIndicator(),
              ],
            ),
          ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isProcessing ? null : _captureAndTransform,
          child: Text("Capture and Transform"),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTransformedImageView() {
    return Center(
      child: _transformedImageBytes != null
          ? Container(
              padding: EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 2.0),
              ),
              child: Image.memory(_transformedImageBytes!),
            )
          : Text("No transformed image available"),
    );
  }
}
