# HardenTool specification review and delivery plan

Reviewed: 2026-07-17

## Recommendation

Proceed, but position HardenTool initially as a **signed offline evidence-and-enforcement bundle for Windows industrial PCs**, not as a general configuration-management platform. The compelling product is the safe workflow around policy selection, air-gapped packaging, preservation rules, execution evidence, and controlled change. DSC is an implementation component, not the product.

The first release should prove one narrow, valuable loop:

> Inspect a known Windows device family, preview a small approved hardening profile, apply it from signed removable media, verify it, and bring back credible evidence—without touching unrecognised supplier software.

Do not build a resident agent, a generic multi-backend compiler, remote orchestration, or a new package repository until that loop has been exercised against representative brown-field devices.

## What is strong in the draft

- The two-level model correctly keeps business intent separate from backend mechanics.
- Offline, signed, self-contained media is a suitable operating model for air-gapped devices.
- Preservation by default directly addresses the central brown-field/OT safety problem.
- Assess, plan, apply, and verify are correctly distinct phases.
- First-class evidence, driver capture, and immutable artifact provenance make the tool operationally credible rather than merely a hardening script.
- Treating reboots, disruption, and exceptions as policy concerns is essential.

## Principal weaknesses and required changes

| Area | Weakness / risk | Decision or change needed |
| --- | --- | --- |
| “Latest approved” | “Latest” is non-reproducible and ambiguous once media is built; it could silently change the intended state. | Resolve channels in the build environment to an exact version, artifact digest, and configuration digest. The target only receives immutable resolved policy. |
| Abstract policy language | A broad universal schema quickly leaks backend details or becomes a weak lowest-common-denominator model. | Start with a small Windows capability catalogue. Define explicit `capability`, `supported`, and `fidelity` metadata for every backend mapping; allow controlled backend extensions rather than pretending all features translate identically. |
| “Compiler” | Calling the whole transformation a compiler implies hard semantic guarantees that are difficult for application installers and vendor configuration. | Split it into: policy validation, resolution, plan construction, and DSC document rendering. Preserve a trace from every planned action to source policy. |
| Device identity and assignment | Hardware identifiers can be absent, duplicated after imaging, or altered by replacement; free-form classification can select the wrong policy. | Use an enrolled asset identity as the primary key where available; require at least two corroborating signals for automatic matching; allow only signed, explicit offline assignments. Fail closed to assessment. |
| Change safety | A preview alone does not make an OT action safe. No policy currently models maintenance windows, safety impact, or application dependencies. | Add change classes (`read-only`, `reversible`, `reboot`, `service-impacting`, `irreversible`), maintenance-window/approval requirements, and an explicit “not supported unattended” flag. |
| Supplier protection | “Supplier/OEM protected” needs a source of truth; discovery alone cannot reliably recognise supplier applications. | Maintain signed per-device-family manifests and protected package identifiers. Unknown remains preserved; a protected classification must be stronger than a removal request. |
| Rollback | The draft says rollback guidance but does not state what is actually reversible. Windows configuration, uninstallers, and firmware are not uniformly reversible. | Define rollback as a per-action capability: `automatic`, `manual-runbook`, or `none`. Block `none` actions in the first release unless an explicit break-glass approval is recorded. |
| Offline secrets | “Encrypted offline secret packages” is necessary but underspecified and dangerous on removable media. | Exclude secrets from v1 if possible. If unavoidable, encrypt to a target/device certificate, restrict validity/scope, require a hardware- or OS-protected private key, and never provide reusable decryption keys on the same media. |
| Tool self-update | Updating the executor on the target increases bootstrap and recovery complexity before there is a demonstrated need. | Do not self-update during a v1 run. Select the signed runtime when building media. Add separate, staged runtime upgrade later. |
| Agent | A continuous agent creates long-term privileged code, scheduling, policy-import, and tamper-resistance problems. | Defer it. Begin with repeated one-shot media runs; later use a minimal scheduled evaluator only after an explicit agent threat model and lifecycle design. |
| DSC v3 dependency | DSC v3 is appropriate to evaluate, but resource coverage and legacy device compatibility must be proven; it does not replace application lifecycle logic. | Build an adapter spike with only registry, services, local policy, package detection, and verification. Keep application installation behind a HardenTool resource contract. |
| OEM driver recovery | Exporting the driver store does not capture OEM management suites, firmware, license material, or every recovery dependency. | Call this “third-party driver-store capture”, document its boundary, and make it read-only. Treat a full recovery image as a separate vendor/OEM process. |
| Evidence integrity | Reports written back to USB can be deleted/replaced after collection. | Sign each completed run with a device-specific signing key where feasible, or at minimum use an append-only hash chain and verify it during central import. A USB report alone is not immutable evidence. |

## Where not to reinvent the wheel

| Need | Reuse / integrate | HardenTool’s responsibility |
| --- | --- | --- |
| Source control and review | Git plus protected branches and normal review tooling | Policy repository conventions, validation, and release promotion—not a new VCS. |
| Artifact storage | JFrog Artifactory or an existing approved repository | Resolve, lock, export, and verify an offline bill of materials—not a package repository. |
| Windows desired-state execution | DSC v3, with narrowly vetted resources; Windows native tools where DSC has no safe resource | Render/configure, call it, normalise results, and own safety gates/evidence. |
| Windows application install mechanics | Vendor silent installers/MSI/EXE switches; vetted package adapters | Detection, declared health checks, exit-code normalisation, and provenance. Avoid depending on live WinGet feeds for air-gapped deployment. |
| Driver export | Windows PnPUtil `/export-driver` | Wrap it safely, enrich inventory, hash output, and report the limitation. |
| SBOM | CycloneDX or SPDX; choose one organisation-wide format | Produce and bundle the BOM for each media release; do not invent a BOM schema. |
| Signed software/update metadata | TUF-style role-separated, versioned metadata where the update workflow needs it; Authenticode/code signing for Windows binaries | Define offline media trust policy, key ownership, and verification UX. Do not create custom cryptographic formats. |
| Security baselines | Microsoft Security Compliance Toolkit and the organisation’s approved CIS/vendor baselines | Curate, test, parameterise, and assign a safe subset per device family; do not claim a generic baseline is universally OT-safe. |
| Compliance interchange | JSON/SARIF where useful and a normal data-ingestion pipeline | Define HardenTool’s evidence envelope and mapping; do not build a bespoke SIEM/compliance data platform. |

## Target v1 boundary

### In scope

- Windows 10/11 IoT Enterprise x64 only, subject to a tested build matrix.
- One or two named industrial PC/device families and one approved baseline each.
- Offline assess, explicit assignment, plan, operator-approved apply, verify, and signed evidence export.
- A small resource set: registry/settings, Windows services, optional features, local groups, firewall rules, and positively identified approved-removal items.
- Bundled, exact-version installer execution with detection and local health checks.
- Third-party driver-store capture.

### Explicitly out of scope

- Linux/macOS, Ansible, remote push, fleet orchestration, and central live inventory.
- A persistent agent or autonomous remediation.
- General-purpose debloating, supplier software discovery/removal, firmware management, and full-device recovery.
- Runtime self-update on target.
- Storing general secrets on removable media.

## Delivery plan and decision gates

### 0. Discovery and safety contract — 2–3 weeks

1. Obtain two representative brown-field devices (or faithful test images), supplier documentation, and the exact Windows build/support constraints.
2. Run read-only inventory and driver-store capture manually; catalogue applications, services, drivers, and operational dependencies.
3. Agree the first device-family manifest: allowed changes, protected identifiers, health checks, maintenance constraints, and escalation contacts.
4. Facilitate a threat-model workshop covering removable media loss/tampering, malicious bundle, wrong-device deployment, privilege escalation, recovery, and evidence tampering.
5. Define signer roles, offline key storage, bundle approval, and policy exception authority.

**Gate:** Operations/supplier owner signs off a v1 safe-change catalogue and test-device access. Stop if this cannot be obtained; the tool cannot safely infer it.

### 1. Architecture spike — 2 weeks

1. Build a throwaway proof that packages a fixed DSC v3 runtime/resources and a simple signed manifest for a disconnected Windows test machine.
2. Prove inventory, `test`, `set`, and structured result collection for five resource types.
3. Prove package detection/installation/verification for one approved MSI and one vendor EXE.
4. Prove PnPUtil driver-store export and validate the output on a clean test host without using it to change production equipment.
5. Measure run time, required privileges, reboots, log volume, and failure modes.

**Gate:** Continue only if DSC/resource behaviour is stable on the supported build matrix and every mutation can be previewed, attributed, and evidenced. Otherwise retain the policy model but choose a different Windows executor.

### 2. V1 foundations — 3–4 weeks

1. Define versioned schemas for intent policy, resolved policy, device-family manifest, assignment, plan, action result, and evidence envelope.
2. Implement deterministic policy resolution: no target-side channels, dependencies, or artifact lookups.
3. Implement a signed bundle format with an inventory file, artifact digests, trusted-key configuration, and an atomic output/run directory.
4. Implement read-only assess mode and strict target-match rules before elevation.
5. Implement plan/apply/verify flow, explicit operator acknowledgement, reboot boundary handling, and per-action rollback classification.

**Gate:** An independent reviewer can reproduce a bundle from a tagged policy release and verify why every file/action is included.

### 3. Safe hardening profile — 3–4 weeks

1. Implement the agreed narrow resource catalogue and idempotence tests.
2. Add protected/unknown/approved-removable classification with positive detection identities.
3. Add the first device-family baseline, vendor health checks, and evidence summaries for operators and importers.
4. Test first on clean OEM builds, then controlled brown-field replicas, then supervised pilot devices during a maintenance window.
5. Perform failure-injection tests: corrupt bundle, invalid signature, insufficient privileges, wrong target, interruption/reboot, failed installer, and a failing health check.

**Gate:** The second application run is a no-op; failure states are correctly reported; no protected/unknown component changes in the pilot evidence.

### 4. Pilot and operationalisation — 4–6 weeks

1. Pilot against a small, supervised device cohort with a signed change record per execution.
2. Establish media custody, import validation, evidence retention, exception review, and vendor escalation procedures.
3. Feed actual inventory differences back into protected manifests and policy tests.
4. Publish an operator runbook and a support/recovery runbook.

**Gate:** Pilot acceptance from OT operations, security, and the relevant supplier owner. Only then prioritise agent or central ingestion work.

### 5. Deferred capability decisions

- **Agent:** start with report-only drift assessment; choose whether remediation is ever acceptable by device class.
- **Central ingestion:** import signed evidence and inventory first; do not start with a management server.
- **Ansible:** add only when a real target class/workflow cannot be adequately handled by DSC and the policy capability mapping is demonstrably stable.
- **Self-update:** introduce through separate signed maintenance media after runtime compatibility and rollback rules exist.

## Initial schema changes to make now

Add these fields to the level-1 policy or resolved-policy form:

```yaml
spec:
  release:
    policyDigest: sha256:...
    resolvedAt: 2026-07-17T12:00:00Z
  changeControl:
    maximumClass: reboot
    unattended: false
    maintenanceWindowRequired: true
  application:
    artifact:
      version: 8.0.401
      digest: sha256:...
    verification:
      - type: file-version
        path: C:\\Program Files\\Example\\example.exe
        equals: 8.0.401
  actionSafety:
    rollback: manual-runbook
  backendRequirements:
    - capability: windows.service
      minimumFidelity: exact
```

The compiled form should contain only resolved versions/digests and explicit actions; it must never make a choice such as “latest” at execution time.

## Measures of success

- No unapproved package/service/driver modifications across pilot runs.
- 100% of executed actions traceable to a signed policy statement and an exact artifact digest.
- 100% of failed or interrupted runs identifiable as incomplete/non-compliant.
- Repeated application produces no state changes when compliant.
- Operators can determine what happened from exported evidence without accessing the target device.

## Tooling assessment

The proposed toolset is appropriate, but it is a **composed architecture**, not an off-the-shelf product category. Mature industrial practice normally combines an asset/change-management process, vendor-approved baselines, a configuration executor, signed software supply-chain controls, and a test environment. HardenTool's differentiated value is the offline, conservative glue between those components.

| Area | Recommendation | Rationale |
| --- | --- | --- |
| Policy source | Git repository with protected releases | Correct choice. Keep policy review, approvals, and history in normal engineering tooling. |
| Artifact repository | JFrog Artifactory if already available and operationally supported | Correct choice. Use it as the approved connected source; export immutable artifacts to media. Do not need a target-side repository. |
| Windows executor | Evaluate DSC v3 first, pin its exact runtime/resource versions, and retain a replacement boundary | A good fit for declarative test/set operations. Its resource compatibility on target Windows builds must be proven before it becomes the default. |
| Baselines | Microsoft Security Compliance Toolkit plus supplier-approved and risk-assessed deltas | Reuse the baseline source and tailor it per industrial device family. Do not apply CIS/Microsoft baselines wholesale to OT. |
| Package installation | Vendor installers with a HardenTool package adapter and verified local health checks | More predictable offline than live package-manager feeds. Package managers can still be used in the build environment to acquire approved artifacts. |
| Driver capture | PnPUtil driver-store export | Correct supported Windows primitive. It is evidence/backup, not a complete OEM recovery mechanism. |
| Bundle signing | Enterprise code-signing/PKI plus standard manifest and role-separated update metadata | Use existing certificate governance. Start with signed immutable bundles; introduce a full TUF-style update workflow only when update roles and key rotation justify it. |
| SBOM | CycloneDX (or SPDX if already mandated elsewhere) | Use one standard format consistently. CycloneDX is a practical choice for bundle and dependency evidence. |
| Reporting | JSON evidence envelope with HTML rendering; central import later | Correctly keeps field operation offline while avoiding a custom monitoring platform in v1. |

### Proxmox validation lab

Use the supplied Proxmox node as an isolated, disposable compatibility and failure-injection lab. It is valuable for build reproducibility and most Windows configuration tests, but it cannot replace testing on the actual industrial hardware and supplier application stack.

Suggested initial layout:

```text
proxmox
  ├─ build-vm             isolated build/signing and bundle-export environment
  ├─ win11-iot-clean      clean supported Windows image snapshot
  ├─ win11-iot-brownfield representative software/services/supplier-app fixture
  ├─ evidence-import      validates signatures, manifests, and report ingestion
  └─ optional-ad          only if local-policy versus domain-policy interaction is in scope
```

Lab rules:

1. Keep the lab isolated from production OT networks; use controlled media-image transfer rather than a bridge to production.
2. Snapshot every target VM before assessment and before each apply run; label snapshots with policy/bundle digest.
3. Run the same bundle against clean and brown-field fixtures, then run it again to prove idempotence.
4. Test invalid signatures, altered artifacts, wrong-device assignment, interrupted runs, insufficient disk space, installer failure, reboot-required behaviour, and failed health checks.
5. Treat Proxmox results as executor evidence only. Run final compatibility, driver, timing, and supplier-application tests on supervised representative physical devices.
