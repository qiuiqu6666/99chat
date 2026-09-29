package vip.ninechat.pro.update

/** Reject incomplete/wrong releases before offering them to the system installer. */
object ApkUpdatePolicy {
    fun rejection(
        expectedPackage: String, actualPackage: String,
        installedBuild: Long, actualBuild: Long, expectedBuild: Long,
        expectedVersion: String, actualVersion: String,
        installedSigners: Set<String>, archiveSigners: Set<String>, archiveHistory: Set<String>,
    ): String? {
        if (actualPackage != expectedPackage) return "wrong_package"
        if (expectedBuild > 0 && actualBuild != expectedBuild) return "wrong_build"
        if (actualVersion != expectedVersion.substringBefore('+')) return "wrong_version"
        if (installedSigners.isEmpty() || archiveSigners.isEmpty()) return "missing_signature"
        val signedBySameIdentity = if (installedSigners.size == 1 && archiveSigners.size == 1) {
            archiveHistory.containsAll(installedSigners) || archiveSigners == installedSigners
        } else archiveSigners == installedSigners
        if (!signedBySameIdentity) return "wrong_signature"
        if (actualBuild <= installedBuild) return "already_installed"
        return null
    }
}
