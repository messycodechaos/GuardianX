import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'evidence_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({Key? key}) : super(key: key);

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final EvidenceService _evidenceService = EvidenceService.instance;
  EvidenceType? _selectedFilter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvidence();
  }

  Future<void> _loadEvidence() async {
    setState(() => _isLoading = true);
    await _evidenceService.initialize();
    setState(() => _isLoading = false);
  }

  List<EvidenceItem> get _filteredItems {
    if (_selectedFilter == null) return _evidenceService.items;
    return _evidenceService.items
        .where((e) => e.type == _selectedFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.shield, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Evidence Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadEvidence,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _filteredItems.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildEvidenceCard(_filteredItems[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('All Evidence', null),
            _filterChip('Videos', EvidenceType.video),
            _filterChip('Audio', EvidenceType.audio),
            _filterChip('Snapshots', EvidenceType.image),
            _filterChip('Threat Clips', EvidenceType.incidentClip),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, EvidenceType? type) {
    final isSelected = _selectedFilter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: Colors.blueAccent.withOpacity(0.3),
        backgroundColor: const Color(0xFF334155),
        labelStyle: TextStyle(
          color: isSelected ? Colors.blueAccent : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => setState(() => _selectedFilter = type),
      ),
    );
  }

  Widget _buildEvidenceCard(EvidenceItem item) {
    final dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(item.timestamp);
    final sizeKb = (item.fileSizeBytes / 1024).toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.incidentType != null ? Colors.redAccent.withOpacity(0.5) : const Color(0xFF334155),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: item.incidentType != null ? Colors.redAccent.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
          child: Icon(
            item.type == EvidenceType.video || item.type == EvidenceType.incidentClip
                ? Icons.videocam
                : item.type == EvidenceType.audio
                ? Icons.mic
                : Icons.image,
            color: item.incidentType != null ? Colors.redAccent : Colors.blueAccent,
          ),
        ),
        title: Text(
          item.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text('$sizeKb KB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                if (item.latitude != null && item.longitude != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.location_on, size: 12, color: Colors.greenAccent),
                  Text(' ${item.latitude!.toStringAsFixed(3)}, ${item.longitude!.toStringAsFixed(3)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          color: const Color(0xFF334155),
          onSelected: (value) => _handleAction(value, item),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'play', child: Text('Open / Play', style: TextStyle(color: Colors.white))),
            const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
        onTap: () => _playItem(item),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.folder_open, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text('No evidence files recorded yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
          SizedBox(height: 8),
          Text('Videos and snapshots from Safety Eye will appear here', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  void _handleAction(String action, EvidenceItem item) {
    if (action == 'play') {
      _playItem(item);
    } else if (action == 'rename') {
      _showRenameDialog(item);
    } else if (action == 'delete') {
      _confirmDelete(item);
    }
  }

  void _playItem(EvidenceItem item) {
    if (item.type == EvidenceType.video || item.type == EvidenceType.incidentClip) {
      showDialog(
        context: context,
        builder: (_) => _VideoPlaybackDialog(filePath: item.filePath, title: item.title),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File stored at: ${item.filePath}')),
      );
    }
  }

  void _showRenameDialog(EvidenceItem item) {
    final controller = TextEditingController(text: item.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Rename Evidence', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Enter title', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _evidenceService.renameEvidence(item.id, controller.text.trim());
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(EvidenceItem item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Evidence?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete this evidence file from device storage.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _evidenceService.deleteEvidence(item.id);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _VideoPlaybackDialog extends StatefulWidget {
  final String filePath;
  final String title;

  const _VideoPlaybackDialog({required this.filePath, required this.title});

  @override
  State<_VideoPlaybackDialog> createState() => _VideoPlaybackDialogState();
}

class _VideoPlaybackDialogState extends State<_VideoPlaybackDialog> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            title: Text(widget.title, style: const TextStyle(fontSize: 14)),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ),
          _initialized
              ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
              : const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
          IconButton(
            icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
            onPressed: () {
              setState(() {
                _controller.value.isPlaying ? _controller.pause() : _controller.play();
              });
            },
          ),
        ],
      ),
    );
  }
}