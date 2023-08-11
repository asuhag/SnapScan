import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart' as p;
import 'package:share_extend/share_extend.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
  int jpegCount = 0;
  String message = '';

  @override
  void initState() {
    super.initState();
    _updateJpegCount();
  }

  Future<void> _updateJpegCount() async {
    int count = await _getImageFileCount();
    setState(() {
      jpegCount = count;
    });
  }

  Future getImageAndScan() async {
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      imageFile = File(pickedFile.path);
      await Future.delayed(const Duration(seconds: 1));
      String? scannedResult = await scan();

      if (scannedResult != 'invalid_product') {
        await saveImageAndBarcode();
      } else if (scannedResult != 'invalid_product') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Barcode format is not supported, proceed with scanning next product'),
          duration: Duration(seconds: 1),
        ));
      }
    } else {
      print('No image selected.');
    }
  }

  Future<String?> scan() async {
    try {
      ScanResult scanResult = await BarcodeScanner.scan();

      // Verify if the code is EAN 8 or EAN 13
      RegExp exp = RegExp(r"^(?:\d{8}|\d{13})$");

      if (scanResult.rawContent.isNotEmpty &&
          exp.hasMatch(scanResult.rawContent)) {
        // Invalid EAN 8 or EAN 13 barcodes
        if ((scanResult.rawContent.length == 8 &&
                (scanResult.rawContent.startsWith('0') ||
                    scanResult.rawContent.startsWith('2'))) ||
            (scanResult.rawContent.length == 13 &&
                (scanResult.rawContent.startsWith('04') ||
                    scanResult.rawContent.startsWith('0')))) {
          setState(() {
            this.barcode = 'invalid_product';
            this.message =
                'Invalid barcode format. Proceed with scanning next product.';
          });
          return 'invalid_product';
        }
        // Valid EAN 8 or EAN 13 barcodes
        else {
          setState(() => this.barcode = scanResult.rawContent);
          return scanResult.rawContent;
        }
      }
      // If the barcode is neither EAN 8 nor EAN 13
      else if (!exp.hasMatch(scanResult.rawContent) &&
          scanResult.rawContent.isNotEmpty) {
        setState(() => this.barcode = 'invalid_product');
        return 'invalid_product';
      }
      // Other edge cases, such as user closing the scanner without scanning
      else {
        setState(() => this.barcode = '');
        return null;
      }
    } catch (e) {
      setState(() => this.barcode = '');
      print('Error scanning barcode: $e');
      return null;
    }
  }

  Future saveImageAndBarcode() async {
    // Request for storage permission

    if (await Permission.storage.request().isGranted) {
      // Continue with your function if permission is granted

      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String fileName;
      if (barcode.isEmpty) {
        fileName = "no_barcode_${timestamp}.jpeg";
      } /*else if (!barcode.isEmpty && barcode == 'invalid_product') {
        // If barcode is not empty and doesn't match EAN8 or EAN13, don't save the image
        fileName = "in_store_brand_${timestamp}_${barcode}.jpeg";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Barcode format is not supported, proceed with scanning next product'),
          duration: Duration(seconds: 1),
        ));
        print('Barcode format is not supported, image not saved.');
      }*/
      else {
        fileName = "${barcode}_number.jpeg";
      }

      final newFileName = "$path/$fileName";

      final compressedImage = await FlutterImageCompress.compressAndGetFile(
        imageFile!.path,
        newFileName,
        quality: 88,
      );

      if (compressedImage != null) {
        print('Compressed image saved to: ${compressedImage.path}');

        final result = await ImageGallerySaver.saveFile(compressedImage.path);
        print('Image saved to gallery: $result');

        imageFile = null;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Data saved to memory')));

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
          (Route<dynamic> route) => false,
        );
        _updateJpegCount();
      } else {
        print('Failed to compress image');
      }
    } else {
      print('Storage permission is not granted');
    }
  }

  Future<int> _getImageFileCount() async {
    final directory = await getApplicationDocumentsDirectory();

    final files = directory.listSync();

    int jpegCount =
        files.where((file) => p.extension(file.path) == '.jpeg').length;

    return jpegCount;
  }

  Future<void> deleteAllFiles() async {
    final directory = await getApplicationDocumentsDirectory();

    final files = directory.listSync();

    for (FileSystemEntity file in files) {
      if (file is File) {
        await file.delete();
      }
    }

    _updateJpegCount();
    print('All files deleted');
  }

  Future shareImagesAndBarcodes() async {
    Archive archive = Archive();

    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;

    final files = directory.listSync();

    for (FileSystemEntity file in files) {
      if (file is File && p.extension(file.path) == '.jpeg') {
        List<int> fileBytes = await file.readAsBytes();
        String filePathInArchive = file.path.substring(path.length);
        archive.addFile(
            ArchiveFile(filePathInArchive, fileBytes.length, fileBytes));
      }
    }

    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);

    final zipPath = p.join(path, '${DateTime.now().toIso8601String()}.zip');
    final zipFile = File(zipPath);

    if (zipData != null) {
      zipFile.writeAsBytesSync(zipData);
      ShareExtend.share(zipFile.path, "file");
    } else {
      print('Error: zipData is null');
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
            SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            Text('Number of images in app folder: $jpegCount'),
            ElevatedButton(
              onPressed: getImageAndScan,
              child: Text('Take Image of Front & Scan barcode'),
            ),
            /*ElevatedButton(
              onPressed: saveImageAndBarcode,
              child: Text('Save Image & Barcode'),
            ),*/
            ElevatedButton(
              onPressed: shareImagesAndBarcodes,
              child: Text('Share Images and Barcodes'),
            ),
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Confirmation'),
                      content:
                          Text('Are you sure you want to delete all images?'),
                      actions: <Widget>[
                        TextButton(
                          child: Text('Cancel'),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        TextButton(
                          child: Text('Yes'),
                          onPressed: () {
                            deleteAllFiles();
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
              },
              child: Text('Delete All Images'),
            ),
          ],
        ),
      ),
    );
  }
}
