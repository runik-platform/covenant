# Covenant contracts

Covenant renders one IAM book and the contracts published by its selected
application books. One instance owns one organization and realm. Its base
Argo CD Application owns every realm-global resource and one ApplicationSet.
The ApplicationSet emits a bounded set of child Applications that partition
only principal reconciliation. A second realm is an independent instance.

Principal Applications group users by the first character of their generated
email: `principals-a` through `principals-z`, with `principals-0-9` for numeric
initials. Only occupied groups are generated. Users within each group are
ordered by email; adding, removing, or reordering other users never changes a
principal's group. Filenames and display profiles do not affect grouping.
Changing an email's initial moves that principal to its new group.

Covenant compiles and materializes these groups once, then gives each
child only its final manifests. Children invoke the same Covenant chart but do
not resolve the book or Lexicon, run the compiler, or invoke glyphs again. They
own only users, initial-password resources, and their narrow Vault access.
Groups, authorization, clients, scopes, roles, IDPs, and authentication flows
remain in the base Application.

The deployment spell supplies `applicationSet.source` so child Applications
can invoke the same chart. This is Argo CD wiring, not IAM data, and must not
be placed in the IAM book. The base Application remains the deployment
approval boundary; once its generated child definitions are accepted, the
children reconcile their shards automatically.

## IAM book

The chart selects `bookrack/<name>/index.yaml`. `name` is an optional chart
context override and defaults to the Helm release name; `namespace` likewise
defaults to the Helm release namespace. Librarian supplies those release
coordinates, so a Covenant spell does not repeat either value.

An IAM book is one organization and exactly one realm. Its `index.yaml` is:

```yaml
organization:
  name: tyl
realm:
  name: tyl
  domain: the.yaml.life
  displayName: The YAML Life
sources:
  applicationBooks:
    - name: the-yaml-life
principalDefaults:
  initialPassword:
    enabled: true
    temporary: true
```

Public definitions have no `schemaVersion`. The chart version and pinned Git
revision version the contract. `realm.scope` defaults to `cluster`; principals
default to active with verified email; generated credentials default to
`simple-password-policy`. `credentialDefaults.passwordPolicy` overrides that
policy once for the realm when needed.

Infrastructure selection does not live in the IAM book or application
contracts. Covenant resolves exactly one Lexicon entry labelled
`default: book` for `keycloak`, and resolves `secret-store` or `cert-issuer`
the same way only when the realm needs them. Missing or ambiguous defaults fail
the render.

Realm provider settings use the current Keycloak operator shape. Token and
session settings are separate, and theme keys match the CRD exactly:

```yaml
realm:
  tokenSettings:
    accessTokenLifespan: 900
    revokeRefreshToken: false
  sessions:
    ssoSessionSettings:
      idleTimeout: 1800
      maxLifespan: 36000
    ssoOfflineSessionSettings:
      idleTimeout: 2592000
  themes:
    loginTheme: keycloak
    accountTheme: keycloak.v2
    adminConsoleTheme: keycloak.v2
    emailTheme: keycloak
```

There are no v1 path fallbacks. The compiler reads only these domains:

```text
identity/principals/*.yaml
identity/groups/*.yaml
authorization/roles/*.yaml
authorization/bindings/*.yaml
keycloak/realm-roles/*.yaml
keycloak/client-scopes/*.yaml
keycloak/idps/*.yaml
keycloak/auth-flows/*.yaml
```

Every file contains exactly one definition. The filename is provenance only;
it never supplies an identity, key, or default. Principals derive their
reference from identity fields. Every other named definition carries an
explicit lowercase kebab-case `key`.

### Principals

A principal document contains one identity. `memberOf` is identity membership,
not an authorization grant:

```yaml
principal:
  name: kim
  lastName: pyne
  profile:
    displayName: Kim Pyne
  memberOf:
    - radio-pirata-mods
  initialPassword:
    enabled: true
    temporary: true
```

`name` and optional `lastName` are lowercase login segments joined with `.`.
With the realm domain above, the example deterministically becomes:

```text
principalRef = kim-pyne
username     = kim.pyne@the.yaml.life
email        = kim.pyne@the.yaml.life
resourceName = kim-pyne
```

Only `[a-z0-9]+` is valid in each identity segment. Covenant fails instead of
transliterating or silently changing identity. `profile` may override display
metadata sent to the provider but never changes the four values above.

Principals cannot contain roles or grants. Individual access is expressed by a
binding whose subject is the derived `principalRef`.

### Identity and provider resources

Groups are pure sets of principals. They never contain roles or grants:

```yaml
group:
  key: radio-pirata-mods
  name: radio-pirata/mods
```

Provider resources are explicitly separated under `keycloak/`. For example,
this declares a Keycloak resource that an authorization role may grant:

```yaml
realmRole:
  key: radio-moderator
  description: Radio moderator
```

Kubernetes resource names default to `key`. A definition may set `name` when
the provider-facing name must intentionally differ and `resourceName` when its
Kubernetes name must differ.

### Authorization

Authorization follows the NIST/Kubernetes RBAC shape:

```text
principal/group -> binding -> role -> grants
```

- A principal is one identity.
- A group is only a reusable set of principals.
- A role is only a reusable set of grants.
- A binding assigns exactly one role to one or more principal/group subjects.

For example, one role file contains:

```yaml
role:
  key: platform-engineer
  grants:
    realmRoles:
      - tyl-platform-engineer
    applicationRoles:
      - application: argocd
        role: admin
```

And one binding file contains:

```yaml
binding:
  key: platform-team-access
  subjects:
    groups:
      - tyl-platform
  roleRef: platform-engineer
```

Direct principal exceptions use the same structure and can record why the
exception exists:

```yaml
binding:
  key: kim-on-call
  subjects:
    principals:
      - kim-pyne
  roleRef: incident-reader
  reason: On-call read access
```

There is no separate policy, entitlement, or package layer. Those concepts are
all represented by a role containing grants. An application role in a grant
must point to an explicit target published by the application contract;
Covenant never chooses between a realm role, client role, group, or claim.
Bindings remain the only assignment mechanism regardless of target type. A
binding to a principal may therefore resolve to realm roles, groups, or client
roles; a binding to a group resolves the same grants onto the Keycloak group.

### Combined compatibility claims

Covenant does not require a claim named `groups` to contain only identity
memberships. A realm may deliberately configure multiple protocol mappers to
write group paths and realm roles into that same claim when existing consumers
authorize from one flat list of authorities.

This is a compatibility projection, not a change to the IAM model: groups and
roles remain separate definitions and bindings remain their assignment
mechanism. Consumers of a combined claim must treat every value as an
authority, not assume that every value is an organizational group. Realm roles
may also be exposed separately in `realm_roles`, so duplication between claims
is expected.

Separating memberships into `groups`, realm-wide roles into `realm_roles`, and
application roles into `resource_access.<client>.roles` is a coordinated
consumer migration. It must not be enabled globally while applications still
depend on the combined claim.

## Application contract

An application spell may publish one small top-level contract. Covenant knows
this contract, not the chart values, workload, API, or provisioning process.

```yaml
name: account
namespace: huly

covenant:
  key: huly
  roles:
    user:
      realmRole: user
  clients:
    tyl:
      webUrl: https://huly.int.example.com
      redirectUris:
        - https://huly.int.example.com/_accounts/auth/openid/callback
```

The expanded defaults for that contract are:

- `key` defaults to the spell `name`; Huly overrides it because its spell is
  named `account`.
- The client map key is the realm name; a nested `realmRef` is invalid.
- `type` defaults to `oidc`, `clientId` to the application key,
  `webOrigins` to the single `webUrl`, `public` to `false`, direct access to
  `false`, and standard flow to `true`.
- Client scopes start with every realm scope marked `default: true`.
  `scopes.include` and `scopes.exclude` express only exceptions.
- A confidential client uses the book-default secret store and realm password
  policy. Covenant generates its client secret and publishes a standard
  `keycloak-client-<application>` Secret to the spell namespace for the
  application ServiceAccount.
- `credentials.publish: false`, or explicit `credentials.sinks`, is needed only
  when the standard credential publication is not correct.

The role catalog is shared. Each realm has a separate client entry. A second
organization uses another IAM book and selects its own client entry; principals
and bindings are never shared across realms.

Supported client types are `oidc`, `saml`, and `serviceAccount`. A SAML client
may declare a signing certificate, while Covenant obtains the issuer from
Lexicon. The certificate and its Secret are created in the application
namespace; `certificate.secretName` may override the deterministic default.
The Keycloak operator does not support Secret references in SAML client
attributes, so the application consumes this Secret and any public certificate
that Keycloak must trust has to be configured through a separately supported
integration. Covenant annotates the client with the namespaced Secret reference
for traceability but does not pretend that the operator imports it. IDPs, auth
flows, scopes, and protocol mappers are realm-owned documents, not application
behavior.

An IDP may materialize a provider-issued secret from Vault without embedding
it in Git:

```yaml
identityProvider:
  key: github
  providerId: github
  config:
    clientId: example
  credentials:
    secretName: github-idp
    secretKey: client_secret   # optional default
    configKey: clientSecret    # optional default
```

Covenant reads the existing value from the deterministic Vault path
`/covenant/<realm>/idps/<idp>`, creates a narrowly scoped provider-access
intent, materializes the Kubernetes Secret, and injects its reference into the
IDP config. It never generates an external provider credential.

Application provisioning is out of scope. A chart or a dedicated integration
chart may consume Covenant outputs and own its Jobs, scripts, RBAC, and API
calls.
