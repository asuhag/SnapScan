import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart' as p;
import 'package:share_extend/share_extend.dart';
import 'package:sqflite/sqflite.dart';

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

  // Database reference
  late Database db;

  @override
  void initState() {
    super.initState();
    initDb();
  }

  Future<void> initDb() async {
    var databasesPath = await getDatabasesPath();
    String path = p.join(databasesPath, 'app_database.db');
    db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      await db.execute(
        'CREATE TABLE Images (id INTEGER PRIMARY KEY, image TEXT, barcode TEXT, timestamp TEXT)',
      );
    });
  }

  Future getImageAndScan() async {
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      imageFile = File(pickedFile.path);
      // Add delay before scanning
      await Future.delayed(const Duration(seconds: 1));
      await scan();
      setState(() {});
    } else {
      print('No image selected.');
    }
  }

  Future scan() async {
    try {
      ScanResult scanResult = await BarcodeScanner.scan();

      // Check if scanResult.rawContent is not empty and then set it as barcode
      if (scanResult.rawContent.isNotEmpty) {
        setState(() => this.barcode = scanResult.rawContent);
      } else {
        // If scanResult.rawContent is empty, set barcode to be empty as well
        setState(() => this.barcode = '');
      }
    } catch (e) {
      setState(() => this.barcode = '');
      print('Error scanning barcode: $e');
    }
  }

  Future saveImageAndBarcode() async {
    if (await Permission.storage.request().isGranted) {
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;

      // Create a filename based on barcode availability
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String fileName;
      if (barcode.isEmpty || barcode == 'Unknown error') {
        fileName = "no_barcode_${timestamp}.jpeg";
      } else {
        fileName = "${barcode}_number.jpeg";
      }

      final newFileName = "$path/$fileName";

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
        await db.insert('Images', {
          'image': compressedImage.path,
          'barcode': barcode,
          'timestamp': DateTime.now().toIso8601String()
        });
        print('Image saved to gallery: $result');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Data saved to memory')));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
        );
      } else {
        print('Failed to compress image');
      }
    } else {
      print('Storage permission is not granted');
    }
  }

  /*Future shareImages() async {
    List<Map> list = (await db.rawQuery('SELECT * FROM Images')).toList();
    list.sort((a, b) => DateTime.parse(b['timestamp'])
        .compareTo(DateTime.parse(a['timestamp'])));
    List<String> sortedImagePaths = [];

    for (var item in list) {
      if (item['image'] != null) {
        File tempFile = File(item['image']);
        if (tempFile.existsSync()) {
          sortedImagePaths.add(item['image']);
        }
      }
    }

    if (sortedImagePaths.isNotEmpty) {
      ShareExtend.shareMultiple(sortedImagePaths, "image");
    } else {
      print('No images found');
    }
  }

  Future shareBarcodes() async {
    List<Map<String, dynamic>> resultList =
        await db.rawQuery('SELECT * FROM Images');
    List<Map<String, dynamic>> list =
        List<Map<String, dynamic>>.from(resultList);

    list.sort((a, b) => DateTime.parse(b['timestamp'])
        .compareTo(DateTime.parse(a['timestamp'])));

    List<String> barcodes = [];
    for (var item in list) {
      barcodes.add(item['barcode'].toString());
    }

    if (barcodes.isNotEmpty) {
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;
      final barcodeFile = File('$path/barcodes.txt');
      await barcodeFile.writeAsString(barcodes.join('\n'));
      ShareExtend.share(barcodeFile.path, "file");
    } else {
      print('No barcodes found');
    }
  } */

  Future<void> deleteAllFiles() async {
    final directory = await getApplicationDocumentsDirectory();

    // List all files in the directory
    final files = directory.listSync();

    // For each file in the directory, delete it
    for (FileSystemEntity file in files) {
      if (file is File) {
        await file.delete();
      }
    }

    print('All files deleted');
  }

  Future shareImagesAndBarcodes() async {
    // Initialize an Archive object to store our files
    Archive archive = Archive();

    // Get the directory
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;

    // List all files in the directory
    final files = directory.listSync();

    // For each file in the directory, add it to the archive
    for (FileSystemEntity file in files) {
      if (file is File && p.extension(file.path) == '.jpeg') {
        List<int>? fileBytes = file.readAsBytesSync();
        if (fileBytes != null) {
          String filePathInArchive = file.path.substring(path.length);
          archive.addFile(
              ArchiveFile(filePathInArchive, fileBytes.length, fileBytes));
        }
      }
    }

    // Encode the archive as a ZIP file
    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);

    // Save the ZIP file to disk
    final zipPath = p.join(path, '${DateTime.now().toIso8601String()}.zip');
    final zipFile = File(zipPath);

    // Write bytes to file, null check on zipData is included
    if (zipData != null) {
      zipFile.writeAsBytesSync(zipData);
      // Share the zip file
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
            ElevatedButton(
              onPressed: getImageAndScan,
              child: Text('Take Image of Front & Scan barcode'),
            ),
            ElevatedButton(
              onPressed: saveImageAndBarcode,
              child: Text('Save Image & Barcode'),
            ),
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
