import 'dart:io' as io;
import 'dart:ui';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/upload_service.dart';
import '../widgets/clickable_gesture_detector.dart';
import '../widgets/sidebar_widget.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_utils.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../widgets/custom_dropdown_field.dart';
import '../utils/delete_dialog.dart';
import '../utils/rate_us_helper.dart';

class AddNewWorkerScreen extends StatefulWidget {
  const AddNewWorkerScreen({super.key});

  @override
  State<AddNewWorkerScreen> createState() => _AddNewWorkerScreenState();
}

class _AddNewWorkerScreenState extends State<AddNewWorkerScreen> {
  final Color textDark = const Color(0xFF000000);
  final Color formBgGrey = const Color(0xFFF3F5F8);

  final TextEditingController nameController = TextEditingController();
  final TextEditingController fatherNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController contactController = TextEditingController();
  final TextEditingController nationalIdController = TextEditingController();
  final TextEditingController religionController = TextEditingController();
  final TextEditingController dobController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  bool isMarried = true;
  bool isLoading = false; // Loading state for Firebase operation

  Uint8List? _profileImageBytes;
  String? _profileImageName;
  String selectedGender = 'Male';

  @override
  void dispose() {
    nameController.dispose();
    fatherNameController.dispose();
    emailController.dispose();
    contactController.dispose();
    nationalIdController.dispose();
    religionController.dispose();
    dobController.dispose();
    addressController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        if (file.bytes != null && file.bytes!.length > 10 * 1024 * 1024) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
              isError: true,
            );
          }
          return;
        }
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
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_pick_image'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _removeProfileImage() async {
    final confirm = await DeleteDialog.show(
      context: context,
      title: 'remove_profile_image'.tr(),
      content: 'remove_profile_image_desc'.tr(),
      confirmButtonText: 'remove',
    );
    if (confirm && mounted) {
      setState(() {
        _profileImageBytes = null;
        _profileImageName = null;
      });
    }
  }

  Future<void> _handleSave() async {
    if (nameController.text.isEmpty || contactController.text.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_name_contact'.tr(),
        isError: true,
      );
      return;
    }

    if (_profileImageBytes == null) {
      FlashySnackBar.show(
        context,
        message: 'please_upload_profile_image'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    final dobStr = dobController.text.trim();
    if (dobStr.isNotEmpty) {
      final dob = AppDateUtils.parseDateString(dobStr);
      if (dob == null) {
        FlashySnackBar.show(
          context,
          message: 'invalid_date_format'.tr(),
          isError: true,
        );
        return;
      }
      final cutoff = DateTime.now().subtract(const Duration(days: 365 * 18));
      if (dob.isAfter(cutoff)) {
        FlashySnackBar.show(
          context,
          message: 'worker_must_be_18'.tr(),
          isError: true,
        );
        return;
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      String? profileImageUrl;
      if (_profileImageBytes != null) {
        final isGuest = AuthService().currentUser?.isAnonymous ?? false;
        if (isGuest) {
          profileImageUrl =
              'data:image/jpeg;base64,${base64Encode(_profileImageBytes!)}';
        } else {
          final results = await UploadService.uploadFiles(
            files: [
              UploadFile(
                folder: 'profile_images',
                fileName: _profileImageName ?? 'profile.jpg',
                bytes: _profileImageBytes!,
                mimeType: 'image/jpeg',
              ),
            ],
          );
          if (results.first.isSuccess) {
            profileImageUrl = results.first.url;
          } else {
            if (mounted) {
              FlashySnackBar.show(
                context,
                message: 'file_upload_failed'.tr(
                  namedArgs: {'file': _profileImageName ?? 'profile.jpg'},
                ),
                isError: true,
              );
            }
          }
          profileImageUrl ??=
              'data:image/jpeg;base64,${base64Encode(_profileImageBytes!)}';
        }
      }

      // Pushing data via FirestoreService (user-scoped collection)
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        // Guests use local DummyData only — no Firebase
        final newWorker = {
          'name': nameController.text.trim(),
          'fatherName': fatherNameController.text.trim(),
          'email': emailController.text.trim(),
          'phone': contactController.text.trim(),
          'nationalId': nationalIdController.text.trim(),
          'religion': religionController.text.trim(),
          'dob': dobController.text.trim(),
          'address': addressController.text.trim(),
          'relationshipStatus': isMarried ? 'Married' : 'Single',
          'gender': selectedGender,
          'position': 'Employee',
          'type1': 'Full-Time',
          'type2': 'On-Site',
          'profileImage': profileImageUrl,
          'id': 'dummy_${DateTime.now().millisecondsSinceEpoch}',
        };
        DummyData.workers.add(newWorker);
        await DummyData.saveToPrefs();
      } else {
        await FirestoreService().addWorker({
          'name': nameController.text.trim(),
          'fatherName': fatherNameController.text.trim(),
          'email': emailController.text.trim(),
          'phone': contactController.text.trim(),
          'nationalId': nationalIdController.text.trim(),
          'religion': religionController.text.trim(),
          'dob': dobController.text.trim(),
          'address': addressController.text.trim(),
          'relationshipStatus': isMarried ? 'Married' : 'Single',
          'gender': selectedGender,
          'position': 'Employee',
          'type1': 'Full-Time',
          'type2': 'On-Site',
          'profileImage': profileImageUrl,
        });
      }

      if (mounted) {
        FlashySnackBar.show(context, message: 'worker_added_successfully'.tr());
        _clearForm();
      }
      if (context.mounted) {
        tryShowFirstMilestoneRateUs(context, 'worker');
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_saving_data'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _clearForm() {
    nameController.clear();
    fatherNameController.clear();
    emailController.clear();
    contactController.clear();
    nationalIdController.clear();
    religionController.clear();
    dobController.clear();
    addressController.clear();
    setState(() {
      isMarried = true;
      selectedGender = 'Male';
      _profileImageBytes = null;
      _profileImageName = null;
    });
  }

  void _safePop() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Row(
        children: [
          SidebarWidget(
            key: ValueKey('sidebar_${context.locale.languageCode}'),
            selectedIndex: 1,
            isGuest: AuthService().currentUser?.isAnonymous ?? false,
            onItemSelected: (index, {subIndex}) {
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => HomeScreen(
                    initialIndex: index,
                    initialSubIndex: subIndex ?? 0,
                  ),
                ),
                (route) => false,
              );
            },
            onBackToLogin: () {
              AuthService().signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: _safePop,
                              child: const Padding(
                                padding: EdgeInsets.only(top: 2.0),
                                child: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Color(0xFF000000),
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'add_new_worker'.tr(),
                                style: TextStyle(
                                  color: textDark,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'fill_worker_details'.tr(),
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
                      InkWell(
                        onTap: isLoading ? null : _handleSave,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          height: 44,
                          width:
                              100, // Fixed width so it doesn't shrink when loading
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: isLoading
                                ? const Color(0xFFD0D5DD)
                                : const Color(0xFFE8EDF8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF000000),
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'save'.tr(),
                                  style: TextStyle(
                                    color: Color(0xFF000000),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Tabs Section ---
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(
                                    0xFF000000,
                                  ).withValues(alpha: 0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildTopTab(
                                    'worker_detail'.tr(),
                                    isActive: true,
                                  ),
                                ),
                                Expanded(
                                  child: _buildTopTab('experience'.tr()),
                                ),
                                Expanded(
                                  child: _buildTopTab('documentation'.tr()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'personal_information'.tr(),
                                style: TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(0xFFFFFFFF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFE0E0E0),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'next_step'.tr(),
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
                            ],
                          ),
                          const SizedBox(height: 24),

                          // --- Form Grid & Right Panel ---
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
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildInputField(
                                              'worker_name_label'.tr(),
                                              'enter_name'.tr(),
                                              controller: nameController,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            child: _buildInputField(
                                              'worker_father_husband_name'.tr(),
                                              'enter_name'.tr(),
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
                                              'worker_email'.tr(),
                                              'enter_email'.tr(),
                                              controller: emailController,
                                              isEmail: true,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            child: _buildInputField(
                                              'contact_no_label'.tr(),
                                              'enter_contact_number'.tr(),
                                              controller: contactController,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildInputField(
                                              'national_id'.tr(),
                                              'enter_national_id'.tr(),
                                              controller: nationalIdController,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            child: _buildInputField(
                                              'professed_religion'.tr(),
                                              'enter_religion'.tr(),
                                              controller: religionController,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildInputField(
                                              'worker_dob'.tr(),
                                              'date_format'.tr(),
                                              suffixIcon: Icons.calendar_month,
                                              controller: dobController,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            child: CustomDropdownField(
                                              label: 'gender_label'.tr(),
                                              selectedValue: selectedGender,
                                              hint: 'enter_gender'.tr(),
                                              items: const [
                                                'Male',
                                                'Female',
                                                'Other',
                                              ],
                                              itemLabelBuilder: (val) =>
                                                  val.toLowerCase().tr(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  setState(() {
                                                    selectedGender = val;
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      _buildInputField(
                                        'worker_address'.tr(),
                                        'enter_address'.tr(),
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
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: formBgGrey,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'worker_profile'.tr(),
                                        style: TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      GestureDetector(
                                        onTap: _pickProfileImage,
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Container(
                                            height: 240,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: Color(0xFFFFFFFF),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Color(
                                                    0xFF000000,
                                                  ).withValues(alpha: 0.01),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: _profileImageBytes != null
                                                ? Stack(
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                        child: Image.memory(
                                                          _profileImageBytes!,
                                                          height: 240,
                                                          width:
                                                              double.infinity,
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                      // Cross/close icon (top-right)
                                                      Positioned(
                                                        top: 8,
                                                        right: 8,
                                                        child: GestureDetector(
                                                          onTap: () =>
                                                              _removeProfileImage(),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  6,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Colors
                                                                      .black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.6,
                                                                      ),
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                            child: const Icon(
                                                              Icons.close,
                                                              color:
                                                                  Colors.white,
                                                              size: 18,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Image.asset(
                                                        'assets/profileimage.png',
                                                        height: 64,
                                                        width: 64,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) => const Icon(
                                                              Icons.person,
                                                              size: 64,
                                                              color:
                                                                  Colors.grey,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Text(
                                                        'upload_profile'.tr(),
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF000000,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 14,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        'upload_profile_hint'
                                                            .tr(),
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 32),

                                      // Relationship Status Section
                                      Text(
                                        'relationship_status'.tr(),
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
                                          _buildCustomRadio(
                                            label: 'married'.tr(),
                                            isSelected: isMarried,
                                            onTap: () {
                                              setState(() => isMarried = true);
                                            },
                                          ),
                                          const SizedBox(width: 40),
                                          _buildCustomRadio(
                                            label: 'single'.tr(),
                                            isSelected: !isMarried,
                                            onTap: () {
                                              setState(() => isMarried = false);
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String title, {bool isActive = false}) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8EEF9) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
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
    );
  }

  Widget _buildInputField(
    String label,
    String hint, {
    IconData? suffixIcon,
    bool isTextArea = false,
    bool isEmail = false,
    TextEditingController? controller,
  }) {
    final isNumeric =
        label.toLowerCase().contains('contact') ||
        label.toLowerCase().contains('phone') ||
        label.toLowerCase().contains('national');
    final isEmailField = isEmail || label.toLowerCase().contains('mail');
    final isReligion = label.toLowerCase().contains('religion');

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
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: isTextArea ? Alignment.topLeft : Alignment.center,
          child: TextField(
            controller: controller,
            maxLines: isTextArea ? 4 : 1,
            keyboardType: isNumeric ? TextInputType.number : null,
            inputFormatters: isNumeric
                ? [
                    FilteringTextInputFormatter.allow(
                      label.toLowerCase().contains('national')
                          ? RegExp(r'^[\d_-]*')
                          : RegExp(r'^\d*'),
                    ),
                    if (label.toLowerCase().contains('phone') ||
                        label.toLowerCase().contains('contact'))
                      LengthLimitingTextInputFormatter(20),
                    if (label.toLowerCase().contains('national'))
                      LengthLimitingTextInputFormatter(15),
                  ]
                : isEmailField
                ? [LengthLimitingTextInputFormatter(100)]
                : isReligion
                ? [LengthLimitingTextInputFormatter(30)]
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
                  : EdgeInsets.zero,
              suffixIcon: suffixIcon != null
                  ? Icon(suffixIcon, color: Colors.grey.shade400, size: 22)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomRadio({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
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
        ),
      ),
    );
  }
}
