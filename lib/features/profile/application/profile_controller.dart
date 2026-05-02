import 'package:flutter/foundation.dart';

import 'profile_service.dart';

export '../../../core/storage/profile/profile_storage.dart' show LocalProfile;

final class ProfileController extends ChangeNotifier {
  ProfileController({
    required this.profileService,
    required this.syncAfterProfileChanged,
  });

  final ProfileService profileService;
  final Future<void> Function() syncAfterProfileChanged;

  LocalProfile? get localProfile => profileService.localProfile;

  Future<void> hydrateLocalProfile() async {
    await profileService.hydrateLocalProfile();
    notifyListeners();
  }

  Future<void> setLocalProfile(LocalProfile profile) async {
    await profileService.setLocalProfile(profile);
    await syncAfterProfileChanged();
    notifyListeners();
  }

  String userNamespaceForMerchantMemory() {
    return profileService.userNamespaceForMerchantMemory();
  }
}
