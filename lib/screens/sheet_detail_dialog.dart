import 'package:flutter/material.dart';
import '../models/sheet.dart';

class SheetDetailDialog extends StatefulWidget {
  final Sheet sheet;

  const SheetDetailDialog({super.key, required this.sheet});

  @override
  State<SheetDetailDialog> createState() => _SheetDetailDialogState();
}

class _SheetDetailDialogState extends State<SheetDetailDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _composerController;
  late final TextEditingController _arrangerController;
  late final TextEditingController _genreController;
  late final TextEditingController _periodController;
  late final TextEditingController _keyController;
  late final TextEditingController _difficultyController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final sheet = widget.sheet;
    _nameController = TextEditingController(text: sheet.name);
    _composerController = TextEditingController(text: sheet.composer ?? '');
    _arrangerController = TextEditingController(text: sheet.arranger ?? '');
    _genreController = TextEditingController(text: sheet.genre ?? '');
    _periodController = TextEditingController(text: sheet.period ?? '');
    _keyController = TextEditingController(text: sheet.key ?? '');
    _difficultyController = TextEditingController(text: sheet.difficulty ?? '');
    _notesController = TextEditingController(text: sheet.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _composerController.dispose();
    _arrangerController.dispose();
    _genreController.dispose();
    _periodController.dispose();
    _keyController.dispose();
    _difficultyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sheet Details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_nameController, 'Title', Icons.title),
            _field(_composerController, 'Composer', Icons.person),
            _field(_arrangerController, 'Arranger', Icons.edit),
            _field(_genreController, 'Genre', Icons.category),
            _field(_periodController, 'Period', Icons.history),
            _field(_keyController, 'Key', Icons.music_note),
            _field(_difficultyController, 'Difficulty', Icons.bar_chart),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final trimmedName = _nameController.text.trim();
            final updated = widget.sheet.copyWith(
              name: trimmedName.isNotEmpty ? trimmedName : widget.sheet.name,
              composer: _nonEmpty(_composerController.text),
              arranger: _nonEmpty(_arrangerController.text),
              genre: _nonEmpty(_genreController.text),
              period: _nonEmpty(_periodController.text),
              key: _nonEmpty(_keyController.text),
              difficulty: _nonEmpty(_difficultyController.text),
              notes: _nonEmpty(_notesController.text),
            );
            Navigator.of(context).pop(updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Widget _field(
  TextEditingController controller,
  String label,
  IconData icon,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
