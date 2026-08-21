import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoIcons;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/workers/worker_form_fields.dart';

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
  final bool isChecking;
  final Uint8List? profileImageBytes;
  final String? profileImageName;
  final String? existingProfileImageUrl;
  final VoidCallback? onUploadProfileTap;
  final VoidCallback? onDeleteProfileTap;
  final String relationshipStatus;
  final ValueChanged<String> onRelationshipStatusChanged;
  final ValueChanged<DateTime>? onDobChanged;

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
    this.isChecking = false,
    this.profileImageBytes,
    this.profileImageName,
    this.existingProfileImageUrl,
    this.onUploadProfileTap,
    this.onDeleteProfileTap,
    required this.relationshipStatus,
    required this.onRelationshipStatusChanged,
    this.onDobChanged,
  });

  final Color formBgGrey = const Color(0xFFF2F3F6);

  void _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onDateSelected,
  }) {
    final now = DateTime.now();
    final maximumDate = DateTime(now.year - 18, now.month, now.day);
    DateTime selected = initialDate;
    bool popped = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'date_picker'.tr(),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        void safePop([VoidCallback? action]) {
          if (popped) return;
          popped = true;
          action?.call();
          final nav = Navigator.of(ctx);
          if (nav.canPop()) {
            nav.pop();
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 12 * anim.value,
                  sigmaY: 12 * anim.value,
                ),
                child: FadeTransition(
                  opacity: anim,
                  child: Container(
                    color: const Color(0xFF0247C4).withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
            ScaleTransition(
              scale: curve,
              child: FadeTransition(
                opacity: anim,
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 40,
                  ),
                  child: Center(
                    child: StatefulBuilder(
                      builder: (_, setPickerState) {
                        return Container(
                          width: 380,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0247C4,
                                ).withValues(alpha: 0.18),
                                blurRadius: 40,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.calendar,
                                      size: 20,
                                      color: Color(0xFF0247C4),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'date_of_birth'.tr(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.exclamationmark_circle,
                                      size: 14,
                                      color: Color(0xFF6B7280),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'worker_must_be_18'.tr(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 200,
                                child: CupertinoDatePicker(
                                  mode: CupertinoDatePickerMode.date,
                                  initialDateTime: initialDate,
                                  minimumDate: DateTime(1950),
                                  maximumDate: maximumDate,
                                  onDateTimeChanged: (DateTime newDate) {
                                    setPickerState(() {
                                      selected = newDate;
                                    });
                                  },
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => safePop(),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3F4F6),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'cancel'.tr(),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF374151),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          safePop(() => onDateSelected(selected));
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0247C4),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'done'.tr(),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
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
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'personal_information'.tr(),
              style: const TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            GestureDetector(
              onTap: onNextStep,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FD),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: Row(
                  children: [
                    Text(
                      'next_step'.tr(),
                      style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
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
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'worker_name_label'.tr(),
                            'enter_your_name'.tr(),
                            controller: nameController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildInputField(
                            'worker_father_husband_name'.tr(),
                            'hint_enter_father_name'.tr(),
                            controller: fatherNameController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'worker_email'.tr(),
                            'enter_your_email'.tr(),
                            controller: emailController,
                            isEmail: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildInputField(
                            'contact_no_label'.tr(),
                            'enter_contact_number'.tr(),
                            controller: phoneController,
                            isContact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'national_id'.tr(),
                            'hint_enter_national_id'.tr(),
                            controller: nationalIdController,
                            isNationalId: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildInputField(
                            'religion_title'.tr(),
                            'enter_your_religion'.tr(),
                            controller: religionController,
                            isReligion: true,
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
                              final now = DateTime.now();
                              final minimumDob = DateTime(1950);
                              final maximumDob = DateTime(
                                now.year - 18,
                                now.month,
                                now.day,
                              );
                              final dobText = dobController.text.trim();
                              final parsedDob =
                                  AppDateUtils.parseDdMmYyyy(dobText) ??
                                  AppDateUtils.parseDateString(dobText);
                              final initialDob = parsedDob == null
                                  ? maximumDob
                                  : parsedDob.isBefore(minimumDob)
                                  ? minimumDob
                                  : parsedDob.isAfter(maximumDob)
                                  ? maximumDob
                                  : parsedDob;
                              _showCupertinoDatePicker(
                                context: context,
                                initialDate: initialDob,
                                onDateSelected: (date) {
                                  final day = date.day.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  final month = date.month.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  final year = date.year.toString();
                                  dobController.text = '$day/$month/$year';
                                  onDobChanged?.call(
                                    DateTime(date.year, date.month, date.day),
                                  );
                                },
                              );
                            },
                            child: AbsorbPointer(
                              child: buildInputField(
                                'worker_dob'.tr(),
                                'date_format'.tr(),
                                suffixIcon: Icons.calendar_month,
                                controller: dobController,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildDropdownField(
                            label: 'gender_label'.tr(),
                            selectedValue: genderController.text,
                            hint: 'enter_gender'.tr(),
                            items: const ['Male', 'Female', 'Other'],
                            itemLabelBuilder: (val) => _localizeGender(val),
                            onChanged: (val) {
                              if (val != null) {
                                genderController.text = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    buildInputField(
                      'worker_address'.tr(),
                      'enter_your_address'.tr(),
                      isTextArea: true,
                      controller: addressController,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'worker_profile'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onUploadProfileTap,
                    child: Container(
                      height: 360,
                      width: 360,
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
                      child: _buildProfileContent(context),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'relationship_status'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: buildCustomRadio(
                          label: 'married'.tr(),
                          isSelected: relationshipStatus == 'Married',
                          onTap: () => onRelationshipStatusChanged('Married'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: buildCustomRadio(
                          label: 'single'.tr(),
                          isSelected: relationshipStatus == 'Single',
                          onTap: () => onRelationshipStatusChanged('Single'),
                        ),
                      ),
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

  Widget _buildProfileContent(BuildContext context) {
    final hasImageBytes = profileImageBytes != null;
    final hasImageUrl =
        existingProfileImageUrl != null && existingProfileImageUrl!.isNotEmpty;

    if (!hasImageBytes && !hasImageUrl) return _buildUploadPlaceholder();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImageBytes)
          Image.memory(
            profileImageBytes!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildUploadPlaceholder(),
          )
        else
          Image(
            image: resolveImageProvider(existingProfileImageUrl),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildUploadPlaceholder(),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.black.withValues(alpha: 0.54),
            child: Text(
              profileImageName ?? 'worker_profile'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        if (onDeleteProfileTap != null)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () {
                bool popped = false;
                showGeneralDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: 'RemoveProfileImage',
                  barrierColor: Colors.transparent,
                  transitionDuration: const Duration(milliseconds: 400),
                  pageBuilder: (dialogContext, animation, secondaryAnimation) =>
                      const SizedBox(),
                  transitionBuilder:
                      (dialogContext, animation, secondaryAnimation, child) {
                        final curve = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        );
                        void safePop([VoidCallback? action]) {
                          if (popped) return;
                          popped = true;
                          action?.call();
                          final nav = Navigator.of(dialogContext);
                          if (nav.canPop()) {
                            nav.pop();
                          }
                        }

                        return Stack(
                          children: [
                            Positioned.fill(
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 12 * animation.value,
                                  sigmaY: 12 * animation.value,
                                ),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: Container(
                                    color: const Color(0xFF0247C4).withValues(alpha: 0.18),
                                  ),
                                ),
                              ),
                            ),
                            FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: curve,
                                child: Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: Container(
                                    width: 380,
                                    padding: const EdgeInsets.all(28),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFFFF),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF000000,
                                          ).withValues(alpha: 0.15),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 64,
                                          height: 64,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFEE2E2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.warning_rounded,
                                              color: Color(0xFFEF4444),
                                              size: 36,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'remove_profile_image'.tr(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF000000),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'remove_profile_image_desc'.tr(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w400,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 28),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () => safePop(),
                                                behavior: HitTestBehavior.opaque,
                                                child: Container(
                                                  height: 48,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFF1F5F9,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    'cancel'.tr(),
                                                    style: const TextStyle(
                                                      color: Color(0xFF000000),
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      fontFamily: 'SF Pro',
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () {
                                                  safePop(() {
                                                    onDeleteProfileTap?.call();
                                                  });
                                                },
                                                behavior: HitTestBehavior.opaque,
                                                child: Container(
                                                  height: 48,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFEF4444,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(
                                                          0xFFEF4444,
                                                        ).withValues(alpha: 0.2),
                                                        blurRadius: 8,
                                                        offset: const Offset(
                                                          0,
                                                          4,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    'remove'.tr(),
                                                    style: const TextStyle(
                                                      color: Color(0xFFFFFFFF),
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      fontFamily: 'SF Pro',
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                );
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.54),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
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
        Text(
          'upload_profile'.tr(),
          style: const TextStyle(
            color: Color(0xFF000000),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'tap_to_upload_profile_image'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.54),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _localizeGender(String value) =>
      LocalizationHelper.localizeGender(value);
}
