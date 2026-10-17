// Dialogs used by the teacher screens. Kept in their own file so widget tests
// can open each one directly (test/dialogs_test.dart).
import 'package:flutter/material.dart';

import 'backend.dart';
import 'links.dart';
import 'youtube.dart';

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
    if (picked != null) {
      setState(() {
        _date = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _time = picked;
      });
    }
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
      setState(() {
        _error = error;
      });
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
                if (value != null) {
                  setState(() {
                    _batchId = value;
                  });
                }
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

/// Name + optional description (courses, batches). Returns
/// (name, description) or null.
///
/// The controllers live in [_TextFormDialog]'s State, so they are disposed
/// only after the dialog route has finished its exit animation and its
/// TextFields are gone. (Disposing them when the Future completes crashed with
/// "A TextEditingController was used after being disposed".)
Future<(String, String)?> showTextForm(
  BuildContext context, {
  required String title,
  required String nameLabel,
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (_) => _TextFormDialog(title: title, nameLabel: nameLabel),
  );
}

class _TextFormDialog extends StatefulWidget {
  const _TextFormDialog({required this.title, required this.nameLabel});

  final String title;
  final String nameLabel;

  @override
  State<_TextFormDialog> createState() => _TextFormDialogState();
}

class _TextFormDialogState extends State<_TextFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (_name.text.trim(), _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
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

/// One text field, e.g. a folder name. Returns the trimmed text or null.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, label: label, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
  });

  final String title;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        maxLength: 160,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Required' : null,
        onFieldSubmitted: (_) => _save(),
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

/// What the teacher typed when adding a PDF or a YouTube video.
class MaterialFormResult {
  const MaterialFormResult({
    required this.title,
    required this.description,
    required this.folderId,
    this.videoId,
  });

  final String title;
  final String description;

  /// null = not in a folder.
  final String? folderId;

  /// Set for videos only.
  final String? videoId;
}

/// Form for a new PDF ([isVideo] false) or YouTube video ([isVideo] true).
/// For videos, pasting a link fills the title from YouTube (via
/// [lookupTitle]) unless the teacher has already typed one.
Future<MaterialFormResult?> showMaterialForm(
  BuildContext context, {
  required bool isVideo,
  required List<MaterialFolder> folders,
  required String? initialFolderId,
  String initialTitle = '',
  YoutubeTitleLookup lookupTitle = fetchYoutubeTitle,
}) => showDialog<MaterialFormResult>(
  context: context,
  builder: (_) => _MaterialFormDialog(
    isVideo: isVideo,
    folders: folders,
    initialFolderId: initialFolderId,
    initialTitle: initialTitle,
    lookupTitle: lookupTitle,
  ),
);

class _MaterialFormDialog extends StatefulWidget {
  const _MaterialFormDialog({
    required this.isVideo,
    required this.folders,
    required this.initialFolderId,
    required this.initialTitle,
    required this.lookupTitle,
  });

  final bool isVideo;
  final List<MaterialFolder> folders;
  final String? initialFolderId;
  final String initialTitle;
  final YoutubeTitleLookup lookupTitle;

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initialTitle);
  final _link = TextEditingController();
  final _description = TextEditingController();
  late String? _folderId = widget.initialFolderId;
  String? _videoId;
  String? _autoTitle;
  bool _lookingUp = false;
  bool _lookupFailed = false;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _linkChanged(String value) async {
    final id = youtubeVideoId(value);
    if (id == _videoId) return;
    setState(() {
      _videoId = id;
      _lookupFailed = false;
      _lookingUp = id != null;
    });
    if (id == null) return;
    final title = await widget.lookupTitle(id);
    if (!mounted || id != _videoId) return;
    setState(() {
      _lookingUp = false;
      _lookupFailed = title == null;
      // Only overwrite a title the teacher has not edited.
      final current = _title.text.trim();
      if (title != null && (current.isEmpty || current == _autoTitle)) {
        _title.text = title;
        _autoTitle = title;
      }
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MaterialFormResult(
        title: _title.text.trim(),
        description: _description.text.trim(),
        folderId: _folderId,
        videoId: widget.isVideo ? _videoId : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoId = _videoId;
    return AlertDialog(
      title: Text(widget.isVideo ? 'Add a YouTube video' : 'Add PDF notes'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isVideo)
                TextFormField(
                  controller: _link,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'YouTube link (Unlisted is fine)',
                  ),
                  onChanged: _linkChanged,
                  validator: (value) => youtubeVideoId(value ?? '') == null
                      ? 'Paste a YouTube video link'
                      : null,
                ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isVideo && videoId != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: VideoThumbnail(videoId: videoId, width: 96),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextFormField(
                      controller: _title,
                      autofocus: !widget.isVideo,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: widget.isVideo
                            ? 'Video title'
                            : 'Title (e.g. Chapter 1 notes)',
                        helperText: _lookingUp
                            ? 'Getting the title from YouTube…'
                            : _lookupFailed
                            ? 'Could not get the title. Please type it.'
                            : null,
                        helperMaxLines: 2,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                ],
              ),
              if (widget.folders.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: _folderId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: [
                    for (final folder in widget.folders)
                      DropdownMenuItem(
                        value: folder.id,
                        child: Text(
                          folder.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No folder'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _folderId = value;
                    });
                  },
                ),
              TextField(
                controller: _description,
                maxLines: 2,
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
        FilledButton(
          onPressed: _save,
          child: Text(widget.isVideo ? 'Save' : 'Choose PDF'),
        ),
      ],
    );
  }
}

/// YouTube's own thumbnail for [videoId]; a plain icon if it cannot load.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({required this.videoId, this.width = 72, super.key});

  final String videoId;
  final double width;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: width,
      height: width * 9 / 16,
      child: Image.network(
        youtubeThumbnailUrl(videoId),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.smart_display),
        ),
      ),
    ),
  );
}

/// Where a material should go. [folderId] null = "No folder".
class FolderChoice {
  const FolderChoice(this.folderId);

  final String? folderId;
}

/// Lets the teacher pick another folder. null = cancelled.
Future<FolderChoice?> showMoveDialog(
  BuildContext context, {
  required List<MaterialFolder> folders,
  required String? currentFolderId,
}) => showDialog<FolderChoice>(
  context: context,
  builder: (dialogContext) => SimpleDialog(
    title: const Text('Move to folder'),
    children: [
      for (final folder in folders)
        SimpleDialogOption(
          onPressed: folder.id == currentFolderId
              ? null
              : () => Navigator.pop(dialogContext, FolderChoice(folder.id)),
          child: Text(
            folder.id == currentFolderId
                ? '${folder.title} (here now)'
                : folder.title,
          ),
        ),
      if (currentFolderId != null)
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(dialogContext, const FolderChoice(null)),
          child: const Text('No folder'),
        ),
      SimpleDialogOption(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cancel'),
      ),
    ],
  ),
);
