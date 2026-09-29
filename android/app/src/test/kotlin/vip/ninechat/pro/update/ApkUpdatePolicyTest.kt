package vip.ninechat.pro.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ApkUpdatePolicyTest {
    private fun check(
        packageName: String = "chat.chat99.chatpro", build: Long = 21,
        expectedBuild: Long = 21, version: String = "3.0.2",
        expectedVersion: String = "3.0.2", installed: Set<String> = setOf("trusted"),
        signers: Set<String> = setOf("trusted"), history: Set<String> = signers,
    ) = ApkUpdatePolicy.rejection(
        "chat.chat99.chatpro", packageName, 20, build, expectedBuild,
        expectedVersion, version, installed, signers, history,
    )

    @Test fun acceptsMatchingRelease() { assertNull(check()) }
    @Test fun rejectsOtherApplication() { assertEquals("wrong_package", check(packageName = "other.app")) }
    @Test fun rejectsStaleCdnBuild() { assertEquals("wrong_build", check(build = 22)) }
    @Test fun rejectsWrongVersion() { assertEquals("wrong_version", check(version = "3.0.1")) }
    @Test fun permitsMetadataBuildSuffix() { assertNull(check(expectedVersion = "3.0.2+21")) }
    @Test fun permitsMissingBackendBuildButNotDowngrade() {
        assertNull(check(expectedBuild = 0))
        assertEquals("already_installed", check(build = 19, expectedBuild = 0))
    }
    @Test fun rejectsUnsignedArchive() { assertEquals("missing_signature", check(signers = emptySet())) }
    @Test fun rejectsUntrustedSigner() { assertEquals("wrong_signature", check(signers = setOf("unknown"))) }
    @Test fun permitsVerifiedCertificateRotation() {
        assertNull(check(signers = setOf("new"), history = setOf("trusted", "new")))
    }
    @Test fun rejectsOldCertificateAfterRotation() {
        assertEquals("wrong_signature", check(installed = setOf("new")))
    }
    @Test fun multipleSignersMustMatchExactly() {
        assertNull(check(installed = setOf("a", "b"), signers = setOf("b", "a")))
        assertEquals("wrong_signature", check(installed = setOf("a", "b"), signers = setOf("a")))
    }
    @Test fun installedReleaseIsCleanedUp() {
        assertEquals("already_installed", check(build = 20, expectedBuild = 20))
    }
}
