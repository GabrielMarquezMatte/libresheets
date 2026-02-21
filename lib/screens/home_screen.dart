import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:libresheets/services/database_helper.dart';
import 'package:libresheets/services/pdf_service.dart';
import 'package:pdfx/pdfx.dart';

import '../models/sheet.dart';
import '../services/sheet_service.dart';
import 'pdf_viewer_screen.dart';
import 'sheet_detail_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Sheet> _sheets = [];
  bool _loading = true;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadSheets();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSheets() async {
    final db = await DatabaseHelper.database;
    final sheets = _searchQuery.isEmpty
        ? await SheetService.getAllSheets(db)
        : await SheetService.searchSheets(db, _searchQuery);
    if (mounted) {
      setState(() {
        _sheets = sheets;
        _loading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) return;
    final singleFile = result.files.single;
    final fileName = singleFile.name;
    if (!kIsWeb) {
      final filePath = singleFile.path;
      if (filePath == null) return;
      await _openPdf(filePath, fileName);
      return;
    }
    final bytes = singleFile.bytes;
    if (bytes == null) return;
    await _openPdfWeb(bytes);
  }

  Future<void> _openPdfWeb(Uint8List bytes) async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final document = await PdfDocument.openData(bytes);
    final pdfService = PdfService(document);
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfService: pdfService)),
    );
  }

  Future<void> _openPdf(String path, String name) async {
    if (!await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File not found: $name'),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    await SheetService.upsertSheet(
      db,
      Sheet(name: name, path: path, lastOpened: now, createdAt: now),
    );

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final document = await PdfDocument.openFile(path);
    if (!mounted) return;
    final pdfService = PdfService(document);
    await navigator.push(
      MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfService: pdfService)),
    );
    await _loadSheets();
  }

  Future<void> _deleteSheet(Sheet sheet) async {
    if (sheet.id == null) return;
    final db = await DatabaseHelper.database;
    await SheetService.deleteSheet(db, sheet.id!);
    await _loadSheets();
  }

  Future<void> _editSheet(Sheet sheet) async {
    final updated = await showDialog<Sheet>(
      context: context,
      builder: (_) => SheetDetailDialog(sheet: sheet),
    );
    if (updated != null) {
      final db = await DatabaseHelper.database;
      await SheetService.updateSheet(db, updated);
      await _loadSheets();
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LibreSheets'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search sheets...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (query) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 300),
                  () {
                    _searchQuery = query;
                    _loadSheets();
                  },
                );
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sheets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_note_rounded,
                          size: 80, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No sheets yet'
                            : 'No results found',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to open a PDF',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _sheets.length,
                  itemBuilder: (context, index) {
                    final sheet = _sheets[index];
                    final sub = sheet.subtitle;
                    return Dismissible(
                      key: Key(sheet.path),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red[900],
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteSheet(sheet),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf,
                            color: Colors.redAccent, size: 36),
                        title:
                            Text(sheet.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          sub.isNotEmpty ? sub : _formatDate(sheet.lastOpened),
                          style: TextStyle(color: Colors.grey[500]),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          color: Colors.grey[500],
                          onPressed: () => _editSheet(sheet),
                          tooltip: 'Edit details',
                        ),
                        onTap: () => _openPdf(sheet.path, sheet.name),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        tooltip: 'Open PDF',
        child: const Icon(Icons.add),
      ),
    );
  }
}
