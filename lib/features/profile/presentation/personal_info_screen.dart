import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../domain/rider_profile.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  static const _saveDelay = Duration(seconds: 2);

  final _nameController = TextEditingController();
  final _userNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _selectedPhotoBytes;
  bool _loadingDialogVisible = false;

  bool get _canSave {
    return _nameController.text.trim().isNotEmpty &&
        _userNameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().length == 10;
  }

  @override
  void initState() {
    super.initState();
    _populateExistingProfile();
    _nameController.addListener(_onFieldChanged);
    _userNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _populateExistingProfile() {
    final profile = RiderProfileStore.instance.profile.value;
    if (!profile.hasCompletedPersonalInfo) {
      return;
    }

    _nameController.text = profile.fullName;
    _userNameController.text = profile.userName;
    _phoneController.text = _localPhoneDigits(profile.phoneNumber);
    _selectedPhotoBytes = profile.photoBytes;
  }

  void _onFieldChanged() {
    setState(() {});
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 900,
      );
      if (photo == null) {
        return;
      }

      final bytes = await photo.readAsBytes();
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedPhotoBytes = bytes;
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Unable to open your photo library.'),
        ),
      );
    } on Object {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to select a profile photo.')),
      );
    }
  }

  Future<void> _saveChanges() async {
    if (!_canSave) {
      return;
    }

    _showLoadingDialog();
    await Future<void>.delayed(_saveDelay);

    if (!mounted) {
      _dismissLoadingDialog();
      return;
    }

    final previousProfile = RiderProfileStore.instance.profile.value;
    await RiderProfileStore.instance.update(
      previousProfile.copyWith(
        fullName: _nameController.text.trim(),
        userName: _cleanUserName(_userNameController.text),
        phoneNumber: _formatPhoneNumber(_phoneController.text),
        photoBytes: _selectedPhotoBytes ?? previousProfile.photoBytes,
        hasCompletedPersonalInfo: true,
      ),
    );

    if (!mounted) {
      return;
    }

    _dismissLoadingDialog();

    final done = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (sheetContext) {
        return _ProfileUpdatedSheet(
          onDone: () => Navigator.of(sheetContext).pop(true),
        );
      },
    );

    if (!mounted || done != true) {
      return;
    }

    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _showLoadingDialog() {
    _loadingDialogVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.74),
        builder: (dialogContext) {
          return const _ProfileLoadingDialog();
        },
      ).whenComplete(() {
        _loadingDialogVisible = false;
      }),
    );
  }

  void _dismissLoadingDialog() {
    if (!_loadingDialogVisible || !mounted) {
      return;
    }

    _loadingDialogVisible = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final existingProfile = RiderProfileStore.instance.profile.value;
    final selectedPhoto = _selectedPhotoBytes ?? existingProfile.photoBytes;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.citirideBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.citirideBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.citirideBlack,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppColors.citirideBlack,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 19, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PersonalInfoHeader(onBack: _goBack),
                      const SizedBox(height: 27),
                      const _FieldLabel('Profile photo'),
                      const SizedBox(height: 10),
                      _ProfilePhotoCard(
                        photoBytes: selectedPhoto,
                        onUpload: _pickProfilePhoto,
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Name'),
                      const SizedBox(height: 10),
                      _ProfileTextField(
                        key: const ValueKey('profile-name-field'),
                        controller: _nameController,
                        hintText: 'Enter full name',
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('User name'),
                      const SizedBox(height: 10),
                      _ProfileTextField(
                        key: const ValueKey('profile-username-field'),
                        controller: _userNameController,
                        hintText: 'Enter username',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Phone number'),
                      const SizedBox(height: 10),
                      _PhoneNumberField(controller: _phoneController),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  10,
                  22,
                  MediaQuery.paddingOf(context).bottom + 48,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('profile-save-button'),
                    onPressed: _canSave ? _saveChanges : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.citirideYellow,
                      disabledBackgroundColor: const Color(0xFF918B00),
                      foregroundColor: AppColors.citirideBlack,
                      disabledForegroundColor: AppColors.citirideBlack
                          .withValues(alpha: 0.66),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Save changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cleanUserName(String value) {
    return value.trim().replaceFirst(RegExp(r'^@+'), '');
  }

  static String _localPhoneDigits(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10 && digits.startsWith('234')) {
      return digits.substring(digits.length - 10);
    }

    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  static String _formatPhoneNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      return '+234 $digits';
    }

    return '+234 ${digits.substring(0, 3)} '
        '${digits.substring(3, 7)} ${digits.substring(7)}';
  }
}

class _PersonalInfoHeader extends StatelessWidget {
  const _PersonalInfoHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              iconSize: 25,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              tooltip: 'Back',
            ),
          ),
          const Text(
            'Personal info',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0,
      ),
    );
  }
}

class _ProfilePhotoCard extends StatelessWidget {
  const _ProfilePhotoCard({required this.photoBytes, required this.onUpload});

  final Uint8List? photoBytes;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: AppColors.citirideYellow, width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB9D1),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 2),
            ),
            child: ClipOval(
              child: photoBytes == null
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CompatibleSvgPicture.asset(
                        'assets/images/Profile.svg',
                        fit: BoxFit.contain,
                        semanticsLabel: 'Profile photo preview',
                      ),
                    )
                  : Image.memory(photoBytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 30,
            child: TextButton(
              key: const ValueKey('profile-upload-photo-button'),
              onPressed: onUpload,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF242431),
                foregroundColor: AppColors.citirideYellow,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                'Upload photo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return _InputShell(
      child: TextField(
        controller: controller,
        cursorColor: AppColors.citirideYellow,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF8F8F8F),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
          filled: false,
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _PhoneNumberField extends StatelessWidget {
  const _PhoneNumberField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _InputShell(
      child: Row(
        children: [
          const SizedBox(width: 16),
          const SizedBox(
            width: 28,
            height: 18,
            child: CompatibleSvgPicture.asset(
              'assets/images/Nigerian flag.svg',
              fit: BoxFit.fill,
              semanticsLabel: 'Nigeria flag',
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF9D9D9D),
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              key: const ValueKey('profile-phone-field'),
              controller: controller,
              cursorColor: AppColors.citirideYellow,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
              decoration: const InputDecoration(
                hintText: '123 4567 890',
                hintStyle: TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
                filled: false,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _InputShell extends StatelessWidget {
  const _InputShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.white, width: 2),
      ),
      child: child,
    );
  }
}

class _ProfileLoadingDialog extends StatelessWidget {
  const _ProfileLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Updating profile',
        child: Container(
          width: 156,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: AppColors.citirideYellow,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Please wait',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileUpdatedSheet extends StatelessWidget {
  const _ProfileUpdatedSheet({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AnimatedSuccessCheck(),
              const SizedBox(height: 16),
              const Text(
                'Profile updated successfully',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your personal information has been saved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.citirideYellow,
                    foregroundColor: AppColors.citirideBlack,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedSuccessCheck extends StatelessWidget {
  const _AnimatedSuccessCheck();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 760),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(scale: value.clamp(0.0, 1.0), child: child);
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: Color(0xFF1DDB5B),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: AppColors.white, size: 42),
      ),
    );
  }
}
