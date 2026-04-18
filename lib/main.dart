import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

final GlobalKey previewKey = GlobalKey();
String? savedFileName;
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class FrameConfig {
  final String asset;
  final EdgeInsets padding;
  final double rotation; // derajat kemiringan
  final double borderRadius; // sudut foto
  final double scale; // 🔥 tambahan

  FrameConfig({
    required this.asset,
    required this.padding,
    this.rotation = 0, // default lurus
    this.borderRadius = 12, // default sudut halus
    this.scale = 0, // default normal
  });
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> pickMultiple(BuildContext context) async {
    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultiImage();

    if (files.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MultiEditPage(files: files)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => pickMultiple(context),
          child: const Text("Pilih  Foto"),
        ),
      ),
    );
  }
}

class MultiEditPage extends StatefulWidget {
  final List<XFile> files;

  const MultiEditPage({super.key, required this.files});

  @override
  State<MultiEditPage> createState() => _MultiEditPageState();
}

class _MultiEditPageState extends State<MultiEditPage>
    with TickerProviderStateMixin {
  List<Uint8List?> editedImages = [];
  int rows = 2;
  final int cols = 2;
  late List<int?> photoboxSlots;
  Uint8List? frameBytes;
  late TabController _tabController;
  int selectedFrameIndex = 0;
  List<String> frameNames = ["Frame 1", "Frame 2", "Frame 3", "No Frame"];
  int totalSlots = 2;

  double getScale(FrameConfig frame) {
    if (totalSlots == 6) return 1.0;
    if (totalSlots == 4) return 1.30;
    if (totalSlots == 2) return 0.95;
    return frame.scale;
  }

  List<FrameConfig> frames = [
    FrameConfig(
      asset: "assets/frame1.png",
      padding: EdgeInsets.fromLTRB(23, 10, 23, 40),
      borderRadius: 3,
      scale: 1,
    ),

    FrameConfig(
      asset: "assets/frame2.png",
      padding: EdgeInsets.fromLTRB(12, 15, 12, 15),
      borderRadius: 1,
    ),
    FrameConfig(
      asset: "assets/frame3.png",
      padding: EdgeInsets.fromLTRB(35, 25, 35, 25),
      borderRadius: 4,
    ),

    FrameConfig(asset: "", padding: EdgeInsets.zero, scale: 0),
  ];
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    editedImages = List.filled(widget.files.length, null);
    photoboxSlots = List.filled(rows * cols, null);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void changeGrid(int value) {
    setState(() {
      totalSlots = value;
      photoboxSlots = List.filled(totalSlots, null);
    });
  }

  void changeFrame(int frameIndex) {
    log("ganti frame ke index $frameIndex");
    setState(() {
      selectedFrameIndex = frameIndex;
      if (frameIndex == 3) {
        frameBytes = null;
      } else {
        // Load frame dari assets sesuai index
        loadFrameByIndex(frameIndex);
      }
    });
  }

  Future<Uint8List> generateFinalImage() async {
    RenderRepaintBoundary boundary =
        previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  String? savedFileName;

  Future<void> savePhotobox() async {
    try {
      final fileName = "PB_${DateTime.now().millisecondsSinceEpoch}";

      final bytes = await generateFinalImage();

      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        name: fileName,
        quality: 100,
      );

      log("Save result: $result");

      setState(() {
        savedFileName = fileName;
      });

      showBarcodeDialog(fileName);
    } catch (e) {
      log("Error save: $e");
    }
  }

  Future<void> loadFrameByIndex(int index) async {
    log("masuk frame");
    try {
      log("coba load frame index $index");
      final frameName = "assets/frame${index + 1}.png";
      final data = await rootBundle.load(frameName);
      setState(() {
        frameBytes = data.buffer.asUint8List();
      });
    } catch (e) {
      log("gagal load frame index $index, error: $e");
      // Fallback: coba load frame.png
    }
  }

  void openEditor(int index) {
    final file = widget.files[index];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProImageEditor.file(
          File(file.path),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              setState(() {
                editedImages[index] = bytes;
              });
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Widget buildCenterSlot(int index) {
    return Expanded(
      child: DragTarget<int>(
        onAccept: (sourceIndex) {
          setState(() {
            photoboxSlots[index] = sourceIndex;
          });
        },
        builder: (context, candidateData, rejectedData) {
          final imageIndex = photoboxSlots[index];
          final isHighlighted = candidateData.isNotEmpty;
          return buildSlot(index, isHighlighted, imageIndex);
        },
      ),
    );
  }

  Widget buildSlot(int slotIndex, bool isHighlighted, int? imageIndex) {
    final frame = frames[selectedFrameIndex];
    return AspectRatio(
      aspectRatio: 1,
      child: Center(
        child: Transform.scale(
          scale: getScale(frame),
          child: Transform.rotate(
            angle: frame.rotation * 3.1416 / 180,
            child: Stack(
              children: [
                if (imageIndex != null)
                  Positioned.fill(
                    child: Padding(
                      padding: frame.padding,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(frame.borderRadius),
                        child: editedImages[imageIndex] != null
                            ? Image.memory(
                                editedImages[imageIndex]!,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(widget.files[imageIndex].path),
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Text(
                      "DROP\nHERE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                /// 🧾 FRAME
                if (frame.asset.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Image.asset(frame.asset, fit: BoxFit.fill),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void showBarcodeDialog(String data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.7),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🎮 Title
              Text(
                "🎮 SCAN",
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 16),

              // 🧾 Barcode Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: data,
                  width: 220,
                  height: 80,
                ),
              ),

              const SizedBox(height: 12),

              // 🆔 Code text
              Text(
                data,
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),

              const SizedBox(height: 20),

              // 🎯 Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "PLAY AGAIN",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildPreview() {
    return Column(
      children: [
        // Tab Bar
        Material(
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.blueAccent,
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: "Grid"),
              Tab(text: "Frame"),
            ],
          ),
        ),

        // Tab controls only
        SizedBox(
          height: 60,
          child: TabBarView(
            controller: _tabController,
            children: [_buildGridTab(), _buildFrameTab()],
          ),
        ),

        // 🔥 INI YANG DIUBAH
        Expanded(
          child: RepaintBoundary(key: previewKey, child: _buildPhotoboxGrid()),
        ),
      ],
    );
  }

  Widget _buildGridTab() {
    log(totalSlots.toString());
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildGridButton("2", 2, totalSlots == 2),
            const SizedBox(width: 8),
            _buildGridButton("2x4", 4, totalSlots == 4),
            const SizedBox(width: 8),
            _buildGridButton("2x6", 6, totalSlots == 6),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < frameNames.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  onPressed: () => changeFrame(i),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedFrameIndex == i
                        ? Colors.blueAccent
                        : Colors.grey[400],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    frameNames[i],
                    style: TextStyle(
                      color: selectedFrameIndex == i
                          ? Colors.white
                          : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoboxGrid() {
    if (totalSlots == 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 130),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: 2,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
            childAspectRatio: 1, 
          ),
          itemBuilder: (context, index) {
            return DragTarget<int>(
              onAccept: (sourceIndex) {
                setState(() {
                  photoboxSlots[index] = sourceIndex;
                });
              },
              builder: (context, candidateData, rejectedData) {
                final imageIndex = photoboxSlots[index];
                final isHighlighted = candidateData.isNotEmpty;

                return buildSlot(index, isHighlighted, imageIndex);
              },
            );
          },
        ),
      );
    }
    if (totalSlots == 6) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),

          shrinkWrap: true,
          itemCount: totalSlots,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1,
            crossAxisSpacing: 20,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            return DragTarget<int>(
              onAccept: (sourceIndex) {
                setState(() {
                  photoboxSlots[index] = sourceIndex;
                });
              },
              builder: (context, candidateData, rejectedData) {
                final imageIndex = photoboxSlots[index];
                final isHighlighted = candidateData.isNotEmpty;

                return buildSlot(index, isHighlighted, imageIndex);
              },
            );
          },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: GridView.builder(
        itemCount: totalSlots,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 40,
          mainAxisSpacing: 40,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          return DragTarget<int>(
            onAccept: (sourceIndex) {
              setState(() {
                photoboxSlots[index] = sourceIndex;
              });
            },
            builder: (context, candidateData, rejectedData) {
              final imageIndex = photoboxSlots[index];
              final isHighlighted = candidateData.isNotEmpty;

              return buildSlot(index, isHighlighted, imageIndex);
            },
          );
        },
      ),
    );
  }

  Widget _buildGridButton(String label, int value, bool isSelected) {
    return ElevatedButton(
      onPressed: () => changeGrid(value),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blueAccent : Colors.grey[400],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> printPhotobox() async {
    final selectedImages = <Uint8List>[];

    for (int? index in photoboxSlots) {
      if (index != null) {
        if (editedImages[index] != null) {
          selectedImages.add(editedImages[index]!);
        } else {
          final bytes = await widget.files[index].readAsBytes();
          selectedImages.add(bytes);
        }
      }
    }

    if (selectedImages.length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Minimal 4 slot terisi")));
      return;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(72 * 4, 72 * 10),
        build: (context) {
          return pw.Column(
            children: [
              for (int i = 0; i < selectedImages.length; i++)
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Stack(
                    children: [
                      pw.Image(
                        pw.MemoryImage(selectedImages[i]),
                        fit: pw.BoxFit.cover,
                      ),
                      if (frameBytes != null)
                        pw.Positioned.fill(
                          child: pw.Image(pw.MemoryImage(frameBytes!)),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Photobox Editor"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: savePhotobox,
              icon: const Icon(Icons.save),
              label: const Text("SAVE"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 4, child: buildPreview()),
          const Divider(),
          Expanded(
            flex: 1,
            child: GridView.builder(
              itemCount: widget.files.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                final file = widget.files[index];
                final edited = editedImages[index];

                return Draggable<int>(
                  data: index,
                  feedback: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: edited != null
                          ? Image.memory(edited, fit: BoxFit.cover)
                          : Image.file(File(file.path), fit: BoxFit.cover),
                    ),
                  ),
                  childWhenDragging: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => openEditor(index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: edited != null
                                ? Image.memory(edited, fit: BoxFit.cover)
                                : Image.file(
                                    File(file.path),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          if (edited != null)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
