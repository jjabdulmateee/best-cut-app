import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../data/user_data_provider.dart';
import '../../main.dart';

// ---------------------------------------------------------------------------
// BarberApplicationStatusScreen
// ---------------------------------------------------------------------------
// The ONLY screen visible to unapproved barbers.
// University-style application portal where barbers:
//  - Upload required documents (CNIC, profile photo, 4 shop photos)
//  - Track application progress via a visual checklist
//  - Auto-submit once all documents are uploaded
//  - Cannot navigate to any barber features until approved
//
// Upload enable/disable rules:
//  draft / needMoreDocs  → uploads ENABLED
//  submitted / underReview → uploads DISABLED ("under review, please wait")
//  approved → redirect via AuthWrapper (never visible here)
//  rejected → show rejection reason + support contact
// ---------------------------------------------------------------------------

class BarberApplicationStatusScreen extends StatefulWidget {
  final BarberStatus status;
  final String? rejectionReason;

  const BarberApplicationStatusScreen({
    super.key,
    required this.status,
    this.rejectionReason,
  });

  @override
  State<BarberApplicationStatusScreen> createState() =>
      _BarberApplicationStatusScreenState();
}

class _BarberApplicationStatusScreenState
    extends State<BarberApplicationStatusScreen> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _imagePicker = ImagePicker();
  final _firestore = FirebaseFirestore.instance;

  bool _isRefreshing = false;
  late BarberStatus _currentStatus;
  String? _currentRejectionReason;

  // Document upload state
  bool _cnicUploaded = false;
  bool _profileUploaded = false;
  List<bool> _shopPhotosUploaded = [false, false, false, false];
  String? _uploadingId; // e.g. 'cnic', 'profile', 'shop_1'

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  int get _shopPhotosCount => _shopPhotosUploaded.where((b) => b).length;
  int get _totalUploaded =>
      (_cnicUploaded ? 1 : 0) + (_profileUploaded ? 1 : 0) + _shopPhotosCount;
  static const int _totalRequired = 6; // 1 CNIC + 1 profile + 4 shop
  bool get _allDocumentsComplete => _totalUploaded == _totalRequired;

  /// Uploads are only enabled when the barber needs to provide documents.
  bool get _uploadsEnabled =>
      _currentStatus == BarberStatus.draft ||
      _currentStatus == BarberStatus.pending ||
      _currentStatus == BarberStatus.needMoreDocs;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentStatus = widget.status;
    _currentRejectionReason = widget.rejectionReason;
    _loadApplicationData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadApplicationData() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore
          .collection('barber_applications')
          .doc(user.uid)
          .get();

      if (mounted && doc.exists) {
        final data = doc.data() ?? {};
        final docs = Map<String, dynamic>.from(data['documents'] as Map? ?? {});
        setState(() {
          _cnicUploaded = docs['cnic'] == true;
          _profileUploaded = docs['profile'] == true;
          for (int i = 0; i < 4; i++) {
            _shopPhotosUploaded[i] = docs['shop_${i + 1}'] == true;
          }
          final statusStr = data['status'] as String?;
          if (statusStr != null) {
            _currentStatus = BarberStatus.values.firstWhere(
              (s) => s.name == statusStr,
              orElse: () => _currentStatus,
            );
          }
          _currentRejectionReason = data['rejectionReason'] as String?;
        });
      }
    } catch (e) {
      debugPrint('BarberApplication: Failed to load data: $e');
    }
  }

  Future<void> _refreshStatus() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      final user = _authService.currentUser;
      if (user == null) return;

      final newStatus =
          await _authService.getBarberApplicationStatus(user.uid);
      final userData = await _authService.getUserData(user.uid);

      if (!mounted) return;

      if (!newStatus.isBlocked) {
        // Approved! Navigate back through AuthWrapper.
        await UserDataProvider().initialize();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Your account has been approved!'),
              ]),
              backgroundColor: Color(0xFF00AA5B),
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthWrapper()),
            (route) => false,
          );
        }
        return;
      }

      setState(() {
        _currentStatus = newStatus;
        _currentRejectionReason = userData?['rejectionReason'] as String?;
        _isRefreshing = false;
      });
      await _loadApplicationData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status: ${newStatus.displayName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to refresh. Check your connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Document upload — single image (CNIC, Profile)
  // ---------------------------------------------------------------------------

  Future<void> _uploadSingleDocument({
    required String docKey,
    required String storageFileName,
  }) async {
    if (!_uploadsEnabled) return;
    final user = _authService.currentUser;
    if (user == null) return;

    final source = await _showSourcePicker();
    if (source == null || !mounted) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() => _uploadingId = docKey);

      // Upload to fixed path: barber_documents/{uid}/{storageFileName}
      final storagePath = 'barber_documents/${user.uid}/$storageFileName';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putFile(File(picked.path));

      // Update Firestore metadata
      await _firestore.collection('barber_applications').doc(user.uid).update({
        'documents.$docKey': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          if (docKey == 'cnic') _cnicUploaded = true;
          if (docKey == 'profile') _profileUploaded = true;
          _uploadingId = null;
        });
        _showUploadSuccess();
        await _checkAndAutoSubmit();
      }
    } catch (e) {
      _handleUploadError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Document upload — shop photo (1 of 4)
  // ---------------------------------------------------------------------------

  Future<void> _uploadShopPhoto(int index) async {
    if (!_uploadsEnabled) return;
    final user = _authService.currentUser;
    if (user == null) return;
    final slotKey = 'shop_${index + 1}';

    final source = await _showSourcePicker();
    if (source == null || !mounted) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() => _uploadingId = slotKey);

      // Upload to fixed path: barber_documents/{uid}/shop_N.jpg
      final storagePath = 'barber_documents/${user.uid}/$slotKey.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putFile(File(picked.path));

      // Update individual flag + recalculate shopPhotos count
      final newUploaded = List<bool>.from(_shopPhotosUploaded);
      newUploaded[index] = true;
      final newCount = newUploaded.where((b) => b).length;

      await _firestore.collection('barber_applications').doc(user.uid).update({
        'documents.$slotKey': true,
        'documents.shopPhotos': newCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _shopPhotosUploaded = newUploaded;
          _uploadingId = null;
        });
        _showUploadSuccess();
        await _checkAndAutoSubmit();
      }
    } catch (e) {
      _handleUploadError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-submit when all documents are complete
  // ---------------------------------------------------------------------------

  Future<void> _checkAndAutoSubmit() async {
    if (!_allDocumentsComplete) return;
    // Only auto-submit from draft / pending / needMoreDocs
    if (_currentStatus != BarberStatus.draft &&
        _currentStatus != BarberStatus.pending &&
        _currentStatus != BarberStatus.needMoreDocs) {
      return;
    }

    final user = _authService.currentUser;
    if (user == null) return;

    try {
      // Update barber_applications status to 'submitted'
      // Firestore rules allow this specific transition only.
      await _firestore.collection('barber_applications').doc(user.uid).update({
        'status': BarberStatus.submitted.name,
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _currentStatus = BarberStatus.submitted);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.send_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    'All documents uploaded! Your application has been submitted for review.'),
              ),
            ]),
            backgroundColor: Color(0xFF2196F3),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Auto-submit failed: $e');
      // Non-blocking — the admin can still process without auto-submit
    }
  }

  // ---------------------------------------------------------------------------
  // Upload helpers
  // ---------------------------------------------------------------------------

  Future<ImageSource?> _showSourcePicker() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Upload Photo',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 4),
              Text('Choose how you want to upload',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              const SizedBox(height: 20),
              ListTile(
                leading: _sourceIcon(Icons.camera_alt_outlined),
                title: const Text('Take a Photo',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: const Text('Use your camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: _sourceIcon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: const Text('Select an existing photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceIcon(IconData icon) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF1A1A1A)),
      );

  void _showUploadSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 8),
          Text('Uploaded successfully'),
        ]),
        backgroundColor: Color(0xFF4CAF50),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleUploadError(Object e) {
    debugPrint('Upload failed: $e');
    if (mounted) {
      setState(() => _uploadingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Upload failed: ${e.toString().split(']').last.trim()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text(
            'Are you sure you want to sign out?\nYour application progress is saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out',
                style: TextStyle(color: Color(0xFF1A1A1A))),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      UserDataProvider().clear();
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Your Application',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A))),
          centerTitle: true,
          actions: [
            TextButton.icon(
              onPressed: _handleSignOut,
              icon: const Icon(Icons.logout,
                  size: 18, color: Color(0xFF6B6B6B)),
              label: const Text('Sign Out',
                  style: TextStyle(color: Color(0xFF6B6B6B), fontSize: 13)),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshStatus,
          color: const Color(0xFF1A1A1A),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusHeader(),
                const SizedBox(height: 24),
                _buildTimeline(),
                const SizedBox(height: 24),
                // Under-review banner
                if (!_uploadsEnabled &&
                    _currentStatus != BarberStatus.rejected)
                  _buildUnderReviewBanner(),
                if (!_uploadsEnabled &&
                    _currentStatus != BarberStatus.rejected)
                  const SizedBox(height: 24),
                _buildStatusMessage(),
                const SizedBox(height: 24),
                _buildChecklist(),
                const SizedBox(height: 24),
                _buildCnicSection(),
                const SizedBox(height: 16),
                _buildProfileSection(),
                const SizedBox(height: 16),
                _buildShopPhotosSection(),
                const SizedBox(height: 24),
                _buildHelpSection(),
                const SizedBox(height: 24),
                _buildCheckStatusButton(),
                const SizedBox(height: 12),
                Center(
                  child: Text('Pull down to refresh',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[400])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // UI Sections
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Status header
  // ---------------------------------------------------------------------------

  Widget _buildStatusHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor.withOpacity(0.3)),
      ),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: _isRefreshing
              ? Center(
                  child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                          color: _statusColor, strokeWidth: 2.5)))
              : Icon(_statusIcon, size: 36, color: _statusColor),
        ),
        const SizedBox(height: 16),
        Text(_currentStatus.displayName,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _statusColor,
                letterSpacing: -0.3),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(_statusSubtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center),
      ]),
    );
  }

  String get _statusSubtitle {
    switch (_currentStatus) {
      case BarberStatus.draft:
      case BarberStatus.pending:
        return 'Upload your documents to get started';
      case BarberStatus.submitted:
        return 'Your documents are in the review queue';
      case BarberStatus.underReview:
        return 'Our team is reviewing your application';
      case BarberStatus.needMoreDocs:
        return 'Action needed — please upload required documents';
      case BarberStatus.approved:
        return 'You are approved to offer services';
      case BarberStatus.rejected:
        return 'Your application was not approved';
    }
  }

  // ---------------------------------------------------------------------------
  // Under-review banner
  // ---------------------------------------------------------------------------

  Widget _buildUnderReviewBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Your application is under review. Uploads are disabled.\n'
            'آپ کی درخواست زیر جائزہ ہے۔ اپلوڈز غیر فعال ہیں۔',
            style: TextStyle(
                fontSize: 13, color: Colors.blue[800], height: 1.5),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Application timeline
  // ---------------------------------------------------------------------------

  Widget _buildTimeline() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Application Progress',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 20),
        const _TimelineStep(
          title: 'Account Created',
          subtitle: 'Your barber account is set up',
          state: _TimelineStepState.completed,
          isFirst: true,
        ),
        _TimelineStep(
          title: 'Documents Uploaded',
          subtitle: '$_totalUploaded/$_totalRequired documents',
          state: _allDocumentsComplete
              ? _TimelineStepState.completed
              : _TimelineStepState.current,
        ),
        _TimelineStep(
          title: _step3Title,
          subtitle: _step3Subtitle,
          state: _step3State,
        ),
        _TimelineStep(
          title: 'Decision',
          subtitle: _step4Subtitle,
          state: _step4State,
          isLast: true,
        ),
      ]),
    );
  }

  String get _step3Title {
    switch (_currentStatus) {
      case BarberStatus.submitted:
        return 'Submitted for Review';
      case BarberStatus.underReview:
        return 'Under Review';
      case BarberStatus.needMoreDocs:
        return 'More Documents Needed';
      case BarberStatus.approved:
      case BarberStatus.rejected:
        return 'Review Complete';
      default:
        return 'Awaiting Submission';
    }
  }

  String get _step3Subtitle {
    switch (_currentStatus) {
      case BarberStatus.submitted:
        return 'In the review queue — usually 24-48 hours';
      case BarberStatus.underReview:
        return 'Our team is actively reviewing';
      case BarberStatus.needMoreDocs:
        return 'Please upload the requested documents';
      case BarberStatus.approved:
      case BarberStatus.rejected:
        return 'Review has been completed';
      default:
        return 'Upload all documents to submit';
    }
  }

  _TimelineStepState get _step3State {
    switch (_currentStatus) {
      case BarberStatus.submitted:
      case BarberStatus.underReview:
        return _TimelineStepState.current;
      case BarberStatus.needMoreDocs:
        return _TimelineStepState.actionNeeded;
      case BarberStatus.approved:
      case BarberStatus.rejected:
        return _TimelineStepState.completed;
      default:
        return _TimelineStepState.pending;
    }
  }

  String get _step4Subtitle {
    switch (_currentStatus) {
      case BarberStatus.approved:
        return 'Approved — welcome aboard!';
      case BarberStatus.rejected:
        return 'Not approved — see details below';
      default:
        return 'Pending review outcome';
    }
  }

  _TimelineStepState get _step4State {
    switch (_currentStatus) {
      case BarberStatus.approved:
        return _TimelineStepState.completed;
      case BarberStatus.rejected:
        return _TimelineStepState.rejected;
      default:
        return _TimelineStepState.pending;
    }
  }

  // ---------------------------------------------------------------------------
  // Status message
  // ---------------------------------------------------------------------------

  Widget _buildStatusMessage() {
    if (_currentStatus == BarberStatus.rejected &&
        _currentRejectionReason != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, color: Colors.red[700], size: 20),
            const SizedBox(width: 8),
            Text('Reason',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[700])),
          ]),
          const SizedBox(height: 8),
          Text(_currentRejectionReason!,
              style: TextStyle(
                  fontSize: 14, color: Colors.red[700], height: 1.5)),
          const SizedBox(height: 12),
          Text('Contact support@bestcut.pk to discuss your application.\n'
              'اپنی درخواست پر بات کرنے کے لیے support@bestcut.pk پر رابطہ کریں۔',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.red[600],
                  fontStyle: FontStyle.italic,
                  height: 1.5)),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            _currentStatus == BarberStatus.needMoreDocs
                ? Icons.priority_high_rounded
                : Icons.lightbulb_outline,
            color: _currentStatus == BarberStatus.needMoreDocs
                ? Colors.orange[700]
                : const Color(0xFF1A1A1A),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text("What's Next",
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _currentStatus == BarberStatus.needMoreDocs
                      ? Colors.orange[700]
                      : const Color(0xFF1A1A1A))),
        ]),
        const SizedBox(height: 10),
        Text(_currentStatus.description,
            style: TextStyle(
                fontSize: 14, color: Colors.grey[700], height: 1.6)),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Checklist summary
  // ---------------------------------------------------------------------------

  Widget _buildChecklist() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.checklist_rounded,
              size: 20, color: Color(0xFF1A1A1A)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Application Checklist',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A))),
          ),
          _completionBadge(),
        ]),
        const SizedBox(height: 16),
        _checklistItem(
          label: 'CNIC uploaded',
          urduLabel: 'شناختی کارڈ اپلوڈ کیا گیا',
          isDone: _cnicUploaded,
        ),
        const SizedBox(height: 10),
        _checklistItem(
          label: 'Profile photo uploaded',
          urduLabel: 'پروفائل تصویر اپلوڈ کی گئی',
          isDone: _profileUploaded,
        ),
        const SizedBox(height: 10),
        _checklistItem(
          label: 'Shop photos uploaded ($_shopPhotosCount/4)',
          urduLabel: 'دکان کی تصاویر ($_shopPhotosCount/4)',
          isDone: _shopPhotosCount == 4,
          isPartial: _shopPhotosCount > 0 && _shopPhotosCount < 4,
        ),
      ]),
    );
  }

  Widget _completionBadge() {
    final isComplete = _allDocumentsComplete;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isComplete
            ? const Color(0xFF4CAF50).withOpacity(0.1)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$_totalUploaded/$_totalRequired',
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isComplete ? const Color(0xFF4CAF50) : Colors.grey[600]),
      ),
    );
  }

  Widget _checklistItem({
    required String label,
    required String urduLabel,
    required bool isDone,
    bool isPartial = false,
  }) {
    return Row(children: [
      Icon(
        isDone
            ? Icons.check_circle
            : isPartial
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
        size: 20,
        color: isDone
            ? const Color(0xFF4CAF50)
            : isPartial
                ? const Color(0xFFFF9800)
                : Colors.grey[400],
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDone ? const Color(0xFF4CAF50) : const Color(0xFF1A1A1A))),
            Text(urduLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // CNIC upload section
  // ---------------------------------------------------------------------------

  Widget _buildCnicSection() {
    return _DocumentCard(
      title: 'CNIC / National ID',
      instruction: 'Please upload a clear photo of your CNIC (front side only).\n'
          'براہ کرم اپنے شناختی کارڈ کی واضح تصویر اپلوڈ کریں (صرف سامنے کی طرف)۔',
      icon: Icons.badge_outlined,
      isUploaded: _cnicUploaded,
      isUploading: _uploadingId == 'cnic',
      uploadsEnabled: _uploadsEnabled,
      onUpload: () =>
          _uploadSingleDocument(docKey: 'cnic', storageFileName: 'cnic.jpg'),
    );
  }

  // ---------------------------------------------------------------------------
  // Profile photo upload section
  // ---------------------------------------------------------------------------

  Widget _buildProfileSection() {
    return _DocumentCard(
      title: 'Profile Photo',
      instruction:
          'Upload a clear photo of yourself (face clearly visible).\n'
          'اپنی واضح تصویر اپلوڈ کریں (چہرہ صاف نظر آئے)۔',
      icon: Icons.person_outline,
      isUploaded: _profileUploaded,
      isUploading: _uploadingId == 'profile',
      uploadsEnabled: _uploadsEnabled,
      onUpload: () => _uploadSingleDocument(
          docKey: 'profile', storageFileName: 'profile.jpg'),
    );
  }

  // ---------------------------------------------------------------------------
  // Shop photos section (4 image grid)
  // ---------------------------------------------------------------------------

  Widget _buildShopPhotosSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.store_outlined,
              size: 20, color: Color(0xFF1A1A1A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Shop Photos ($_shopPhotosCount/4)',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A))),
          ),
          if (_shopPhotosCount == 4)
            const Icon(Icons.check_circle,
                size: 20, color: Color(0xFF4CAF50)),
        ]),
        const SizedBox(height: 8),
        Text(
          'Upload 4 photos of your shop or workspace.\n'
          'اپنی دکان یا ورک سپیس کی 4 تصاویر اپلوڈ کریں۔',
          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 16),
        // 2x2 grid of shop photo slots
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: List.generate(4, (i) {
            final slotKey = 'shop_${i + 1}';
            final isUploaded = _shopPhotosUploaded[i];
            final isUploading = _uploadingId == slotKey;
            return _ShopPhotoSlot(
              index: i + 1,
              isUploaded: isUploaded,
              isUploading: isUploading,
              uploadsEnabled: _uploadsEnabled,
              onUpload: () => _uploadShopPhoto(i),
            );
          }),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Help section
  // ---------------------------------------------------------------------------

  Widget _buildHelpSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Need Help?',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 4),
        Text('مدد چاہیے؟',
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 12),
        const _HelpRow(
            icon: Icons.email_outlined,
            label: 'support@bestcut.pk',
            sublabel: 'Email us anytime / کسی بھی وقت ای میل کریں'),
        const SizedBox(height: 10),
        const _HelpRow(
            icon: Icons.schedule_outlined,
            label: 'Response time',
            sublabel: 'Usually within 24 hours / عام طور پر 24 گھنٹوں میں'),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Check status button
  // ---------------------------------------------------------------------------

  Widget _buildCheckStatusButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isRefreshing ? null : _refreshStatus,
        icon: _isRefreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.refresh, size: 20),
        label: Text(_isRefreshing ? 'Checking...' : 'Check for Updates',
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A1A1A),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status color / icon helpers
  // ---------------------------------------------------------------------------

  Color get _statusColor {
    switch (_currentStatus) {
      case BarberStatus.draft:
      case BarberStatus.pending:
        return const Color(0xFFFF9800);
      case BarberStatus.submitted:
        return const Color(0xFF2196F3);
      case BarberStatus.underReview:
        return const Color(0xFF7C4DFF);
      case BarberStatus.needMoreDocs:
        return const Color(0xFFFF6D00);
      case BarberStatus.approved:
        return const Color(0xFF4CAF50);
      case BarberStatus.rejected:
        return const Color(0xFFE53935);
    }
  }

  IconData get _statusIcon {
    switch (_currentStatus) {
      case BarberStatus.draft:
      case BarberStatus.pending:
        return Icons.hourglass_top_rounded;
      case BarberStatus.submitted:
        return Icons.send_rounded;
      case BarberStatus.underReview:
        return Icons.manage_search_rounded;
      case BarberStatus.needMoreDocs:
        return Icons.upload_file_rounded;
      case BarberStatus.approved:
        return Icons.verified_rounded;
      case BarberStatus.rejected:
        return Icons.block_rounded;
    }
  }
}

// =============================================================================
// Private supporting widgets
// =============================================================================

// ---------------------------------------------------------------------------
// Single-document upload card (CNIC, Profile)
// ---------------------------------------------------------------------------

class _DocumentCard extends StatelessWidget {
  final String title;
  final String instruction;
  final IconData icon;
  final bool isUploaded;
  final bool isUploading;
  final bool uploadsEnabled;
  final VoidCallback onUpload;

  const _DocumentCard({
    required this.title,
    required this.instruction,
    required this.icon,
    required this.isUploaded,
    required this.isUploading,
    required this.uploadsEnabled,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUploaded
            ? const Color(0xFF4CAF50).withOpacity(0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUploaded
              ? const Color(0xFF4CAF50).withOpacity(0.25)
              : Colors.grey[200]!,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isUploaded
                  ? const Color(0xFF4CAF50).withOpacity(0.1)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isUploaded ? Icons.check_circle_outline : icon,
              color: isUploaded
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFF1A1A1A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A))),
          ),
          if (isUploaded)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Done',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50))),
            ),
        ]),
        const SizedBox(height: 10),
        Text(instruction,
            style: TextStyle(
                fontSize: 13, color: Colors.grey[600], height: 1.5)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: isUploading
              ? const Center(
                  child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF1A1A1A))))
              : OutlinedButton.icon(
                  onPressed: uploadsEnabled ? onUpload : null,
                  icon: Icon(
                      isUploaded ? Icons.refresh : Icons.upload_outlined,
                      size: 18),
                  label: Text(isUploaded ? 'Replace' : 'Upload',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A1A1A),
                    side: BorderSide(
                        color: uploadsEnabled
                            ? const Color(0xFF1A1A1A)
                            : Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Shop photo slot (1 of 4)
// ---------------------------------------------------------------------------

class _ShopPhotoSlot extends StatelessWidget {
  final int index;
  final bool isUploaded;
  final bool isUploading;
  final bool uploadsEnabled;
  final VoidCallback onUpload;

  const _ShopPhotoSlot({
    required this.index,
    required this.isUploaded,
    required this.isUploading,
    required this.uploadsEnabled,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploadsEnabled ? onUpload : null,
      child: Container(
        decoration: BoxDecoration(
          color: isUploaded
              ? const Color(0xFF4CAF50).withOpacity(0.06)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded
                ? const Color(0xFF4CAF50).withOpacity(0.3)
                : Colors.grey[300]!,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: isUploading
            ? const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF1A1A1A))))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isUploaded
                        ? Icons.check_circle
                        : uploadsEnabled
                            ? Icons.add_a_photo_outlined
                            : Icons.photo_outlined,
                    size: 28,
                    color: isUploaded
                        ? const Color(0xFF4CAF50)
                        : uploadsEnabled
                            ? const Color(0xFF1A1A1A)
                            : Colors.grey[400],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isUploaded ? 'Photo $index ✓' : 'Photo $index',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isUploaded
                          ? const Color(0xFF4CAF50)
                          : Colors.grey[600],
                    ),
                  ),
                  if (!isUploaded && uploadsEnabled)
                    Text('Tap to upload',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline step
// ---------------------------------------------------------------------------

enum _TimelineStepState { completed, current, actionNeeded, pending, rejected }

class _TimelineStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final _TimelineStepState state;
  final bool isFirst;
  final bool isLast;

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.state,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            if (!isFirst)
              Container(
                  width: 2,
                  height: 8,
                  color: state == _TimelineStepState.pending
                      ? Colors.grey[300]
                      : _dotColor),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: state == _TimelineStepState.pending
                    ? Colors.grey[200]
                    : _dotColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: state == _TimelineStepState.pending
                        ? Colors.grey[400]!
                        : _dotColor,
                    width: 2),
              ),
              child: Center(child: _dotIcon),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                    width: 2,
                    color: state == _TimelineStepState.completed
                        ? _dotColor
                        : Colors.grey[300]),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: state == _TimelineStepState.pending
                          ? Colors.grey[500]
                          : const Color(0xFF1A1A1A))),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[500], height: 1.3)),
            ]),
          ),
        ),
      ]),
    );
  }

  Color get _dotColor {
    switch (state) {
      case _TimelineStepState.completed:
        return const Color(0xFF4CAF50);
      case _TimelineStepState.current:
        return const Color(0xFF2196F3);
      case _TimelineStepState.actionNeeded:
        return const Color(0xFFFF9800);
      case _TimelineStepState.pending:
        return Colors.grey;
      case _TimelineStepState.rejected:
        return const Color(0xFFE53935);
    }
  }

  Widget? get _dotIcon {
    switch (state) {
      case _TimelineStepState.completed:
        return const Icon(Icons.check, size: 14, color: Color(0xFF4CAF50));
      case _TimelineStepState.current:
        return Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Color(0xFF2196F3), shape: BoxShape.circle));
      case _TimelineStepState.actionNeeded:
        return const Icon(Icons.priority_high,
            size: 14, color: Color(0xFFFF9800));
      case _TimelineStepState.pending:
        return null;
      case _TimelineStepState.rejected:
        return const Icon(Icons.close, size: 14, color: Color(0xFFE53935));
    }
  }
}

// ---------------------------------------------------------------------------
// Help row
// ---------------------------------------------------------------------------

class _HelpRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;

  const _HelpRow({
    required this.icon,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF6B6B6B)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A))),
          Text(sublabel,
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ]),
      ),
    ]);
  }
}
