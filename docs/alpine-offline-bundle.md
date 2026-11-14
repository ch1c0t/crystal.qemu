# Alpine offline bundle

grml.agent prepare_alpine_bundle [alpine_branch] creates a self-contained
offline APK repository snapshot for Alpine x86_64. It does **not** create a
bootable Alpine root filesystem or disk image. Image creation is a separate
operation.

The default branch is latest-stable. A caller may supply a branch such as
v3.24. Branch names are restricted to letters, digits, dots, underscores,
and hyphens before they are used in guest commands.

## What is fetched

The workflow uses the GRML guest as the build environment. It downloads two
pinned tools:

- alpine-chroot-install v0.14.0, checked against a pinned SHA-256 digest.
- apk.static v2.14.7 for x86_64, checked against a pinned SHA-256 digest.

The Alpine public signing keys embedded in the pinned
alpine-chroot-install script are extracted into the bundle. APK then fetches
the recursive dependency closure of alpine-base and alpine-keys from the
selected branch's main and community repositories.

This captures the dependencies of those two requested packages; it is not a
full mirror of either Alpine repository. The latest-stable branch is a moving
reference, so separate runs can contain different package versions.

## Verification performed

The operation reports fourteen stages:

1. Check that the GRML guest architecture is x86_64.
2. Create a unique run directory and a RUNNING marker.
3. Download alpine-chroot-install v0.14.0 and check its pinned SHA-256.
4. Download apk.static v2.14.7, check its pinned SHA-256, and make it executable.
5. Extract the Alpine public keys and install them into the temporary APK root.
6. Fetch the recursive package dependency closure from main and community.
7. Run apk verify against every downloaded .apk using the extracted Alpine
   public keys. This checks package integrity and signatures before the local
   repository is used.
8. Generate repository/x86_64/APKINDEX.tar.gz with --rewrite-arch x86_64.
   This aligns index architecture metadata with the directory containing the
   package files, including upstream noarch packages.
9. Check that the architecture directory, index, and at least one package
   archive exist; report the package count and repository size.
10. Attempt to install alpine-base and alpine-keys into a disposable root using
    only the local repository and with networking disabled. It also checks
    that both packages appear in the installed package database.
11. Remove the temporary APK roots, write MANIFEST, and generate SHA256SUMS
    for the manifest, repository, tools, and public keys.
12. Check the manifest fields, package count, repository size, exact expected
    payload file list, and every SHA-256 digest.
13. Atomically rename RUNNING to COMPLETE.
14. Atomically replace LATEST with the relative path of this completed run.

A run is not promoted to COMPLETE until the final metadata and checksum audit
succeeds. LATEST is not updated until after that promotion.

## Trust model and limitations

The locally generated APKINDEX.tar.gz is unsigned because this workflow does
not have an Alpine repository-index signing private key. The isolated offline
installation therefore passes --allow-untrusted to accept the locally
generated index. That option also relaxes APK's signature enforcement for the
install command; it is not the package-authenticity check. Before the install
test, every downloaded package archive is independently checked by
apk verify against the Alpine public keys extracted from the pinned installer
script. The offline installation itself uses --no-network.

SHA256SUMS detects accidental or subsequent changes to the files it lists
when checked with sha256sum -c SHA256SUMS. It is not a digital signature:
an attacker able to replace both the files and SHA256SUMS can replace the
entire bundle. The checksum list does not checksum itself, the RUNNING or
COMPLETE marker, or the external LATEST pointer. Preserve a trusted copy of
the checksum list or authenticate the bundle through a separate trusted
channel when protection against malicious modification is required.

The installer script's current pin is SHA-1 for compatibility with the
existing preparation workflow; the static APK tool is pinned with SHA-256.
The package signatures are checked with the embedded Alpine keys, and the
final payload is checksummed with SHA-256.

## Artifact layout

The guest stores runs beneath /mnt/shared/alpine-bundles; the same files are
visible on the host beneath the QEMU VM's shared directory:

    alpine-bundles/
      LATEST                         # contains runs/<run_id>
      runs/
        <run_id>/
          RUNNING or COMPLETE        # contains run_id=<run_id>
          MANIFEST
          SHA256SUMS
          repository/
            x86_64/
              APKINDEX.tar.gz
              *.apk
          tools/
            alpine-chroot-install
            apk.static
          keys/
            *.rsa.pub

The repository URL/path supplied to APK is the repository/ directory, not
repository/x86_64/; APK appends the architecture directory itself.

MANIFEST records the format version, run ID, Alpine branch, architecture,
repository components, requested packages, tool versions, signature-check
results, offline-install result, package count, repository size, and checksum
algorithm. SHA256SUMS covers all regular files beneath MANIFEST,
repository/, tools/, and keys/.

## Failure and retention behavior

Each invocation creates a new run directory; successful prior runs are not
overwritten. If a command fails before final verification, the run directory
is retained with its RUNNING marker for diagnosis, and LATEST remains
unchanged. Temporary roots may remain in an incomplete run.

If all checks pass but publishing LATEST fails, the verified run remains
marked COMPLETE; the previous LATEST value remains in place. A COMPLETE
marker therefore means the payload and checksums were verified, not
necessarily that it became the current LATEST run.

The output is a repository snapshot and verification record, not a signed
repository, a complete Alpine mirror, or a bootable image.

## Progress reporting

The operation reports stage-level progress through the optional callback
used by the GRML REPL or through the logger for the one-shot CLI command.
Guest commands are polled through the QEMU Guest Agent and return their
captured output when they finish; package-manager output is not streamed
line by line while a command is running.
