import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_colors.dart'; // adjust relative path to match your project
import '../models/weight_record.dart';
import '../services/weight_record_service.dart';

/// Add-or-edit form for a single weight record
class LogWeightScreen extends StatefulWidget {
  final WeightRecord? existingRecord;

  const LogWeightScreen({super.key, this.existingRecord});

  @override
  State<LogWeightScreen> createState() => _LogWeightScreenState();
}

class _LogWeightScreenState extends State<LogWeightScreen> {
  final _weightController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _pictureBase64; // already-compressed, ready to store
  bool _saving = false;
  bool _deleting = false;

  bool get _isEditing => widget.existingRecord != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingRecord;
    if (existing != null) {
      _weightController.text = existing.weightKg.toString();
      _descriptionController.text = existing.description ?? '';
      _selectedDate = existing.date;
      _pictureBase64 = existing.progressPictureBase64;
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surfaceContainerHigh,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    // Compress before base64-encoding 
    final compressed = await FlutterImageCompress.compressWithFile(
      picked.path,
      minWidth: 800,
      minHeight: 800,
      quality: 70,
    );
    if (compressed == null) return;

    setState(() => _pictureBase64 = base64Encode(compressed));
  }

  void _removeImage() => setState(() => _pictureBase64 = null);

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final weight = double.tryParse(_weightController.text.trim());
    if (weight == null || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final record = WeightRecord(
        id: widget.existingRecord?.id ?? const Uuid().v4(),
        date: _selectedDate,
        weightKg: weight,
        progressPictureBase64: _pictureBase64,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (_isEditing) {
        await WeightRecordService().updateRecord(uid: uid, record: record);
      } else {
        await WeightRecordService().addRecord(uid: uid, record: record);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final existing = widget.existingRecord;
    if (uid == null || existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Delete record?', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Text(
          'This removes the weight entry and its progress picture. This cannot be undone.',
          style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await WeightRecordService().deleteRecord(uid: uid, recordId: existing.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
      setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          _isEditing ? 'Edit Weight Record' : 'Log Weight',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, color: AppColors.error),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildLabel('WEIGHT (KG)'),
            const SizedBox(height: 8),
            _buildBottomEtchedField(
              child: TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '0.0',
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildLabel('DATE'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: _buildBottomEtchedField(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedDate.day} ${_kMonthNames[_selectedDate.month - 1]} ${_selectedDate.year}',
                      style: GoogleFonts.manrope(fontSize: 15, color: AppColors.onSurface),
                    ),
                    const Icon(Icons.calendar_today_rounded,
                        size: 16, color: AppColors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildLabel('PROGRESS PICTURE (OPTIONAL)'),
            const SizedBox(height: 8),
            _buildPicturePicker(),
            const SizedBox(height: 24),
            _buildLabel('DESCRIPTION (OPTIONAL)'),
            const SizedBox(height: 8),
            _buildBottomEtchedField(
              child: TextField(
                controller: _descriptionController,
                maxLines: 3,
                style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'e.g. Feeling stronger this month',
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.onSurfaceVariant,
        ),
      );

  // "Bottom-Etched" input
  Widget _buildBottomEtchedField({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _buildPicturePicker() {
    if (_pictureBase64 != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              base64Decode(_pictureBase64!),
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _removeImage,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_a_photo_outlined,
                color: AppColors.onSurfaceVariant, size: 24),
            const SizedBox(height: 8),
            Text(
              'Add a photo',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(48)),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
              )
            : Text(
                _isEditing ? 'Save Changes' : 'Log Weight',
                style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}

const List<String> _kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];