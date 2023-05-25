import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart';
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

  // Context
  late BuildContext myContext;

  @override
  void initState() {
    super.initState();
    initDb();
  }

  Future<void> initDb() async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'app_database.db');
    db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      await db.execute(
        'CREATE TABLE Images (id INTEGER PRIMARY KEY, image TEXT, barcode TEXT)',
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
        await db.insert(
            'Images', {'image': result['filePath'], 'barcode': barcode});
        print('Image saved to gallery: $result');
        showDialog(
          context: myContext,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Data Saved'),
              content: Text('Data saved to memory'),
              actions: <Widget>[
                TextButton(
                  child: Text('Close'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => HomePage()),
                    );
                  },
                ),
              ],
            );
          },
        );
      } else {
        print('Failed to compress image');
      }
    } else {
      print('Storage permission is not granted');
    }
  }

  Future shareImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;

    List<String> imagePaths = [];
    final dir = Directory(path);
    if (dir.existsSync()) {
      dir.listSync().forEach((file) {
        if (file is File && basename(file.path).contains('.jpg')) {
          imagePaths.add(file.path);
        }
      });
    }

    if (imagePaths.isNotEmpty) {
      ShareExtend.shareMultiple(imagePaths, "image");
    } else {
      print('No images found');
    }
  }

  Future shareBarcodes() async {
    List<Map> list = await db.rawQuery('SELECT * FROM Images');
    List<String> barcodes = [];
    for (var item in list) {
      barcodes.add(item['barcode']);
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
  }

  @override
  Widget build(BuildContext context) {
    myContext = context;
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
              onPressed: shareImages,
              child: Text('Share Images'),
            ),
            ElevatedButton(
              onPressed: shareBarcodes,
              child: Text('Share Barcodes'),
            ),
          ],
        ),
      ),
    );
  }
}
