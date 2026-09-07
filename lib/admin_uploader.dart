import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'grovio_shared.dart';

class BulkUploaderPage extends StatefulWidget {
  const BulkUploaderPage({super.key});

  @override
  State<BulkUploaderPage> createState() => _BulkUploaderPageState();
}

class _BulkUploaderPageState extends State<BulkUploaderPage> {
  bool _isUploading = false;
  String _status = "Select a CSV or TXT file to upload items";
  String? _fileName;
  Uint8List? _fileBytes;

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _fileName = file.name;
        _fileBytes = bytes;
        _status = "File selected: $_fileName. Click Upload to start.";
      });
    }
  }

  Future<void> _startUpload() async {
    if (_fileBytes == null) return;

    setState(() {
      _isUploading = true;
      _status = "Reading file and uploading...";
    });

    try {
      String content = utf8.decode(_fileBytes!);
      List<String> lines = content.split("\n");
      int startLine = 0;

      // Skip header if it exists
      if (lines.isNotEmpty &&
          (lines[0].toLowerCase().contains("id") ||
              lines[0].toLowerCase().contains("name"))) {
        startLine = 1;
      }

      int count = 0;
      for (int i = startLine; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;

        // Support both Commas (CSV) and Tabs
        List<String> cols;
        if (line.contains("\t")) {
          cols = line.split("\t");
        } else {
          cols = line.split(",");
        }

        if (cols.length < 8) continue;

        // Sequence: id, name, category, mrp, selling_price, unit, imageUrl, barcode, stockQty
        String id = cols[0].trim();
        String name = cols[1].trim();
        String category = cols[2].trim();
        double mrp = double.tryParse(cols[3].replaceAll("₹", "").trim()) ?? 0.0;
        double sellingPrice =
            double.tryParse(cols[4].replaceAll("₹", "").trim()) ?? 0.0;
        String unit = cols[5].trim();
        String imageUrl = cols[6].trim();
        String barcode = cols.length > 7 ? cols[7].trim() : "";
        int stockQty = cols.length > 8
            ? (int.tryParse(cols[8].trim()) ?? 10)
            : 10;

        final item = GroceryItem(
          id: id.isEmpty
              ? "item_${DateTime.now().millisecondsSinceEpoch}_$count"
              : id,
          names: {"en": name, "hi": name},
          category: category,
          price: sellingPrice,
          mrp: mrp,
          unit: unit,
          imageUrl: imageUrl,
          barcode: barcode,
          stockQty: stockQty,
          inStock: true,
        );

        await GrovioFirestore.placeCustomProduct(item);
        count++;
        setState(() {
          _status = "Uploading... ($count items)";
        });
      }

      setState(() {
        _isUploading = false;
        _status = "Successfully uploaded $count items!";
        _fileBytes = null;
        _fileName = null;
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _status = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Grovio File Manager")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(Icons.upload_file, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 30),
            if (!_isUploading) ...[
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_open),
                  label: Text(_fileName ?? "SELECT CSV FILE"),
                ),
              ),
              const SizedBox(height: 15),
              if (_fileBytes != null)
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _startUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("START UPLOAD TO FIREBASE"),
                  ),
                ),
            ] else
              const CircularProgressIndicator(),
            const Spacer(),
            const Text(
              "Format: id, name, category, mrp, price, unit, imageUrl, barcode, stock",
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
