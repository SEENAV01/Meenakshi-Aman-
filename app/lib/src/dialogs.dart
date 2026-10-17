// Dialogs used by the teacher screens. Kept in their own file so widget tests
// can open each one directly (test/dialogs_test.dart).
import 'package:flutter/material.dart';

import 'backend.dart';
import 'links.dart';

class LiveClassInput {
  const LiveClassInput({
    required this.batchId,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.meetingUrl,
  });

  final String batchId;
  final String title;
  final String description;
  final DateTime startsAt;
  final String meetingUrl;
}

class ScheduleClassDialog extends StatefulWidget {
  const ScheduleClassDialog({required this.batches, super.key});

  final List<LearningBatch> batches;

  @override
  State<ScheduleClassDialog> createState() => _ScheduleClassDialogState();
}

class _ScheduleClassDialogState extends State<ScheduleClassDialog> {
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _description = TextEditingController();
  late String _batchId = widget.batches.first.id;
  DateTime? _date;
  TimeOfDay? _time;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final date = _date;
    final time = _time;
    String? error;
    if (_title.text.trim().isEmpty) {
      error = 'Enter a class title.';
    } else if (!isMeetingUrl(_link.text)) {
      error = 'Paste a Google Meet or Zoom link starting with https://';
    } else if (date == null || time == null) {
      error = 'Choose the date and time.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      LiveClassInput(
        batchId: _batchId,
        title: _title.text.trim(),
        description: _description.text.trim(),
        startsAt: DateTime(
          date!.year,
          date.month,
          date.day,
          time!.hour,
          time.minute,
        ),
        meetingUrl: _link.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: const Text('Schedule live class'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _batchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Batch'),
              items: [
                for (final batch in widget.batches)
                  DropdownMenuItem(
                    value: batch.id,
                    child: Text(
                      '${batch.courseTitle} · ${batch.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _batchId = value);
              },
            ),
            TextField(
              controller: _title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Class title'),
            ),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Google Meet or Zoom link',
                hintText: 'https://meet.google.com/...',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _date == null
                          ? 'Date'
                          : localizations.formatShortDate(_date!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      _time == null
                          ? 'Time'
                          : localizations.formatTimeOfDay(_time!),
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note for students (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Returns (name, description, link). The link field is shown only when
/// [linkLabel] is given.
///
/// The controllers live in [_TextFormDialog]'s State, so they are disposed
/// only after the dialog route has finished its exit animation and its
/// TextFields are gone. (Disposing them when the Future completes crashed with
/// "A TextEditingController was used after being disposed".)
Future<(String, String, String)?> showTextForm(
  BuildContext context, {
  required String title,
  required String nameLabel,
  String? linkLabel,
  String? Function(String value)? linkValidator,
}) {
  return showDialog<(String, String, String)>(
    context: context,
    builder: (_) => _TextFormDialog(
      title: title,
      nameLabel: nameLabel,
      linkLabel: linkLabel,
      linkValidator: linkValidator,
    ),
  );
}

class _TextFormDialog extends StatefulWidget {
  const _TextFormDialog({
    required this.title,
    required this.nameLabel,
    this.linkLabel,
    this.linkValidator,
  });

  final String title;
  final String nameLabel;
  final String? linkLabel;
  final String? Function(String value)? linkValidator;

  @override
  State<_TextFormDialog> createState() => _TextFormDialogState();
}

class _TextFormDialogState extends State<_TextFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _link = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (
      _name.text.trim(),
      _description.text.trim(),
      _link.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final linkLabel = widget.linkLabel;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 200,
                decoration: InputDecoration(labelText: widget.nameLabel),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              if (linkLabel != null)
                TextFormField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(labelText: linkLabel),
                  validator: (value) => widget.linkValidator?.call(value ?? ''),
                ),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String detail,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(detail),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}
