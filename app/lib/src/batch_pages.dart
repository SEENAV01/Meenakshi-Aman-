part of 'app.dart';

// Batch → folders (chapters) → numbered materials.

class _BatchContent {
  const _BatchContent(this.folders, this.materials);

  final List<MaterialFolder> folders;
  final List<LearningMaterial> materials;

  List<LearningMaterial> inFolder(String? folderId) =>
      materials.where((m) => m.folderId == folderId).toList(growable: false);

  /// display_order for a new item at the end of [folderId].
  int nextOrder(String? folderId) => inFolder(folderId)
      .fold(0, (top, m) => m.displayOrder >= top ? m.displayOrder + 1 : top);
}

Future<_BatchContent> _loadBatch(GyanifyBackend backend, String batchId) async {
  final results = await Future.wait([
    backend.loadFolders(batchId),
    backend.loadMaterials(batchId),
  ]);
  return _BatchContent(
    results[0] as List<MaterialFolder>,
    results[1] as List<LearningMaterial>,
  );
}

String _batchLoadError(Object error, {required bool isTeacher}) =>
    error is SetupRequiredException && !isTeacher
    ? 'Your teacher is updating this class. Please try again later.'
    : 'Could not load this batch: ${_errorText(error)}';

/// Picks a PDF from the phone. Returns null if the teacher cancels.
Future<({String fileName, Uint8List bytes})?> _pickPdf() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (result.isEmpty) return null;
  final file = result.single;
  final fileLength = await file.length();
  if (fileLength == null) {
    throw StateError('The selected PDF size could not be read.');
  }
  if (fileLength > 20 * 1024 * 1024) {
    throw StateError('PDF must be 20 MB or smaller.');
  }
  if (!file.name.toLowerCase().endsWith('.pdf')) {
    throw StateError('Choose a PDF file.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw StateError('The selected file does not contain a valid PDF header.');
  }
  return (
    fileName: file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
    bytes: bytes,
  );
}

/// Shared "add PDF / add video" flow for the batch and folder pages.
/// Returns true when something was added.
Future<bool> _addMaterial(
  BuildContext context, {
  required GyanifyBackend backend,
  required LearningBatch batch,
  required _BatchContent content,
  required String? folderId,
  required bool isVideo,
  required YoutubeTitleLookup lookupTitle,
}) async {
  try {
    ({String fileName, Uint8List bytes})? pdf;
    if (!isVideo) {
      pdf = await _pickPdf();
      if (pdf == null) return false;
    }
    if (!context.mounted) return false;
    final input = await showMaterialForm(
      context,
      isVideo: isVideo,
      folders: content.folders,
      initialFolderId: folderId,
      initialTitle: pdf == null
          ? ''
          : pdf.fileName
                .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
                .replaceAll('_', ' ')
                .trim(),
      lookupTitle: lookupTitle,
    );
    if (input == null) return false;
    final order = content.nextOrder(input.folderId);
    if (pdf != null) {
      await backend.uploadPdf(
        batchId: batch.id,
        title: input.title,
        description: input.description,
        fileName: pdf.fileName,
        bytes: pdf.bytes,
        folderId: input.folderId,
        displayOrder: order,
      );
    } else {
      await backend.addVideo(
        batchId: batch.id,
        title: input.title,
        description: input.description,
        youtubeUrl: canonicalYoutubeUrl(input.videoId!),
        folderId: input.folderId,
        displayOrder: order,
      );
    }
    if (context.mounted) {
      _showMessage(context, isVideo ? 'Video added.' : 'PDF uploaded.');
    }
    return true;
  } catch (error) {
    if (context.mounted) _showMessage(context, _errorText(error));
    return false;
  }
}

/// Two 40px buttons stacked (80px; a _RowCard grows to fit).
final _arrowStyle = IconButton.styleFrom(
  minimumSize: const Size(40, 40),
  maximumSize: const Size(40, 40),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// A card row: leading, title/subtitle, trailing. Unlike ListTile it lets
/// the trailing widget be taller than 56px (the stacked up/down buttons).
class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up / down arrows used to reorder folders and materials.
class _MoveButtons extends StatelessWidget {
  const _MoveButtons({required this.onUp, required this.onDown});

  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Move up',
        style: _arrowStyle,
        onPressed: onUp,
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        tooltip: 'Move down',
        style: _arrowStyle,
        onPressed: onDown,
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
    ],
  );
}

List<T> _swapped<T>(List<T> items, int a, int b) {
  final copy = List.of(items);
  final tmp = copy[a];
  copy[a] = copy[b];
  copy[b] = tmp;
  return copy;
}

/// First screen of a batch: its folders (chapters) in the teacher's order.
class BatchPage extends StatefulWidget {
  const BatchPage({
    required this.backend,
    required this.batch,
    required this.isTeacher,
    this.lookupTitle = fetchYoutubeTitle,
    super.key,
  });

  final GyanifyBackend backend;
  final LearningBatch batch;
  final bool isTeacher;
  final YoutubeTitleLookup lookupTitle;

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  late Future<_BatchContent> _content = _loadBatch(
    widget.backend,
    widget.batch.id,
  );

  /// Back from the background: show what changed meanwhile.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _content = _loadBatch(widget.backend, widget.batch.id);
    });
    await _settle(_content);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      await _refresh();
      if (mounted && done != null) _showMessage(context, done);
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  Future<void> _newFolder(_BatchContent content) async {
    final name = await showNameDialog(
      context,
      title: 'New folder',
      label: 'Folder name (e.g. Chapter 1 – Greetings)',
    );
    if (name == null) return;
    await _run(
      () => widget.backend.createFolder(
        batchId: widget.batch.id,
        title: name,
        displayOrder: content.folders.isEmpty
            ? 0
            : content.folders.last.displayOrder + 1,
      ),
    );
  }

  Future<void> _rename(MaterialFolder folder) async {
    final name = await showNameDialog(
      context,
      title: 'Rename folder',
      label: 'Folder name',
      initial: folder.title,
    );
    if (name == null || name == folder.title) return;
    await _run(() => widget.backend.renameFolder(folder.id, name));
  }

  Future<void> _delete(_BatchContent content, MaterialFolder folder) async {
    final count = content.inFolder(folder.id).length;
    if (count > 0) {
      _showMessage(
        context,
        '"${folder.title}" still has $count item${count == 1 ? '' : 's'}. '
        'Move or delete them first.',
      );
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this folder?',
      detail: '"${folder.title}" is empty and will be removed.',
    );
    if (!confirmed) return;
    await _run(() => widget.backend.deleteFolder(folder.id));
  }

  Future<void> _add(_BatchContent content) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder (chapter)'),
              onTap: () => Navigator.pop(sheetContext, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Upload PDF / notes'),
              onTap: () => Navigator.pop(sheetContext, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.smart_display_outlined),
              title: const Text('Add YouTube video link'),
              onTap: () => Navigator.pop(sheetContext, 'video'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'folder') {
      await _newFolder(content);
      return;
    }
    final added = await _addMaterial(
      context,
      backend: widget.backend,
      batch: widget.batch,
      content: content,
      folderId: content.folders.isEmpty ? null : content.folders.first.id,
      isVideo: choice == 'video',
      lookupTitle: widget.lookupTitle,
    );
    if (added) await _refresh();
  }

  Future<void> _openFolder(
    _BatchContent content,
    MaterialFolder? folder,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderPage(
          backend: widget.backend,
          batch: widget.batch,
          folder: folder,
          isTeacher: widget.isTeacher,
          lookupTitle: widget.lookupTitle,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_BatchContent>(
    future: _content,
    builder: (context, snapshot) {
      final content = snapshot.data;
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.batch.title),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: widget.isTeacher && content != null
            ? FloatingActionButton.extended(
                onPressed: () => _add(content),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              )
            : null,
        body: snapshot.hasError
            ? _RefreshableList(
                onRefresh: _refresh,
                children: [
                  _LoadError(
                    message: _batchLoadError(
                      snapshot.error!,
                      isTeacher: widget.isTeacher,
                    ),
                    onRetry: _refresh,
                  ),
                ],
              )
            : content == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(onRefresh: _refresh, child: _list(content)),
      );
    },
  );

  Widget _list(_BatchContent content) {
    final folders = content.folders;
    final loose = content.inFolder(null);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          widget.batch.courseTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (folders.isEmpty && loose.isEmpty)
          _EmptyState(
            icon: Icons.folder_outlined,
            title: 'No chapters yet',
            detail: widget.isTeacher
                ? 'Tap Add → New folder to create "Chapter 1".'
                : 'Your teacher will add chapters here.',
          ),
        for (var i = 0; i < folders.length; i++)
          _RowCard(
            leading: const Icon(Icons.folder),
            title: folders[i].title,
            subtitle: _itemCount(content.inFolder(folders[i].id).length),
            onTap: () => _openFolder(content, folders[i]),
            trailing: widget.isTeacher
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MoveButtons(
                        onUp: i == 0
                            ? null
                            : () => _run(
                                () => widget.backend.reorderFolders(
                                  _swapped(folders, i, i - 1),
                                ),
                              ),
                        onDown: i == folders.length - 1
                            ? null
                            : () => _run(
                                () => widget.backend.reorderFolders(
                                  _swapped(folders, i, i + 1),
                                ),
                              ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Folder options',
                        onSelected: (value) => value == 'rename'
                            ? _rename(folders[i])
                            : _delete(content, folders[i]),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  )
                : const Icon(Icons.chevron_right),
          ),
        if (loose.isNotEmpty)
          _RowCard(
            leading: const Icon(Icons.folder_open_outlined),
            title: 'Other materials',
            subtitle: widget.isTeacher
                ? '${_itemCount(loose.length)} not in a folder'
                : _itemCount(loose.length),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFolder(content, null),
          ),
      ],
    );
  }
}

String _itemCount(int n) => n == 0 ? 'Empty' : '$n item${n == 1 ? '' : 's'}';

/// The numbered materials of one folder ([folder] null = "Other materials").
class FolderPage extends StatefulWidget {
  const FolderPage({
    required this.backend,
    required this.batch,
    required this.folder,
    required this.isTeacher,
    this.lookupTitle = fetchYoutubeTitle,
    super.key,
  });

  final GyanifyBackend backend;
  final LearningBatch batch;
  final MaterialFolder? folder;
  final bool isTeacher;
  final YoutubeTitleLookup lookupTitle;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  late Future<_BatchContent> _content = _loadBatch(
    widget.backend,
    widget.batch.id,
  );

  String? get _folderId => widget.folder?.id;

  /// Back from the background: show what changed meanwhile.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _content = _loadBatch(widget.backend, widget.batch.id);
    });
    await _settle(_content);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      await _refresh();
      if (mounted && done != null) _showMessage(context, done);
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  Future<void> _add(_BatchContent content) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Upload PDF / notes'),
              onTap: () => Navigator.pop(sheetContext, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.smart_display_outlined),
              title: const Text('Add YouTube video link'),
              onTap: () => Navigator.pop(sheetContext, 'video'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final added = await _addMaterial(
      context,
      backend: widget.backend,
      batch: widget.batch,
      content: content,
      folderId: _folderId,
      isVideo: choice == 'video',
      lookupTitle: widget.lookupTitle,
    );
    if (added) await _refresh();
  }

  Future<void> _move(_BatchContent content, LearningMaterial material) async {
    final choice = await showMoveDialog(
      context,
      folders: content.folders,
      currentFolderId: material.folderId,
    );
    if (choice == null) return;
    await _run(
      () => widget.backend.moveMaterial(
        material,
        folderId: choice.folderId,
        displayOrder: content.nextOrder(choice.folderId),
      ),
      done: 'Moved.',
    );
  }

  Future<void> _delete(LearningMaterial material) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this material?',
      detail: '"${material.title}" will be removed for all students.',
    );
    if (!confirmed) return;
    await _run(() => widget.backend.deleteMaterial(material));
  }

  Future<void> _open(LearningMaterial material) async {
    if (material.isVideo) {
      final id = youtubeVideoId(material.youtubeUrl ?? '');
      if (id == null) {
        _showMessage(context, 'This video link is not valid.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _VideoPage(title: material.title, videoId: id),
        ),
      );
      return;
    }
    try {
      final url = await widget.backend.createPdfLink(material.storagePath!);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PdfPage(title: material.title, url: url),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  Future<void> _download(LearningMaterial material) async {
    try {
      final url = await widget.backend.createPdfDownloadLink(
        material.storagePath!,
        material.title,
      );
      if (mounted) await _openExternal(context, url);
    } catch (error) {
      if (mounted) _showMessage(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.folder?.title ?? 'Other materials';
    return FutureBuilder<_BatchContent>(
      future: _content,
      builder: (context, snapshot) {
        final content = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          floatingActionButton: widget.isTeacher && content != null
              ? FloatingActionButton.extended(
                  onPressed: () => _add(content),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                )
              : null,
          body: snapshot.hasError
              ? _RefreshableList(
                  onRefresh: _refresh,
                  children: [
                    _LoadError(
                      message: _batchLoadError(
                        snapshot.error!,
                        isTeacher: widget.isTeacher,
                      ),
                      onRetry: _refresh,
                    ),
                  ],
                )
              : content == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _refresh, child: _list(content)),
        );
      },
    );
  }

  Widget _list(_BatchContent content) {
    final items = content.inFolder(_folderId);
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          _EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here yet',
            detail: widget.isTeacher
                ? 'Tap Add to upload a PDF or add a YouTube video.'
                : 'Your teacher will add notes and videos here.',
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (var i = 0; i < items.length; i++)
          _RowCard(
            leading: _ItemLeading(number: i + 1, material: items[i]),
            title: items[i].title,
            subtitle: items[i].description,
            onTap: () => _open(items[i]),
            trailing: widget.isTeacher
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MoveButtons(
                        onUp: i == 0
                            ? null
                            : () => _run(
                                () => widget.backend.reorderMaterials(
                                  _swapped(items, i, i - 1),
                                ),
                              ),
                        onDown: i == items.length - 1
                            ? null
                            : () => _run(
                                () => widget.backend.reorderMaterials(
                                  _swapped(items, i, i + 1),
                                ),
                              ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Options',
                        onSelected: (value) => switch (value) {
                          'download' => _download(items[i]),
                          'move' => _move(content, items[i]),
                          _ => _delete(items[i]),
                        },
                        itemBuilder: (_) => [
                          if (items[i].isPdf)
                            const PopupMenuItem(
                              value: 'download',
                              child: Text('Download'),
                            ),
                          const PopupMenuItem(
                            value: 'move',
                            child: Text('Move to folder'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  )
                : items[i].isPdf
                ? IconButton(
                    tooltip: 'Download',
                    onPressed: () => _download(items[i]),
                    icon: const Icon(Icons.download),
                  )
                : const Icon(Icons.play_circle_outline),
          ),
      ],
    );
  }
}

/// "1." plus a video thumbnail or a PDF icon.
class _ItemLeading extends StatelessWidget {
  const _ItemLeading({required this.number, required this.material});

  final int number;
  final LearningMaterial material;

  @override
  Widget build(BuildContext context) {
    final videoId = material.isVideo
        ? youtubeVideoId(material.youtubeUrl ?? '')
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          child: Text(
            '$number.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (videoId != null)
          VideoThumbnail(videoId: videoId, width: 56)
        else
          SizedBox(
            width: 56,
            child: Icon(
              material.isVideo ? Icons.smart_display : Icons.picture_as_pdf,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
    );
  }
}
