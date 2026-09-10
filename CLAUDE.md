# CLAUDE.md — Covenant

This file contains Covenant implementation rules. The public book and
application contract is defined only in [docs/contracts.md](docs/contracts.md).
Shared Runik concepts live in the parent repository.

## Scope

Covenant compiles one IAM book and the contracts published by its selected
application books. It owns realm identity, RBAC, Keycloak resources, generated
credentials, certificates, and provider access needed to materialize them.

It must not read application chart values or own application workloads, APIs,
Jobs, scripts, configuration, or provisioning procedures.

## Runtime

One base release is one book, organization, realm, and Covenant instance. The
base Argo CD Application owns the realm, roles, scopes, groups, clients, IDPs,
authentication flows, application credentials, reports, and one
ApplicationSet. The ApplicationSet creates a bounded set of principal
Applications. Each child is an internal reconciliation shard, never an
additional organization, application contract, or realm. A second realm is an
independent Covenant instance with its own state and lifecycle.

Covenant compiles and materializes the complete model once in the base render.
It passes each child only that shard's final manifests. Children invoke the
same Covenant chart through a private materialized-manifest path; they never
resolve references, run glyphs, or compile the model again. The manifest
payload is reconciliation plumbing, not a public mode or IAM-book option. The
base Application remains the deployment approval boundary; accepted child
definitions reconcile automatically.

## Contract invariants

- Read only the paths and fields documented in `docs/contracts.md`; do not
  add v1 fallbacks, migration readers, public `schemaVersion`, or filename
  defaults.
- Use optional chart-context overrides `name` and `namespace`, falling back to
  `.Release.Name` and `.Release.Namespace`; do not require duplicate values in
  a Librarian spell.
- Keep ApplicationSet source coordinates in the deployment spell;
  they are runtime wiring and never part of the IAM book.
- Derive principal identity only from required `name` and optional `lastName`.
  `profile` is optional display metadata.
- Use lowercase kebab-case for logical references and Kubernetes names. Dots
  are reserved for generated login and email values.
- Principals own identity and `memberOf`; groups own identity membership; roles
  own grants; bindings are the only assignment mechanism.
- Keep reusable RBAC under `authorization/` and provider resources under
  `keycloak/`.
- Preserve explicit physical `resourceName` and provider-facing `name`
  overrides where the public contract allows them.

## Provider resolution

Resolve exactly one book-default Keycloak entry from the consolidated Lexicon.
Resolve a book-default secret store or certificate issuer only when required.
Missing and ambiguous providers are errors. Public IAM and application data
cannot select providers and must never be published through Appendix/Lexicon.

Pass atomic glyphs only the resolved provider entries for this realm so their
existing `runicIndexer` contracts remain intact.

## Compiler and glyphs

The compiler discovers and validates definitions, resolves references into a
canonical graph, and emits ordered typed intents. Every intent type has one
fixed adapter in `templates/covenant.yaml`; the adapter invokes a meta-glyph in
`templates/_metaglyphs.tpl` composed from existing atomic glyphs.

Meta-glyphs may render typed intents. They may not scan files, resolve
references, infer access, select a CRD, or inspect application configuration.

`charts/` is a tracked glyphs submodule, not a Helm dependency. Keep
`Chart.yaml` free of dependencies and do not add `Chart.lock` or dependency
build steps. Edit reusable glyph behavior only in Runik's canonical
`charts/glyphs` checkout, then update this submodule pointer.

## Determinism and validation

- Fail on missing or duplicate identities and references.
- Preserve explicit `false` through every layer.
- Keep adapter selection, sync waves, and render order fixed.
- Group principals by generated email initial (`a`–`z`, numeric `0-9`) and
  order them by email; never partition by list position or rebalance by size.
- Never place secret material in compiler intents.
- Validate through the parent repository's `make test covenant`; it renders the
  complete fixture, parses it, and verifies resource invariants without a
  cluster. Do not use `helm lint` to validate intentionally vendored template
  libraries.
