import 'dart:io' as io;
import 'package:flutter/cupertino.dart' as import_cupertino;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../utils/snackbar_utils.dart';

// ==========================================
// ADD NEW WORKER FLOW (EXPERIENCE & DOCS)
// ==========================================
class AddNewWorkerFlow extends StatefulWidget {
  final VoidCallback? onBack;
  final Map<String, dynamic>? workerToEdit;

  const AddNewWorkerFlow({super.key, this.onBack, this.workerToEdit});

  @override
  State<AddNewWorkerFlow> createState() => _AddNewWorkerFlowState();
}

class _AddNewWorkerFlowState extends State<AddNewWorkerFlow> {
  int _activeTabIndex = 0;
  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _religionController = TextEditingController();
  final _dobController = TextEditingController();
  final _genderController = TextEditingController();
  final _addressController = TextEditingController();
  final _positionController = TextEditingController();
  final _type1Controller = TextEditingController();
  final _type2Controller = TextEditingController();

  // Upload states
  Uint8List? _profileImageBytes;
  String? _profileImageName;
  String? _existingProfileImageUrl;

  Uint8List? _frontIdBytes;
  String? _frontIdName;
  String? _existingFrontIdUrl;

  Uint8List? _backIdBytes;
  String? _backIdName;
  String? _existingBackIdUrl;

  Uint8List? _cvBytes;
  String? _cvName;
  String? _existingCvUrl;
  bool _isCvUploaded = false;

  String? _joiningDate;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.workerToEdit != null) {
      _nameController.text = (widget.workerToEdit!['name'] ?? '').toString();
      _fatherNameController.text = (widget.workerToEdit!['fatherName'] ?? '')
          .toString();
      _emailController.text = (widget.workerToEdit!['email'] ?? '').toString();
      _phoneController.text = (widget.workerToEdit!['phone'] ?? '').toString();
      _nationalIdController.text = (widget.workerToEdit!['nationalId'] ?? '')
          .toString();
      _religionController.text = (widget.workerToEdit!['religion'] ?? '')
          .toString();
      _dobController.text = (widget.workerToEdit!['dob'] ?? '').toString();
      _genderController.text = (widget.workerToEdit!['gender'] ?? '')
          .toString();
      _addressController.text = (widget.workerToEdit!['address'] ?? '')
          .toString();
      _positionController.text = (widget.workerToEdit!['position'] ?? '')
          .toString();
      _type1Controller.text = (widget.workerToEdit!['type1'] ?? '').toString();
      _type2Controller.text = (widget.workerToEdit!['type2'] ?? '').toString();

      _existingProfileImageUrl = widget.workerToEdit!['profileImage']
          ?.toString();
      _existingFrontIdUrl = widget.workerToEdit!['frontId']?.toString();
      _existingBackIdUrl = widget.workerToEdit!['backId']?.toString();
      _existingCvUrl = widget.workerToEdit!['cv']?.toString();
      if (_existingCvUrl != null && _existingCvUrl!.isNotEmpty) {
        _isCvUploaded = true;
        _cvName = _existingCvUrl!.split('/').last;
      }
      _joiningDate = widget.workerToEdit!['joiningDate']?.toString();
    }
  }

  Future<String?> _uploadToStorage(
    String folder,
    String fileName,
    Uint8List fileBytes,
  ) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'hrms_documents/$folder/${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );
      final uploadTask = ref.putData(fileBytes);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Firebase Storage upload failed: $e');
      return null;
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _profileImageBytes = bytes;
          _profileImageName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
    }
  }

  Future<void> _pickFrontId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _frontIdBytes = bytes;
          _frontIdName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking front ID: $e');
    }
  }

  Future<void> _pickBackId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _backIdBytes = bytes;
          _backIdName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking back ID: $e');
    }
  }

  Future<void> _pickCv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _cvBytes = bytes;
          _cvName = file.name;
          _isCvUploaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error picking CV: $e');
    }
  }

  Future<void> _saveWorker() async {
    setState(() {
      _isSaving = true;
    });

    String? profileImageUrl = _existingProfileImageUrl;
    String? frontIdUrl = _existingFrontIdUrl;
    String? backIdUrl = _existingBackIdUrl;
    String? cvUrl = _existingCvUrl;

    if (_profileImageBytes != null) {
      profileImageUrl = await _uploadToStorage(
        'profile_images',
        _profileImageName ?? 'profile.jpg',
        _profileImageBytes!,
      );
      profileImageUrl ??= 'mock://profile_images/$_profileImageName';
    }

    if (_frontIdBytes != null) {
      frontIdUrl = await _uploadToStorage(
        'id_cards',
        _frontIdName ?? 'front.jpg',
        _frontIdBytes!,
      );
      frontIdUrl ??= 'mock://id_cards/$_frontIdName';
    }

    if (_backIdBytes != null) {
      backIdUrl = await _uploadToStorage(
        'id_cards',
        _backIdName ?? 'back.jpg',
        _backIdBytes!,
      );
      backIdUrl ??= 'mock://id_cards/$_backIdName';
    }

    if (_cvBytes != null) {
      cvUrl = await _uploadToStorage('cvs', _cvName ?? 'cv.pdf', _cvBytes!);
      cvUrl ??= 'mock://cvs/$_cvName';
    }

    final data = {
      'name': _nameController.text.isNotEmpty
          ? _nameController.text
          : 'New Worker',
      'fatherName': _fatherNameController.text,
      'email': _emailController.text.isNotEmpty
          ? _emailController.text
          : 'worker@email.com',
      'phone': _phoneController.text,
      'nationalId': _nationalIdController.text,
      'religion': _religionController.text,
      'dob': _dobController.text,
      'gender': _genderController.text,
      'address': _addressController.text,
      'type1': _type1Controller.text.isNotEmpty
          ? _type1Controller.text
          : 'Full-Time',
      'position': _positionController.text.isNotEmpty
          ? _positionController.text
          : 'Employee',
      'type2': _type2Controller.text.isNotEmpty
          ? _type2Controller.text
          : 'On-Site',
      'joiningDate': _joiningDate ?? 'January 9, 2026',
      'profileImage': profileImageUrl,
      'frontId': frontIdUrl,
      'backId': backIdUrl,
      'cv': cvUrl,
    };

    bool success = false;
    String? errorMessage;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    try {
      if (widget.workerToEdit != null) {
        final editId = widget.workerToEdit!['id']?.toString();
        if (editId == null || editId.isEmpty) {
          throw StateError('Missing worker id for update');
        }
        if (isGuest) {
          final index = DummyData.workers.indexWhere((w) => w['id'] == editId);
          if (index != -1) {
            DummyData.workers[index] = {...data, 'id': editId};
          }
        } else {
          await FirestoreService().updateWorker(editId, data);
        }
      } else {
        if (isGuest) {
          final newId = 'dummy_${DateTime.now().millisecondsSinceEpoch}';
          DummyData.workers.insert(0, {...data, 'id': newId});
        } else {
          await FirestoreService().addWorker(data);
        }
      }
      success = true;
    } catch (e) {
      debugPrint('Error saving worker: $e');
      errorMessage = 'Could not save worker. Please try again.';
    }

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (success) {
      widget.onBack?.call();
    } else {
      FlashySnackBar.show(
        context,
        message: errorMessage ?? 'Could not save worker. Please try again.',
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _religionController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _addressController.dispose();
    _positionController.dispose();
    _type1Controller.dispose();
    _type2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FA), // Dashboard background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Area
          Container(
            height: 94,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => widget.onBack?.call(),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 2.0),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(0xFF000000),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Add New Worker',
                          style: TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Fill in the worker details to get started.',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Save Button (Blue state based on image 2)
                GestureDetector(
                  onTap: _isSaving ? null : _saveWorker,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: _isSaving ? Colors.grey : const Color(0xFF0B50C3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs and Form Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tabs Section
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildTopTab('Worker Detail', 0)),
                        Expanded(child: _buildTopTab('Experience', 1)),
                        Expanded(child: _buildTopTab('Documentation', 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Switch Content based on active tab
                  if (_activeTabIndex == 0)
                    WorkerDetailFormSection(
                      nameController: _nameController,
                      fatherNameController: _fatherNameController,
                      emailController: _emailController,
                      phoneController: _phoneController,
                      nationalIdController: _nationalIdController,
                      religionController: _religionController,
                      dobController: _dobController,
                      genderController: _genderController,
                      addressController: _addressController,
                      profileImageBytes: _profileImageBytes,
                      profileImageName: _profileImageName,
                      existingProfileImageUrl: _existingProfileImageUrl,
                      onUploadProfileTap: _pickProfileImage,
                      onNextStep: () => setState(() => _activeTabIndex = 1),
                    ),
                  if (_activeTabIndex == 1)
                    ExperienceFormSection(
                      positionController: _positionController,
                      type1Controller: _type1Controller,
                      type2Controller: _type2Controller,
                      selectedJoiningDate: _joiningDate,
                      onJoiningDateChanged: (date) {
                        setState(() => _joiningDate = date);
                      },
                      onNextStep: () => setState(() => _activeTabIndex = 2),
                    ),
                  if (_activeTabIndex == 2)
                    DocumentationSection(
                      frontIdBytes: _frontIdBytes,
                      frontIdName: _frontIdName,
                      existingFrontIdUrl: _existingFrontIdUrl,
                      onUploadFrontTap: _pickFrontId,
                      backIdBytes: _backIdBytes,
                      backIdName: _backIdName,
                      existingBackIdUrl: _existingBackIdUrl,
                      onUploadBackTap: _pickBackId,
                      cvBytes: _cvBytes,
                      cvName: _cvName,
                      existingCvUrl: _existingCvUrl,
                      isCvUploaded: _isCvUploaded,
                      onUploadCvTap: _pickCv,
                      onDeleteCvTap: () {
                        setState(() {
                          _cvBytes = null;
                          _cvName = null;
                          _existingCvUrl = null;
                          _isCvUploaded = false;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String title, int index) {
    bool isActive = _activeTabIndex == index;
    BorderRadiusGeometry? borderRadius;
    if (isActive) {
      if (index == 0) {
        borderRadius = const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        );
      } else if (index == 2) {
        borderRadius = const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        );
      }
    }
    return GestureDetector(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8EEF9) : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }
}

// ==========================================
// WORKER DETAIL FORM SECTION
// ==========================================
class WorkerDetailFormSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController fatherNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController nationalIdController;
  final TextEditingController religionController;
  final TextEditingController dobController;
  final TextEditingController genderController;
  final TextEditingController addressController;
  final VoidCallback? onNextStep;
  final Uint8List? profileImageBytes;
  final String? profileImageName;
  final String? existingProfileImageUrl;
  final VoidCallback? onUploadProfileTap;

  const WorkerDetailFormSection({
    super.key,
    required this.nameController,
    required this.fatherNameController,
    required this.emailController,
    required this.phoneController,
    required this.nationalIdController,
    required this.religionController,
    required this.dobController,
    required this.genderController,
    required this.addressController,
    this.onNextStep,
    this.profileImageBytes,
    this.profileImageName,
    this.existingProfileImageUrl,
    this.onUploadProfileTap,
  });

  final Color formBgGrey = const Color(0xFFF3F5F8);

  void _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onDateSelected,
  }) {
    DateTime tempPickedDate = initialDate;
    showDialog(
      context: context,
      builder: (BuildContext builder) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 320,
            height: 300,
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  import_cupertino.CupertinoButton(
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  import_cupertino.CupertinoButton(
                    child: const Text('Done', style: TextStyle(color: Color(0xFF0247C4))),
                    onPressed: () {
                      onDateSelected(tempPickedDate);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              Expanded(
                child: import_cupertino.CupertinoDatePicker(
                  mode: import_cupertino.CupertinoDatePickerMode.date,
                  initialDateTime: initialDate,
                  minimumDate: DateTime(1950),
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (DateTime newDate) {
                    tempPickedDate = newDate;
                  },
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: onNextStep,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Next Step',
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === LEFT: Input Form Area ===
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Worker Name:',
                            'Enter your name',
                            controller: nameController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Worker Father/Husband Name:',
                            'Enter your name',
                            controller: fatherNameController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Worker E-mail:',
                            'Enter your email',
                            controller: emailController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Contact no:',
                            '0000000000',
                            controller: phoneController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'National ID:',
                            'Enter your national id',
                            controller: nationalIdController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Professed Religion:',
                            'Enter your religion',
                            controller: religionController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _showCupertinoDatePicker(
                                context: context,
                                initialDate: DateTime(1990, 1, 1),
                                onDateSelected: (date) {
                                  final day = date.day.toString().padLeft(2, '0');
                                  final month = date.month.toString().padLeft(2, '0');
                                  final year = date.year.toString();
                                  dobController.text = '$day/$month/$year';
                                },
                              );
                            },
                            child: AbsorbPointer(
                              child: _buildInputField(
                                'Worker Date of Birth:',
                                '00/00/0000',
                                suffixIcon: Icons.calendar_month,
                                controller: dobController,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Gender:',
                            'Male',
                            isDropdown: true,
                            controller: genderController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInputField(
                      'Worker Address:',
                      'Enter your address',
                      isTextArea: true,
                      controller: addressController,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

            // === RIGHT: Profile Upload & Status ===
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Upload Section
                  const Text(
                    'Worker Profile',
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onUploadProfileTap,
                    child: Container(
                      height: 280,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF000000,
                            ).withValues(alpha: 0.01),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: profileImageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  profileImageBytes!,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    color: Colors.black54,
                                    child: Text(
                                      profileImageName ?? 'Profile Image',
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : existingProfileImageUrl != null &&
                                existingProfileImageUrl!.startsWith('http')
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  existingProfileImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildUploadPlaceholder(),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _buildUploadPlaceholder(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Relationship Status Section
                  const Text(
                    'Relationship Status:',
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildCustomRadio(label: 'Married', isSelected: true),
                      const SizedBox(width: 40),
                      _buildCustomRadio(label: 'Single', isSelected: false),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset('assets/Upload_profile.svg', height: 64, width: 64),
        const SizedBox(height: 12),
        const Text(
          'Upload Profile',
          style: TextStyle(
            color: Color(0xFF000000),
            fontWeight: FontWeight.w700,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap to upload a profile image\nPNG or JPG',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }
}

// ==========================================
// EXPERIENCE SECTION (IMAGE 1 + CUSTOM LEAVE)
// ==========================================
class ExperienceFormSection extends StatefulWidget {
  final TextEditingController positionController;
  final TextEditingController type1Controller;
  final TextEditingController type2Controller;
  final String? selectedJoiningDate;
  final ValueChanged<String>? onJoiningDateChanged;
  final VoidCallback? onNextStep;

  const ExperienceFormSection({
    super.key,
    required this.positionController,
    required this.type1Controller,
    required this.type2Controller,
    this.selectedJoiningDate,
    this.onJoiningDateChanged,
    this.onNextStep,
  });

  @override
  State<ExperienceFormSection> createState() => _ExperienceFormSectionState();
}

class _ExperienceFormSectionState extends State<ExperienceFormSection> {
  final Color formBgGrey = const Color(0xFFF3F5F8);
  int _selectedDay = 9;

  @override
  void initState() {
    super.initState();
    if (widget.selectedJoiningDate != null) {
      final parts = widget.selectedJoiningDate!.split(' ');
      if (parts.length >= 2) {
        final dayString = parts[1].replaceAll(',', '');
        final day = int.tryParse(dayString);
        if (day != null) {
          _selectedDay = day;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Job Experience Information',
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: widget.onNextStep,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Next Step',
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Main Grid & Right Panel (Calendar)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Form
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Job Position:',
                            'Enter your level',
                            controller: widget.positionController,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Experience Level:',
                            'Enter your level',
                            isDropdown: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Work Type:',
                            'Enter your work type',
                            isDropdown: true,
                            controller: widget.type1Controller,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Education:',
                            'Enter your education',
                            isDropdown: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Attendance Type:',
                            'Enter your attendance type',
                            isDropdown: true,
                            controller: widget.type2Controller,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(
                          child: SizedBox(),
                        ), // Empty space to match image
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Right Calendar
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Joining Date set',
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Icon(Icons.keyboard_arrow_left, size: 20),
                            Text(
                              'JANUARY20XX',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_right, size: 20),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildDayPill('SUN', true),
                            _buildDayPill('MON', false),
                            _buildDayPill('THE', false),
                            _buildDayPill('WED', false),
                            _buildDayPill('THU', false),
                            _buildDayPill('FRI', false, isGreen: true),
                            _buildDayPill('SAT', false),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Calendar Grid Mockup
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(31, (index) {
                            int day = index + 1;
                            bool isSelected = day == _selectedDay;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDay = day;
                                });
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF0B50C3)
                                      : Color(0xFFFFFFFF),
                                  border: isSelected
                                      ? null
                                      : Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$day',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected
                                        ? Color(0xFFFFFFFF)
                                        : Colors.black,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                final selectedDate =
                                    'January $_selectedDay, 2026';
                                widget.onJoiningDateChanged?.call(selectedDate);
                                FlashySnackBar.show(
                                  context,
                                  message: 'Joining date is $selectedDate',
                                  isError: false,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B50C3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Set',
                                  style: TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),

        // Salary Section
        const Text(
          'Salary Section',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: formBgGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Salary Type:',
                      'Enter your salary type',
                      isDropdown: true,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'Currency:',
                      'Enter your currency',
                      isDropdown: true,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Salary Amount:',
                      'Enter your amount',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 24),
                  const Expanded(child: SizedBox()), // empty
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Custom Leave Section (As Requested by user)
        const Text(
          'Leave Section',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: formBgGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Leave Policy:',
                      'Select policy',
                      isDropdown: true,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'Annual Leaves (Days):',
                      'e.g., 14',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Sick Leaves (Days):',
                      'e.g., 7',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'Casual Leaves (Days):',
                      'e.g., 3',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildDayPill(String text, bool isRed, {bool isGreen = false}) {
    Color bg = isRed
        ? Colors.red
        : (isGreen ? Colors.green : const Color(0xFF0B50C3));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.bold,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }
}

// ==========================================
// DOCUMENTATION SECTION (IMAGE 2)
// ==========================================
class DocumentationSection extends StatelessWidget {
  final Uint8List? frontIdBytes;
  final String? frontIdName;
  final String? existingFrontIdUrl;
  final VoidCallback? onUploadFrontTap;

  final Uint8List? backIdBytes;
  final String? backIdName;
  final String? existingBackIdUrl;
  final VoidCallback? onUploadBackTap;

  final Uint8List? cvBytes;
  final String? cvName;
  final String? existingCvUrl;
  final bool isCvUploaded;
  final VoidCallback? onUploadCvTap;
  final VoidCallback? onDeleteCvTap;

  const DocumentationSection({
    super.key,
    this.frontIdBytes,
    this.frontIdName,
    this.existingFrontIdUrl,
    this.onUploadFrontTap,
    this.backIdBytes,
    this.backIdName,
    this.existingBackIdUrl,
    this.onUploadBackTap,
    this.cvBytes,
    this.cvName,
    this.existingCvUrl,
    this.isCvUploaded = false,
    this.onUploadCvTap,
    this.onDeleteCvTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Documentation',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Side: ID Card Upload
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ID Card:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F5F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload Front Side:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildIdUploadBox(
                          label: 'Upload front side ID Card',
                          bytes: frontIdBytes,
                          fileName: frontIdName,
                          existingUrl: existingFrontIdUrl,
                          onTap: onUploadFrontTap,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Upload Back Side:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildIdUploadBox(
                          label: 'Upload back side ID Card',
                          bytes: backIdBytes,
                          fileName: backIdName,
                          existingUrl: existingBackIdUrl,
                          onTap: onUploadBackTap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 32),
            // Right Side: CV Upload Preview
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload CV:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  isCvUploaded ? _buildCvPreview(context) : _buildCvUpload(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdUploadBox({
    required String label,
    Uint8List? bytes,
    String? fileName,
    String? existingUrl,
    VoidCallback? onTap,
  }) {
    final bool hasFile =
        bytes != null || (existingUrl != null && existingUrl.isNotEmpty);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 200,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF0B50C3).withValues(alpha: 0.5)
                : Colors.grey.shade200,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: hasFile
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(bytes, fit: BoxFit.cover)
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http'))
                    Image.network(
                      existingUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else
                    _buildIdPlaceholder(label, hasFile),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black54,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              fileName ?? 'File uploaded',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.edit,
                            color: Colors.white70,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildIdPlaceholder(label, false),
      ),
    );
  }

  Widget _buildIdPlaceholder(String label, bool hasFile) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.badge,
          size: 48,
          color: hasFile ? const Color(0xFF0B50C3) : Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to select file',
          style: TextStyle(
            color: Colors.grey.shade300,
            fontSize: 12,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  Widget _buildCvUpload() {
    return _buildCvContainer(
      overlay: GestureDetector(
        onTap: onUploadCvTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Upload',
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/Upload_profile.svg',
                height: 18,
                width: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDocumentPreview(BuildContext context) {
    if (existingCvUrl != null && existingCvUrl!.isNotEmpty) {
      // Try to launch the document URL
      launchUrl(
        Uri.parse(existingCvUrl!),
        mode: LaunchMode.externalApplication,
      );
    } else if (cvBytes != null && cvName != null) {
      // Save bytes to temp file and open
      try {
        final tempDir = io.Directory.systemTemp;
        final tempFile = io.File('${tempDir.path}/$cvName');
        tempFile.writeAsBytesSync(cvBytes!);
        launchUrl(
          Uri.file(tempFile.path),
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        debugPrint('Error opening CV preview: $e');
      }
    }
  }

  Widget _buildCvPreview(BuildContext buildContext) {
    return Container(
      height: 580,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Mock CV lines background
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(height: 16, width: 200, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Container(height: 10, width: 150, color: Colors.grey.shade300),
                const SizedBox(height: 40),
                ...List.generate(
                  8,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Show uploaded document preview (PDF icon) if available
          if (cvBytes != null ||
              (existingCvUrl != null && existingCvUrl!.isNotEmpty))
            GestureDetector(
              onTap: () => _openDocumentPreview(buildContext),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.picture_as_pdf,
                    size: 120,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    cvName ?? 'Uploaded CV',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      fontFamily: 'SF Pro Display',
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to preview document',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade600,
                      fontFamily: 'SF Pro Display',
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),

          // Semi-transparent overlay
          Container(color: const Color(0xFFFFFFFF).withValues(alpha: 0.5)),
          // Foreground controls
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cvName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.description,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          cvName!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: onUploadCvTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Edit',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SvgPicture.asset(
                            'assets/edit_icon.svg',
                            height: 18,
                            width: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: onDeleteCvTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Delete',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SvgPicture.asset(
                            'assets/delete_icon.svg',
                            height: 18,
                            width: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCvContainer({required Widget overlay}) {
    return Container(
      height: 580,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(height: 16, width: 200, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Container(height: 10, width: 150, color: Colors.grey.shade300),
                const SizedBox(height: 40),
                ...List.generate(
                  8,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(color: const Color(0xFFFFFFFF).withValues(alpha: 0.5)),
          overlay,
        ],
      ),
    );
  }
}

// ==========================================
// FILE-LEVEL SHARED HELPERS
// ==========================================
Widget _buildInputField(
  String label,
  String hint, {
  IconData? suffixIcon,
  bool isDropdown = false,
  bool isTextArea = false,
  TextEditingController? controller,
  TextAlign textAlign = TextAlign.start,
}) {
  final isAmount = label.toLowerCase().contains('amount');
  final isLeaves = label.toLowerCase().contains('leaves');
  final isNumeric = isAmount || isLeaves;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'SF Pro Display',
        ),
      ),
      const SizedBox(height: 8),
      Container(
        height: isTextArea ? 90 : 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: isTextArea ? Alignment.topLeft : Alignment.center,
        child: TextField(
          textAlign: textAlign,
          maxLines: isTextArea ? 4 : 1,
          controller: controller,
          keyboardType: isNumeric
              ? (isAmount
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number)
              : null,
          inputFormatters: isNumeric
              ? [
                  FilteringTextInputFormatter.allow(
                    isAmount ? RegExp(r'^\d*\.?\d*') : RegExp(r'^\d*'),
                  ),
                ]
              : null,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: isTextArea
                ? const EdgeInsets.only(top: 14)
                : const EdgeInsets.symmetric(vertical: 12),
            suffixIcon: isDropdown
                ? Icon(
                    Icons.arrow_drop_down,
                    color: Colors.grey.shade400,
                    size: 22,
                  )
                : (suffixIcon != null
                      ? Icon(suffixIcon, color: Colors.grey.shade400, size: 22)
                      : null),
          ),
        ),
      ),
    ],
  );
}

Widget _buildCustomRadio({required String label, required bool isSelected}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Color(0xFF000000), width: 2),
        ),
        child: isSelected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF000000),
                  ),
                ),
              )
            : const SizedBox(),
      ),
      const SizedBox(width: 10),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 16,
          fontWeight: FontWeight.w500,
          fontFamily: 'SF Pro Display',
        ),
      ),
    ],
  );
}
