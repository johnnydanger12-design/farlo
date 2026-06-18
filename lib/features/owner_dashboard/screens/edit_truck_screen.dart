import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../services/storage_service.dart';
import '../../bookings/widgets/places_autocomplete_field.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

class EditTruckScreen extends ConsumerStatefulWidget {
  const EditTruckScreen({super.key});

  @override
  ConsumerState<EditTruckScreen> createState() => _EditTruckScreenState();
}

class _EditTruckScreenState extends ConsumerState<EditTruckScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cuisineCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _instagramCtrl;
  late final TextEditingController _tiktokCtrl;
  late final TextEditingController _facebookCtrl;
  late final TextEditingController _twitterCtrl;
  late final TextEditingController _youtubeCtrl;
  late final TextEditingController _websiteCtrl;

  late final TextEditingController _addressCtrl;
  late final TextEditingController _otherCuisineCtrl;
  int? _cancellationPolicyHours;
  bool _ordersEnabled = false;
  String _businessType = 'mobile';
  double? _staticLat;
  double? _staticLng;
  bool _loading = false;
  bool _initialized = false;

  // Existing URLs from DB
  String? _existingLogoUrl;
  List<String> _existingPhotoUrls = [];

  // Newly picked local files (null = no change for that slot)
  File? _newLogo;
  // Up to 10 photo slots; null = keep existing
  final List<File?> _newPhotos = List.filled(10, null);

  static const List<String> _cuisineOptions = [
    'American', 'Mexican', 'Asian', 'BBQ', 'Pizza', 'Burgers',
    'Sandwiches', 'Seafood', 'Mediterranean', 'Indian',
    'Thai', 'Korean', 'Vegan', 'Desserts', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _cuisineCtrl = TextEditingController();
    _otherCuisineCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _instagramCtrl = TextEditingController();
    _tiktokCtrl = TextEditingController();
    _facebookCtrl = TextEditingController();
    _twitterCtrl = TextEditingController();
    _youtubeCtrl = TextEditingController();
    _websiteCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cuisineCtrl.dispose();
    _descCtrl.dispose();
    _instagramCtrl.dispose();
    _tiktokCtrl.dispose();
    _facebookCtrl.dispose();
    _twitterCtrl.dispose();
    _youtubeCtrl.dispose();
    _websiteCtrl.dispose();
    _addressCtrl.dispose();
    _otherCuisineCtrl.dispose();
    super.dispose();
  }

  void _initFromTruck() {
    if (_initialized) return;
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    _nameCtrl.text = truck.name;
    if (_cuisineOptions.contains(truck.cuisineType)) {
      _cuisineCtrl.text = truck.cuisineType;
    } else {
      _cuisineCtrl.text = 'Other';
      _otherCuisineCtrl.text = truck.cuisineType;
    }
    _descCtrl.text = truck.description ?? '';
    _existingLogoUrl = truck.logoUrl;
    _existingPhotoUrls = List<String>.from(truck.photoUrls);
    _instagramCtrl.text = truck.socialInstagram ?? '';
    _tiktokCtrl.text = truck.socialTiktok ?? '';
    _facebookCtrl.text = truck.socialFacebook ?? '';
    _twitterCtrl.text = truck.socialTwitter ?? '';
    _youtubeCtrl.text = truck.socialYoutube ?? '';
    _websiteCtrl.text = truck.websiteUrl ?? '';
    _cancellationPolicyHours = truck.cancellationPolicyHours;
    _ordersEnabled = truck.ordersEnabled;
    _businessType = truck.businessType;
    _addressCtrl.text = truck.address ?? '';
    _staticLat = truck.latitude;
    _staticLng = truck.longitude;
    _initialized = true;
  }

  Future<void> _pickLogo() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile != null) setState(() => _newLogo = File(xfile.path));
  }

  Future<void> _pickPhoto(int index) async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile != null) setState(() => _newPhotos[index] = File(xfile.path));
  }

  void _removePhoto(int index) {
    setState(() {
      if (index < _existingPhotoUrls.length) {
        _existingPhotoUrls.removeAt(index);
      }
      _newPhotos[index] = null;
    });
  }

  void _toggleOrdersEnabled(bool val) {
    setState(() => _ordersEnabled = val);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final storage = storageServiceInstance;
      String? handle(TextEditingController c) {
        final v = c.text.trim().replaceAll(RegExp(r'^@'), '');
        return v.isEmpty ? null : v;
      }

      final fields = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'cuisine_type': _cuisineCtrl.text == 'Other'
            ? (_otherCuisineCtrl.text.trim().isEmpty ? 'Other' : _otherCuisineCtrl.text.trim())
            : _cuisineCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'social_instagram': handle(_instagramCtrl),
        'social_tiktok': handle(_tiktokCtrl),
        'social_facebook': handle(_facebookCtrl),
        'social_twitter': handle(_twitterCtrl),
        'social_youtube': handle(_youtubeCtrl),
        'website_url': _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
        'cancellation_policy_hours': _cancellationPolicyHours,
        'orders_enabled': _ordersEnabled,
        'business_type': _businessType,
        if (_businessType == 'fixed') ...{
          'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          'latitude': _staticLat,
          'longitude': _staticLng,
        },
      };

      // Upload logo if changed
      if (_newLogo != null) {
        final url = await storage.uploadImage(
          SupabaseConstants.truckLogosBucket,
          _newLogo!,
          ownerId: user.id,
        );
        fields['logo_url'] = url;
      }

      // Build final photo_urls list: existing kept + new uploads
      final photoUrls = List<String>.from(_existingPhotoUrls);
      for (int i = 0; i < _newPhotos.length; i++) {
        final file = _newPhotos[i];
        if (file != null) {
          final url = await storage.uploadImage(
            SupabaseConstants.truckPhotosBucket,
            file,
            ownerId: user.id,
          );
          if (i < photoUrls.length) {
            photoUrls[i] = url; // replace slot
          } else {
            photoUrls.add(url); // new slot
          }
        }
      }
      fields['photo_urls'] = photoUrls;

      await ref.read(ownerTruckProvider.notifier).updateProfile(fields);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: AppColors.openGreen,
            duration: Duration(seconds: 2),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTruck = ref.watch(ownerTruckProvider);
    _initFromTruck();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo picker
                Text('Truck Logo', style: AppTextStyles.heading3),
                const SizedBox(height: 2),
                const Text('Shown as your marker on the map', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.sm),
                _LogoPicker(
                  existingUrl: _existingLogoUrl,
                  newFile: _newLogo,
                  onTap: _pickLogo,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Truck name
                AppTextField(
                  controller: _nameCtrl,
                  label: 'Truck Name',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: AppSpacing.md),

                // Cuisine
                _CuisineDropdown(
                  value: _cuisineCtrl.text.isEmpty ? 'Other' : _cuisineCtrl.text,
                  options: _cuisineOptions,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _cuisineCtrl.text = val;
                        if (val != 'Other') _otherCuisineCtrl.clear();
                      });
                    }
                  },
                ),
                if (_cuisineCtrl.text == 'Other') ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    controller: _otherCuisineCtrl,
                    label: 'Specify your business type',
                    hint: 'e.g. Coffee Shop, Bakery, Thai Fusion…',
                    textInputAction: TextInputAction.next,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),

                // Description
                AppTextField(
                  controller: _descCtrl,
                  label: 'Description (optional)',
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Photos (up to 10)
                Text('Photos (up to 10)', style: AppTextStyles.heading3),
                const SizedBox(height: AppSpacing.sm),
                _PhotoGrid(
                  existingUrls: _existingPhotoUrls,
                  newFiles: _newPhotos,
                  onPick: _pickPhoto,
                  onRemove: _removePhoto,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Social media
                Text('Social Media', style: AppTextStyles.heading3),
                const SizedBox(height: 6),
                Text('Enter your username without @', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.sm),
                _SocialField(controller: _instagramCtrl, label: 'Instagram', hint: 'yourhandle'),
                const SizedBox(height: AppSpacing.sm),
                _SocialField(controller: _tiktokCtrl, label: 'TikTok', hint: 'yourhandle'),
                const SizedBox(height: AppSpacing.sm),
                _SocialField(controller: _facebookCtrl, label: 'Facebook', hint: 'yourpage'),
                const SizedBox(height: AppSpacing.sm),
                _SocialField(controller: _twitterCtrl, label: 'Twitter / X', hint: 'yourhandle'),
                const SizedBox(height: AppSpacing.sm),
                _SocialField(controller: _youtubeCtrl, label: 'YouTube', hint: 'yourchannel'),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _websiteCtrl,
                  label: 'Website',
                  hint: 'https://yoursite.com',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Business address (fixed businesses only)
                if (_businessType == 'fixed') ...[
                  Text('Business Address', style: AppTextStyles.heading3),
                  const SizedBox(height: 4),
                  const Text('Your permanent location shown to customers on the map.', style: AppTextStyles.caption),
                  const SizedBox(height: AppSpacing.sm),
                  PlacesAutocompleteField(
                    controller: _addressCtrl,
                    label: 'Business address',
                    onCoordinatesSelected: (lat, lng) => setState(() { _staticLat = lat; _staticLng = lng; }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Cancellation policy
                Text('Cancellation Policy', style: AppTextStyles.heading3),
                const SizedBox(height: 4),
                Text('Blocks online cancellation inside this window. Informational only — no automatic charge.', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.sm),
                _CancellationPolicyDropdown(
                  value: _cancellationPolicyHours,
                  onChanged: (val) => setState(() => _cancellationPolicyHours = val),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Order Ahead toggle
                Text('Order Ahead', style: AppTextStyles.heading3),
                const SizedBox(height: 4),
                Text('Let customers order and pay directly. Requires an active subscription and a connected Stripe account.', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  value: _ordersEnabled,
                  onChanged: _toggleOrdersEnabled,
                  title: const Text('Accept orders'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: AppSpacing.xl),

                AppButton(
                  label: 'Save Changes',
                  onPressed: _loading ? null : _save,
                  isLoading: _loading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({
    required this.existingUrl,
    required this.newFile,
    required this.onTap,
  });

  final String? existingUrl;
  final File? newFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    Widget child;
    if (newFile != null) {
      child = ClipOval(child: Image.file(newFile!, fit: BoxFit.cover, width: 88, height: 88));
    } else if (existingUrl != null) {
      child = ClipOval(child: Image.network(existingUrl!, fit: BoxFit.cover, width: 88, height: 88,
          errorBuilder: (_, _, _) => const Icon(Icons.storefront_outlined, size: 40, color: Colors.white54)));
    } else {
      child = const Icon(Icons.storefront_outlined, size: 40, color: Colors.white54);
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.15),
              border: Border.all(color: primary.withValues(alpha: 0.4), width: 2),
            ),
            child: Center(child: child),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.existingUrls,
    required this.newFiles,
    required this.onPick,
    required this.onRemove,
  });

  final List<String> existingUrls;
  final List<File?> newFiles;
  final void Function(int) onPick;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // 10 fixed slots in a 5-column grid (2 rows)
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      children: List.generate(10, (i) {
        final newFile = newFiles[i];
        final existingUrl = i < existingUrls.length ? existingUrls[i] : null;
        final hasContent = newFile != null || existingUrl != null;

        return GestureDetector(
          onTap: () => onPick(i),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: primary.withValues(alpha: 0.08),
              border: Border.all(
                color: hasContent ? primary.withValues(alpha: 0.4) : AppColors.divider,
              ),
            ),
            child: hasContent
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: newFile != null
                            ? Image.file(newFile, fit: BoxFit.cover)
                            : Image.network(existingUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => onRemove(i),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Icon(Icons.add_photo_alternate_outlined, color: primary, size: 22),
                  ),
          ),
        );
      }),
    );
  }
}

class _CuisineDropdown extends StatelessWidget {
  const _CuisineDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(value) ? value : options.last;
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      decoration: InputDecoration(
        labelText: 'Cuisine Type',
        labelStyle: AppTextStyles.bodySmall,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _CancellationPolicyDropdown extends StatelessWidget {
  const _CancellationPolicyDropdown({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static const _options = <int?>[null, 24, 48, 72, 168, 336];

  static String _label(int? hours) {
    if (hours == null) return 'No cancellation policy';
    if (hours < 24) return '$hours hours';
    final days = hours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
      items: _options.map((h) => DropdownMenuItem(value: h, child: Text(_label(h)))).toList(),
      onChanged: onChanged,
    );
  }
}

class _SocialField extends StatelessWidget {
  const _SocialField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: '@',
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
    );
  }
}
