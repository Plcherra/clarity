import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../auth/application/auth_service.dart';
import 'profile_service.dart';

export '../../../core/storage/profile/profile_storage.dart' show LocalProfile;

final class ProfileController extends ChangeNotifier {
  ProfileController({
    required this.profileService,
    required this.authService,
    required this.syncAfterProfileChanged,
  }) {
    _subscription = authService.authStateChanges.listen((state) async {
      await hydrateProfileForCurrentUser();
    });
  }

  final ProfileService profileService;
  final AuthService authService;
  final Future<void> Function() syncAfterProfileChanged;
  StreamSubscription<dynamic>? _subscription;

  LocalProfile? get localProfile => profileService.localProfile;
  bool isLoading = false;
  String? errorMessage;

  bool get hasCompleteProfile {
    return localProfile?.displayName.trim().isNotEmpty ?? false;
  }

  Future<void> hydrateLocalProfile() async {
    await hydrateProfileForCurrentUser();
  }

  Future<void> hydrateProfileForCurrentUser() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final user = authService.currentUser;
      if (user == null) {
        profileService.localProfile = null;
      } else {
        await profileService.hydrateProfileForUser(user);
      }
    } catch (e) {
      errorMessage = e.toString();
      profileService.localProfile = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setLocalProfile(LocalProfile profile) async {
    final user = authService.currentUser;
    if (user == null) {
      await profileService.setLocalProfile(profile);
    } else {
      await profileService.upsertProfileForUser(user: user, profile: profile);
    }
    await syncAfterProfileChanged();
    notifyListeners();
  }

  String userNamespaceForMerchantMemory() {
    return profileService.userNamespaceForMerchantMemory();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
