import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String barcode = '';
  File? imageFile;
  final picker = ImagePicker();

  Future getImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      imageFile = File(pickedFile.path);
      setState(() {});
    } else {
      print('No image selected.');
    }
  }

  Future scan() async {
    try {
      ScanResult scanResult = await BarcodeScanner.scan();
      setState(() => this.barcode = scanResult.rawContent);
    } catch (e) {
      setState(() => this.barcode = 'Unknown error: $e');
    }
  }

  Future saveImageAndBarcode() async {
    if (await Permission.storage.request().isGranted) {
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;
      final newFileName = "$path/$barcode.jpg";

      // Compress image and save it as new file
      final compressedImage = await FlutterImageCompress.compressAndGetFile(
        imageFile!.path,
        newFileName,
        quality: 88,
      );

      if (compressedImage != null) {
        print('Compressed image saved to: ${compressedImage.path}');

        // Save compressed image to gallery
        final result = await ImageGallerySaver.saveFile(compressedImage.path);
        print('Image saved to gallery: $result');
      } else {
        print('Failed to compress image');
      }
    } else {
      print('Storage permission is not granted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Product Scanner'),
      ),
      body: Center(
        child: ListView(
          children: <Widget>[
            imageFile != null
                ? Image.file(imageFile!)
                : Text('No image selected.'),
            Text('Barcode: $barcode'),
            ElevatedButton(
              onPressed: getImage,
              child: Text('Take Image of Front'),
            ),
            ElevatedButton(
              onPressed: scan,
              child: Text('Scan Barcode'),
            ),
            ElevatedButton(
              onPressed: saveImageAndBarcode,
              child: Text('Save Image & Barcode'),
            ),
          ],
        ),
      ),
    );
  }
}
