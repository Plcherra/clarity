import '../../../core/storage/profile/profile_storage.dart';

export '../../../core/storage/profile/profile_storage.dart' show LocalProfile;

class ProfileService {
  LocalProfile? localProfile;

  Future<void> hydrateLocalProfile() async {
    try {
      localProfile = await loadLocalProfile();
    } on Object {
      localProfile = null;
    }
  }

  Future<void> setLocalProfile(LocalProfile profile) async {
    await saveLocalProfile(profile);
    localProfile = profile;
  }

  String userNamespaceForMerchantMemory() {
    final created = localProfile?.createdAtUtcIso.trim();
    if (created != null && created.isNotEmpty) return created;
    return 'anon';
  }
}
