{{/* SPDX-License-Identifier: AGPL-3.0-only */}}

{{- define "covenant.compile" -}}
{{- $root := . -}}
{{- $book := default $root.Release.Name $root.Values.name -}}
{{- $indexPath := printf "bookrack/%s/index.yaml" $book -}}
{{- if not ($root.Files.Glob $indexPath) -}}
  {{- fail (printf "covenant: IAM book index not found: %s" $indexPath) -}}
{{- end -}}
{{- $index := $root.Files.Get $indexPath | fromYaml -}}
{{- if hasKey $index "schemaVersion" -}}{{- fail "covenant: IAM index must not declare schemaVersion; the chart version owns the contract" -}}{{- end -}}
{{- if hasKey $index "providers" -}}{{- fail "covenant: IAM index cannot declare infrastructure providers; publish book defaults through Lexicon" -}}{{- end -}}
{{- $organization := required "covenant: index.organization is required" $index.organization -}}
{{- $organizationName := include "covenant.logical" (required "covenant: organization.name is required" $organization.name) -}}
{{- $realm := deepCopy (required "covenant: index.realm is required" $index.realm) -}}
{{- if hasKey $realm "providerRef" -}}{{- fail "covenant: realm cannot select infrastructure providerRef; Covenant resolves the book-default Keycloak from Lexicon" -}}{{- end -}}
{{- $realmName := include "covenant.logical" (required "covenant: realm.name is required" $realm.name) -}}
{{- if ne $organizationName $realmName -}}
  {{- fail (printf "covenant: one IAM book is one organization and one realm; organization %q and realm %q must match" $organizationName $realmName) -}}
{{- end -}}
{{- $domain := required "covenant: realm.domain is required" $realm.domain -}}
{{- $realmScope := default "cluster" $realm.scope -}}
{{- if not (has $realmScope (list "cluster" "namespace")) -}}{{- fail "covenant: realm.scope must be cluster or namespace" -}}{{- end -}}
{{- $realmProviderRef := "identity" -}}
{{- $_ := set $realm "providerRef" $realmProviderRef -}}
{{- $_ := set $realm "refKind" (ternary "ClusterKeycloakRealm" "KeycloakRealm" (eq $realmScope "cluster")) -}}
{{- $_ := set $realm "realmName" $realmName -}}
{{- $_ := set $realm "resourceName" (include "covenant.physical" (list $realmName (default (printf "realm-%s" $realmName) $realm.resourceName))) -}}

{{- $providers := dict "identity" (include "covenant.provider" (list $root "identity" "keycloak") | fromJson) -}}
{{- $credentialDefaults := default dict $index.credentialDefaults -}}
{{- $credentialPasswordPolicy := default "simple-password-policy" $credentialDefaults.passwordPolicy -}}
{{- with ($index.principalDefaults).initialPassword -}}
  {{- if hasKey . "providerRef" -}}{{- fail "covenant: principal password defaults cannot select infrastructure providerRef" -}}{{- end -}}
{{- end -}}

{{- $base := printf "bookrack/%s" $book -}}
{{- $principalDefaults := deepCopy (default dict $index.principalDefaults) -}}
{{- $initialPasswordDefaults := deepCopy (default dict $principalDefaults.initialPassword) -}}
{{- if not (hasKey $initialPasswordDefaults "passwordPolicy") -}}{{- $_ := set $initialPasswordDefaults "passwordPolicy" $credentialPasswordPolicy -}}{{- end -}}
{{- $_ := set $principalDefaults "initialPassword" $initialPasswordDefaults -}}
{{- $realmRoles := include "covenant.scanNamed" (list $root (printf "%s/keycloak/realm-roles/*.yaml" $base) "realmRole") | fromJson -}}
{{- $groups := include "covenant.scanNamed" (list $root (printf "%s/identity/groups/*.yaml" $base) "group") | fromJson -}}
{{- $principals := include "covenant.scanPrincipals" (list $root (printf "%s/identity/principals/*.yaml" $base) $domain $principalDefaults) | fromJson -}}
{{- $authorizationRoles := include "covenant.scanNamed" (list $root (printf "%s/authorization/roles/*.yaml" $base) "role") | fromJson -}}
{{- $bindings := include "covenant.scanNamed" (list $root (printf "%s/authorization/bindings/*.yaml" $base) "binding") | fromJson -}}
{{- $clientScopes := include "covenant.scanNamed" (list $root (printf "%s/keycloak/client-scopes/*.yaml" $base) "clientScope") | fromJson -}}
{{- $identityProviders := include "covenant.scanNamed" (list $root (printf "%s/keycloak/idps/*.yaml" $base) "identityProvider") | fromJson -}}
{{- $authenticationFlows := include "covenant.scanNamed" (list $root (printf "%s/keycloak/auth-flows/*.yaml" $base) "authenticationFlow") | fromJson -}}
{{- $applications := include "covenant.scanApplications" (list $root (default list ($index.sources).applicationBooks)) | fromJson -}}
{{- $principalShards := list -}}
{{- $principalRefsByEmail := dict -}}
{{- range $principalRef, $principal := $principals -}}
  {{- $_ := set $principalRefsByEmail $principal.email $principalRef -}}
  {{- $principalShards = append $principalShards (include "covenant.principalShard" $principal) | uniq -}}
{{- end -}}
{{- $principalShards = sortAlpha $principalShards -}}
{{- $defaultClientScopes := list -}}
{{- range $scopeRef, $scope := $clientScopes -}}
  {{- $isDefault := false -}}{{- if hasKey $scope "default" -}}{{- $isDefault = $scope.default -}}{{- end -}}
  {{- if $isDefault -}}{{- $defaultClientScopes = append $defaultClientScopes (default $scopeRef $scope.name) -}}{{- end -}}
{{- end -}}

{{/* Validate every published role target, even when no current binding uses it. */}}
{{- $applicationProducerAccess := dict -}}
{{- $applicationSinkAccess := dict -}}
{{- range $applicationKey, $application := $applications -}}
  {{- range $roleKey, $_ := default dict $application.roles -}}
    {{- $_ := include "covenant.applicationRoleGrant" (list $applications $applicationKey $roleKey $realmName) | fromJson -}}
  {{- end -}}
{{- end -}}

{{/* Identity definitions never carry permissions. Principals only declare membership. */}}
{{- range $groupRef, $group := $groups -}}
  {{- range $forbidden := list "memberOf" "realmRoles" "applicationRoles" "roles" "grants" "entitlements" "packages" -}}
    {{- if hasKey $group $forbidden -}}{{- fail (printf "covenant: group %q cannot contain authorization field %s; use a role and binding" $groupRef $forbidden) -}}{{- end -}}
  {{- end -}}
  {{- $_ := set $group "resolvedRealmRoles" (list) -}}
  {{- $_ := set $group "resolvedGroups" (list) -}}
  {{- $_ := set $group "resolvedClientRoles" (dict) -}}
{{- end -}}
{{- range $principalRef, $principal := $principals -}}
  {{- range $forbidden := list "groups" "realmRoles" "applicationRoles" "roles" "grants" "entitlements" "packages" -}}
    {{- if hasKey $principal $forbidden -}}{{- fail (printf "covenant: principal %q cannot contain authorization field %s; use memberOf for identity membership and a role binding for access" $principalRef $forbidden) -}}{{- end -}}
  {{- end -}}
  {{- $memberships := list -}}
  {{- range $groupRef := default list $principal.memberOf -}}{{- $memberships = append $memberships (include "covenant.logical" $groupRef) | uniq -}}{{- end -}}
  {{- $_ := set $principal "resolvedRealmRoles" (list) -}}
  {{- $_ := set $principal "resolvedGroups" $memberships -}}
  {{- $_ := set $principal "resolvedClientRoles" (dict) -}}
{{- end -}}

{{/* Roles are reusable permission sets. Validate every role, even if unused. */}}
{{- $resolvedRoles := dict -}}
{{- range $roleRef, $role := $authorizationRoles -}}
  {{- $grant := include "covenant.resolveRole" (list $role $applications $realmName) | fromJson -}}
  {{- range $realmRoleRef := default list $grant.realmRoles -}}
    {{- if not (hasKey $realmRoles $realmRoleRef) -}}{{- fail (printf "covenant: authorization role %q references unknown Keycloak realm role %q" $roleRef $realmRoleRef) -}}{{- end -}}
  {{- end -}}
  {{- range $groupRef := default list $grant.groups -}}
    {{- if not (hasKey $groups $groupRef) -}}{{- fail (printf "covenant: authorization role %q references unknown group %q" $roleRef $groupRef) -}}{{- end -}}
  {{- end -}}
  {{- $_ := set $resolvedRoles $roleRef $grant -}}
{{- end -}}

{{/* Bindings are the only authorization assignment in the IAM book. */}}
{{- $resolvedBindings := list -}}
{{- range $bindingRef, $binding := $bindings -}}
  {{- range $forbidden := list "realmRoles" "applicationRoles" "roles" "grants" "entitlements" "packages" "subject" -}}
    {{- if hasKey $binding $forbidden -}}{{- fail (printf "covenant: binding %q cannot contain %s; it must reference exactly one roleRef and declare subjects" $bindingRef $forbidden) -}}{{- end -}}
  {{- end -}}
  {{- $roleRef := include "covenant.logical" (required (printf "covenant: binding %q requires roleRef" $bindingRef) $binding.roleRef) -}}
  {{- $grant := required (printf "covenant: binding %q references unknown authorization role %q" $bindingRef $roleRef) (get $resolvedRoles $roleRef) -}}
  {{- $subjects := required (printf "covenant: binding %q requires subjects" $bindingRef) $binding.subjects -}}
  {{- range $subjectKind, $_ := $subjects -}}
    {{- if not (has $subjectKind (list "principals" "groups")) -}}{{- fail (printf "covenant: binding %q has unsupported subject kind %s" $bindingRef $subjectKind) -}}{{- end -}}
  {{- end -}}
  {{- $subjectCount := add (len (default list $subjects.principals)) (len (default list $subjects.groups)) -}}
  {{- if eq (int $subjectCount) 0 -}}{{- fail (printf "covenant: binding %q requires at least one principal or group subject" $bindingRef) -}}{{- end -}}
  {{- $resolvedSubjects := list -}}
  {{- range $principalRef := default list $subjects.principals -}}
    {{- $principalRef = include "covenant.logical" $principalRef -}}
    {{- $principal := required (printf "covenant: binding %q references unknown principal %q" $bindingRef $principalRef) (get $principals $principalRef) -}}
    {{- $_ := include "covenant.applyGrant" (list $principal $grant) -}}
    {{- $resolvedSubjects = append $resolvedSubjects (dict "kind" "principal" "ref" $principalRef) -}}
  {{- end -}}
  {{- range $groupRef := default list $subjects.groups -}}
    {{- $groupRef = include "covenant.logical" $groupRef -}}
    {{- $group := required (printf "covenant: binding %q references unknown group %q" $bindingRef $groupRef) (get $groups $groupRef) -}}
    {{- $_ := include "covenant.applyGrant" (list $group $grant) -}}
    {{- $resolvedSubjects = append $resolvedSubjects (dict "kind" "group" "ref" $groupRef) -}}
  {{- end -}}
  {{- $resolvedBindings = append $resolvedBindings (dict "key" $bindingRef "roleRef" $roleRef "subjects" $resolvedSubjects "grant" $grant "reason" (default "" $binding.reason) "source" $binding.source) -}}
{{- end -}}

{{/* Validate canonical references before producing any intent. */}}
{{- range $groupRef, $group := $groups -}}
  {{- if $group.resolvedGroups -}}
    {{- fail (printf "covenant: group binding for %q resolves to group membership; bind that role to principals because nested Keycloak groups are not supported" $groupRef) -}}
  {{- end -}}
  {{- range $roleRef := default list $group.resolvedRealmRoles -}}
    {{- if not (hasKey $realmRoles $roleRef) -}}{{- fail (printf "covenant: group %q references unknown realm role %q" $groupRef $roleRef) -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- range $principalRef, $principal := $principals -}}
  {{- range $roleRef := default list $principal.resolvedRealmRoles -}}
    {{- if not (hasKey $realmRoles $roleRef) -}}{{- fail (printf "covenant: principal %q references unknown realm role %q" $principalRef $roleRef) -}}{{- end -}}
  {{- end -}}
  {{- range $groupRef := default list $principal.resolvedGroups -}}
    {{- if not (hasKey $groups $groupRef) -}}{{- fail (printf "covenant: principal %q references unknown group %q" $principalRef $groupRef) -}}{{- end -}}
  {{- end -}}
{{- end -}}

{{- $intentGroups := dict "realm" (list) "identities" (list) "applications" (list) "authorization" (list) "report" (list) -}}
{{- $indexSource := dict "path" $indexPath "entry" $organizationName -}}
{{- $realmIntentType := ternary "keycloak.cluster-realm" "keycloak.realm" (eq $realmScope "cluster") -}}
{{- $realmIntent := include "covenant.intent" (list (printf "realm.%s" $realmName) $realmIntentType "0" (printf "organization.%s" $organizationName) $realmProviderRef $indexSource $realm) | fromJson -}}
{{- $_ := set $intentGroups "realm" (append $intentGroups.realm $realmIntent) -}}

{{- range $roleRef, $role := $realmRoles -}}
  {{- $spec := deepCopy $role -}}
  {{- $_ := set $spec "roleName" (default $roleRef $role.name) -}}
  {{- $composites := list -}}
  {{- range $compositeRef := default list $role.compositeRoles -}}
    {{- $composite := required (printf "covenant: realm role %q references unknown composite %q" $roleRef $compositeRef) (get $realmRoles $compositeRef) -}}
    {{- $composites = append $composites (default $compositeRef $composite.name) -}}
  {{- end -}}
  {{- $_ := set $spec "compositeRoles" $composites -}}
  {{- $_ := set $spec "realmRef" $realm.resourceName -}}
  {{- $_ := set $spec "realmRefKind" $realm.refKind -}}
  {{- $intent := include "covenant.intent" (list (printf "realm-role.%s" $roleRef) "keycloak.realm-role" "1" (printf "organization.%s" $organizationName) $realmProviderRef $role.source $spec) | fromJson -}}
  {{- $_ := set $intentGroups "realm" (append $intentGroups.realm $intent) -}}
{{- end -}}

{{- range $scopeRef, $scope := $clientScopes -}}
  {{- $spec := deepCopy $scope -}}
  {{- $_ := set $spec "scopeName" (default $scopeRef $scope.name) -}}
  {{- $_ := set $spec "realmRef" $realm.resourceName -}}
  {{- $_ := set $spec "realmRefKind" $realm.refKind -}}
  {{- $intent := include "covenant.intent" (list (printf "client-scope.%s" $scopeRef) "keycloak.client-scope" "1" (printf "organization.%s" $organizationName) $realmProviderRef $scope.source $spec) | fromJson -}}
  {{- $_ := set $intentGroups "realm" (append $intentGroups.realm $intent) -}}
{{- end -}}
{{- range $idpRef, $idp := $identityProviders -}}
  {{- $enabled := true -}}{{- if hasKey $idp "enabled" -}}{{- $enabled = $idp.enabled -}}{{- end -}}
  {{- if $enabled -}}
    {{- $spec := deepCopy $idp -}}{{- $_ := set $spec "realmRef" $realm.resourceName -}}{{- $_ := set $spec "realmRefKind" $realm.refKind -}}{{- $_ := set $spec "alias" (default $idpRef $idp.alias) -}}
    {{- with $idp.credentials -}}
      {{- if hasKey . "providerRef" -}}{{- fail (printf "covenant: identity provider %q credentials cannot select infrastructure providerRef" $idpRef) -}}{{- end -}}
      {{- $vaultRef := "credentials" -}}
      {{- if not (hasKey $providers $vaultRef) -}}{{- $_ := set $providers $vaultRef (include "covenant.provider" (list $root $vaultRef "secret-store") | fromJson) -}}{{- end -}}
      {{- $vault := get $providers $vaultRef -}}
      {{- $secretName := include "covenant.physical" (list $idpRef (default (printf "covenant-idp-%s" $idp.resourceName) .secretName)) -}}
      {{- $secretKey := default "client_secret" .secretKey -}}
      {{- $configKey := default "clientSecret" .configKey -}}
      {{- $path := printf "/covenant/%s/idps/%s" $realmName $idp.resourceName -}}
      {{- $accessName := printf "%s-idp-%s" ($book | replace "." "-") $idp.resourceName | trunc 63 | trimSuffix "-" -}}
      {{- $accessSpec := dict "name" $accessName "namespace" (default $root.Release.Namespace $root.Values.namespace) "serviceAccount" $accessName "createServiceAccount" true "paths" (list (dict "path" (printf "%s/data%s" $vault.secretPath $path) "capabilities" (list "read")) (dict "path" (printf "%s/metadata%s" $vault.secretPath $path) "capabilities" (list "read"))) -}}
      {{- $accessIntent := include "covenant.intent" (list (printf "provider-access.idp.%s" $idpRef) "vault.provider-access" "0" (printf "identity-provider.%s" $idpRef) $vaultRef $idp.source $accessSpec) | fromJson -}}
      {{- $_ := set $intentGroups "realm" (append $intentGroups.realm $accessIntent) -}}
      {{- $_ := set $spec "credentialContext" (dict "providerRef" $vaultRef "serviceAccount" $accessName "role" $accessName "path" $path "secretName" $secretName "secretKey" $secretKey "configKey" $configKey) -}}
    {{- end -}}
    {{- $intent := include "covenant.intent" (list (printf "identity-provider.%s" $idpRef) "keycloak.identity-provider" "2" (printf "organization.%s" $organizationName) $realmProviderRef $idp.source $spec) | fromJson -}}
    {{- $_ := set $intentGroups "realm" (append $intentGroups.realm $intent) -}}
  {{- end -}}
{{- end -}}
{{- range $flowRef, $flow := $authenticationFlows -}}
  {{- $enabled := true -}}{{- if hasKey $flow "enabled" -}}{{- $enabled = $flow.enabled -}}{{- end -}}
  {{- if $enabled -}}
    {{- $spec := deepCopy $flow -}}{{- $_ := set $spec "realmRef" $realm.resourceName -}}{{- $_ := set $spec "realmRefKind" $realm.refKind -}}{{- $_ := set $spec "alias" (default $flowRef $flow.alias) -}}
    {{- $intent := include "covenant.intent" (list (printf "authentication-flow.%s" $flowRef) "keycloak.authentication-flow" "1" (printf "organization.%s" $organizationName) $realmProviderRef $flow.source $spec) | fromJson -}}
    {{- $_ := set $intentGroups "realm" (append $intentGroups.realm $intent) -}}
  {{- end -}}
{{- end -}}

{{- $identityCredentialShards := dict -}}
{{- range $email := keys $principalRefsByEmail | sortAlpha -}}
  {{- $principal := get $principals (get $principalRefsByEmail $email) -}}
  {{- $enabled := false -}}{{- if hasKey $principal.initialPassword "enabled" -}}{{- $enabled = $principal.initialPassword.enabled -}}{{- end -}}
  {{- if $enabled -}}
    {{- $shard := include "covenant.principalShard" $principal -}}
    {{- $secretName := printf "principal-password-%s" $principal.resourceName | trunc 63 | trimSuffix "-" -}}
    {{- $_ := set $identityCredentialShards $shard (append (default list (get $identityCredentialShards $shard)) $secretName) -}}
  {{- end -}}
{{- end -}}
{{- $identityCredentialContexts := dict -}}
{{- if $identityCredentialShards -}}
  {{- $vaultRef := "credentials" -}}
  {{- if not (hasKey $providers $vaultRef) -}}{{- $_ := set $providers $vaultRef (include "covenant.provider" (list $root $vaultRef "secret-store") | fromJson) -}}{{- end -}}
  {{- $vault := get $providers $vaultRef -}}
  {{- range $shard := keys $identityCredentialShards | sortAlpha -}}
    {{- $sa := printf "%s-principals-%s" ($book | replace "." "-") $shard | trunc 63 | trimSuffix "-" -}}
    {{- $paths := list -}}
    {{- range $secretName := get $identityCredentialShards $shard -}}
      {{- $paths = append $paths (dict "path" (printf "%s/data/covenant/%s/principals/%s" $vault.secretPath $realmName $secretName) "capabilities" (list "create" "read" "update" "delete" "list")) -}}
      {{- $paths = append $paths (dict "path" (printf "%s/metadata/covenant/%s/principals/%s" $vault.secretPath $realmName $secretName) "capabilities" (list "create" "read" "update" "delete" "list")) -}}
    {{- end -}}
    {{- $paths = append $paths (dict "path" "sys/policies/password/*" "capabilities" (list "read" "list")) -}}
    {{- $accessSpec := dict "name" $sa "namespace" (default $root.Release.Namespace $root.Values.namespace) "serviceAccount" $sa "createServiceAccount" true "paths" $paths -}}
    {{- $accessIntent := include "covenant.intent" (list (printf "provider-access.%s" $sa) "vault.provider-access" "0" (printf "principal-shard.%s" $shard) $vaultRef $indexSource $accessSpec) | fromJson -}}
    {{- $_ := set $accessIntent "principalShard" $shard -}}
    {{- $_ := set $intentGroups "identities" (append $intentGroups.identities $accessIntent) -}}
    {{- $_ := set $identityCredentialContexts $shard (dict "providerRef" $vaultRef "serviceAccount" $sa "role" $sa "path" (printf "/covenant/%s/principals/" $realmName)) -}}
  {{- end -}}
{{- end -}}

{{- range $groupRef, $group := $groups -}}
  {{- $realmRoleNames := list -}}
  {{- range $roleRef := default list $group.resolvedRealmRoles -}}{{- $role := get $realmRoles $roleRef -}}{{- $realmRoleNames = append $realmRoleNames (default $roleRef $role.name) -}}{{- end -}}
  {{- $clientRoles := list -}}
  {{- range $clientId, $roles := default dict $group.resolvedClientRoles -}}{{- $clientRoles = append $clientRoles (dict "clientId" $clientId "roles" $roles) -}}{{- end -}}
  {{- $spec := deepCopy $group -}}
  {{- $_ := set $spec "scopeName" (default $groupRef $group.name) -}}{{- $_ := set $spec "realmRef" $realm.resourceName -}}{{- $_ := set $spec "realmRoles" $realmRoleNames -}}{{- $_ := set $spec "clientRoles" $clientRoles -}}
  {{- $_ := set $spec "realmRefKind" $realm.refKind -}}
  {{- $intent := include "covenant.intent" (list (printf "group.%s" $groupRef) "keycloak.group" "2" (printf "organization.%s" $organizationName) $realmProviderRef $group.source $spec) | fromJson -}}
  {{- $_ := set $intentGroups "identities" (append $intentGroups.identities $intent) -}}
{{- end -}}
{{- range $email := keys $principalRefsByEmail | sortAlpha -}}
  {{- $principalRef := get $principalRefsByEmail $email -}}
  {{- $principal := get $principals $principalRef -}}
  {{- $principalShard := include "covenant.principalShard" $principal -}}
  {{- $realmRoleNames := list -}}
  {{- range $roleRef := default list $principal.resolvedRealmRoles -}}{{- $role := get $realmRoles $roleRef -}}{{- $realmRoleNames = append $realmRoleNames (default $roleRef $role.name) -}}{{- end -}}
  {{- $groupNames := list -}}
  {{- range $groupRef := default list $principal.resolvedGroups -}}{{- $group := get $groups $groupRef -}}{{- $groupNames = append $groupNames (default $groupRef $group.name) -}}{{- end -}}
  {{- $clientRoles := list -}}
  {{- range $clientId := keys (default dict $principal.resolvedClientRoles) | sortAlpha -}}
    {{- $clientRoles = append $clientRoles (dict "clientId" $clientId "roles" (get $principal.resolvedClientRoles $clientId)) -}}
  {{- end -}}
  {{- $spec := deepCopy $principal -}}
  {{- $_ := set $spec "realmRef" $realm.resourceName -}}{{- $_ := set $spec "realmRoles" $realmRoleNames -}}{{- $_ := set $spec "groups" $groupNames -}}{{- $_ := set $spec "clientRoles" $clientRoles -}}
  {{- $_ := set $spec "realmRefKind" $realm.refKind -}}
  {{- $passwordEnabled := false -}}{{- if hasKey $principal.initialPassword "enabled" -}}{{- $passwordEnabled = $principal.initialPassword.enabled -}}{{- end -}}
  {{- if and $passwordEnabled (hasKey $identityCredentialContexts $principalShard) -}}{{- $_ := set $spec "credentialContext" (get $identityCredentialContexts $principalShard) -}}{{- end -}}
  {{- $intent := include "covenant.intent" (list (printf "principal.%s" $principalRef) "keycloak.principal" "3" (printf "principal.%s" $principalRef) $realmProviderRef $principal.source $spec) | fromJson -}}
  {{- $_ := set $intent "principalShard" $principalShard -}}
  {{- $_ := set $intentGroups "identities" (append $intentGroups.identities $intent) -}}
{{- end -}}

{{- range $applicationKey, $application := $applications -}}
  {{- with get (default dict $application.clients) $realmName -}}
    {{- $clientKey := $realmName -}}{{- $client := deepCopy . -}}
    {{- $enabled := true -}}{{- if hasKey $client "enabled" -}}{{- $enabled = $client.enabled -}}{{- end -}}
    {{- if $enabled -}}
    {{- if hasKey $client "realmRef" -}}{{- fail (printf "covenant: client %s/%s must use its map key as the realm; realmRef is not valid" $applicationKey $clientKey) -}}{{- end -}}
    {{- if hasKey $client "providerRef" -}}{{- fail (printf "covenant: client %s/%s cannot select infrastructure providerRef" $applicationKey $clientKey) -}}{{- end -}}
    {{- if hasKey $client "defaultClientScopes" -}}{{- fail (printf "covenant: client %s/%s must inherit realm scopes and use scopes.include/scopes.exclude only for exceptions" $applicationKey $clientKey) -}}{{- end -}}
    {{- $type := default "oidc" $client.type -}}
    {{- if not (has $type (list "oidc" "saml" "serviceAccount")) -}}{{- fail (printf "covenant: unsupported client type %q" $type) -}}{{- end -}}
    {{- $public := false -}}{{- if hasKey $client "public" -}}{{- $public = $client.public -}}{{- end -}}
    {{- $directAccess := false -}}{{- if hasKey $client "directAccess" -}}{{- $directAccess = $client.directAccess -}}{{- end -}}
    {{- $standardFlow := true -}}{{- if hasKey $client "standardFlowEnabled" -}}{{- $standardFlow = $client.standardFlowEnabled -}}{{- end -}}
    {{- if eq $type "serviceAccount" -}}{{- $standardFlow = false -}}{{- end -}}
    {{- $_ := set $client "type" $type -}}{{- $_ := set $client "public" $public -}}{{- $_ := set $client "directAccess" $directAccess -}}{{- $_ := set $client "standardFlowEnabled" $standardFlow -}}
    {{- $_ := set $client "applicationKey" $applicationKey -}}{{- $_ := set $client "clientKey" $clientKey -}}{{- $_ := set $client "clientId" (default $applicationKey $client.clientId) -}}{{- $_ := set $client "resourceName" (include "covenant.physical" (list (printf "%s-%s" $applicationKey $realmName) (default "" $client.resourceName))) -}}{{- $_ := set $client "realmRef" $realm.resourceName -}}{{- $_ := set $client "realmRefKind" $realm.refKind -}}
    {{- if not (hasKey $client "webOrigins") -}}{{- $_ := set $client "webOrigins" (list (required (printf "covenant: client %s/%s requires webUrl" $applicationKey $realmName) $client.webUrl)) -}}{{- end -}}
    {{- $resolvedScopes := deepCopy $defaultClientScopes -}}
    {{- with $client.scopes -}}
      {{- range $scopeRef := default list .exclude -}}
        {{- $scope := required (printf "covenant: client %s/%s excludes unknown realm scope %q" $applicationKey $realmName $scopeRef) (get $clientScopes $scopeRef) -}}
        {{- $resolvedScopes = without $resolvedScopes (default $scopeRef $scope.name) -}}
      {{- end -}}
      {{- range $scopeRef := default list .include -}}
        {{- $scope := required (printf "covenant: client %s/%s includes unknown realm scope %q" $applicationKey $realmName $scopeRef) (get $clientScopes $scopeRef) -}}
        {{- $resolvedScopes = append $resolvedScopes (default $scopeRef $scope.name) | uniq -}}
      {{- end -}}
    {{- end -}}
    {{- $_ := set $client "defaultClientScopes" $resolvedScopes -}}{{- $_ := unset $client "scopes" -}}
    {{- with $client.certificate -}}
      {{- if ne $type "saml" -}}{{- fail (printf "covenant: only SAML client %s/%s may declare a certificate" $applicationKey $realmName) -}}{{- end -}}
      {{- if hasKey . "providerRef" -}}{{- fail (printf "covenant: SAML client %s/%s certificate cannot select infrastructure providerRef" $applicationKey $realmName) -}}{{- end -}}
      {{- $dnsNames := required (printf "covenant: SAML client %s/%s certificate.dnsNames is required" $applicationKey $realmName) .dnsNames -}}
      {{- $certificateName := include "covenant.physical" (list (printf "%s-saml" $client.resourceName) (default "" .name)) -}}
      {{- $_ := set . "resourceName" $certificateName -}}
      {{- $_ := set . "secretName" (include "covenant.physical" (list (printf "%s-certificate" $certificateName) (default "" .secretName))) -}}
      {{- $_ := set . "namespace" $application.namespace -}}
      {{- $_ := set . "commonName" (default (index $dnsNames 0) .commonName) -}}
      {{- $certificateRef := "certificates" -}}
      {{- if not (hasKey $providers $certificateRef) -}}{{- $_ := set $providers $certificateRef (include "covenant.provider" (list $root $certificateRef "cert-issuer") | fromJson) -}}{{- end -}}
      {{- $_ := set . "providerRef" $certificateRef -}}
    {{- end -}}
    {{- $intentType := "keycloak.oidc-client" -}}{{- if eq $type "saml" -}}{{- $intentType = "keycloak.saml-client" -}}{{- else if eq $type "serviceAccount" -}}{{- $intentType = "keycloak.service-account-client" -}}{{- end -}}
    {{- if and (eq $type "oidc") $public (hasKey $client "credentials") -}}{{- fail (printf "covenant: public client %s/%s cannot declare credentials" $applicationKey $realmName) -}}{{- end -}}
    {{- if and (ne $type "saml") (not $public) -}}
      {{- $credentials := deepCopy (default dict $client.credentials) -}}
      {{- if hasKey $credentials "providerRef" -}}{{- fail (printf "covenant: client %s/%s credentials cannot select infrastructure providerRef" $applicationKey $realmName) -}}{{- end -}}
      {{- if not (hasKey $credentials "passwordPolicy") -}}{{- $_ := set $credentials "passwordPolicy" $credentialPasswordPolicy -}}{{- end -}}
      {{- $sinks := list (dict) -}}
      {{- if and (hasKey $credentials "publish") (not $credentials.publish) -}}
        {{- $sinks = list -}}
      {{- else if hasKey $credentials "sinks" -}}
        {{- $sinks = $credentials.sinks -}}
      {{- end -}}
      {{- $_ := unset $credentials "publish" -}}
      {{- $normalizedSinks := list -}}
      {{- range $sink := $sinks -}}
        {{- $normalizedSink := deepCopy (default dict $sink) -}}
        {{- $sinkName := include "covenant.logical" (default $applicationKey $normalizedSink.name) -}}
        {{- $_ := set $normalizedSink "name" $sinkName -}}
        {{- $_ := set $normalizedSink "namespace" (default $application.namespace $normalizedSink.namespace) -}}
        {{- $_ := set $normalizedSink "serviceAccount" (default (include "covenant.physical" (list $applicationKey "")) $normalizedSink.serviceAccount) -}}
        {{- $sinkSecret := deepCopy (default dict $normalizedSink.secret) -}}
        {{- $_ := set $sinkSecret "name" (default (printf "keycloak-client-%s" (include "covenant.physical" (list $applicationKey ""))) $sinkSecret.name) -}}
        {{- $_ := set $normalizedSink "secret" $sinkSecret -}}
        {{- $normalizedSinks = append $normalizedSinks $normalizedSink -}}
      {{- end -}}
      {{- $_ := set $credentials "sinks" $normalizedSinks -}}{{- $_ := set $client "credentials" $credentials -}}
      {{- $vaultRef := "credentials" -}}
      {{- if not (hasKey $providers $vaultRef) -}}{{- $_ := set $providers $vaultRef (include "covenant.provider" (list $root $vaultRef "secret-store") | fromJson) -}}{{- end -}}
      {{- $vault := get $providers $vaultRef -}}
      {{- $sa := printf "%s-applications-%s" ($book | replace "." "-") ($vaultRef | replace "." "-") | trunc 63 | trimSuffix "-" -}}
      {{- $_ := set $client "credentialContext" (dict "providerRef" $vaultRef "serviceAccount" $sa "role" $sa "path" (printf "/covenant/%s/clients/" $realmName)) -}}
      {{- if not (hasKey $applicationProducerAccess $vaultRef) -}}
        {{- $accessSpec := dict "name" $sa "namespace" (default $root.Release.Namespace $root.Values.namespace) "serviceAccount" $sa "createServiceAccount" true "paths" (list (dict "path" (printf "%s/data/covenant/%s/clients/*" $vault.secretPath $realmName) "capabilities" (list "create" "read" "update" "delete" "list")) (dict "path" (printf "%s/metadata/covenant/%s/clients/*" $vault.secretPath $realmName) "capabilities" (list "create" "read" "update" "delete" "list")) (dict "path" "sys/policies/password/*" "capabilities" (list "read" "list"))) -}}
        {{- $_ := set $applicationProducerAccess $vaultRef $accessSpec -}}
      {{- end -}}
      {{- $producerName := printf "client-credentials-%s" $client.resourceName | trunc 63 | trimSuffix "-" -}}
      {{- range $sink := $normalizedSinks -}}
        {{- $sinkName := $sink.name -}}
        {{- $sinkNamespace := $sink.namespace -}}
        {{- $sinkServiceAccount := $sink.serviceAccount -}}
        {{- $accessKey := printf "%s.%s.%s" $applicationKey $realmName $sinkName -}}
        {{- if hasKey $applicationSinkAccess $accessKey -}}{{- fail (printf "covenant: duplicate credential sink access %q" $accessKey) -}}{{- end -}}
        {{- $roleName := default (printf "covenant-%s-%s" $client.resourceName ($sinkName | replace "." "-")) $sink.role | trunc 63 | trimSuffix "-" -}}
        {{- $sinkAccess := dict "name" $roleName "namespace" $sinkNamespace "serviceAccount" $sinkServiceAccount "createServiceAccount" false "paths" (list (dict "path" (printf "%s/data/covenant/%s/clients/%s" $vault.secretPath $realmName $producerName) "capabilities" (list "read")) (dict "path" (printf "%s/metadata/covenant/%s/clients/%s" $vault.secretPath $realmName $producerName) "capabilities" (list "read"))) "providerRef" $vaultRef "source" $application.source -}}
        {{- $_ := set $applicationSinkAccess $accessKey $sinkAccess -}}
      {{- end -}}
    {{- end -}}
    {{- $intent := include "covenant.intent" (list (printf "application.%s.client.%s" $applicationKey $realmName) $intentType "2" (printf "application.%s" $applicationKey) $realmProviderRef $application.source $client) | fromJson -}}
    {{- $_ := set $intentGroups "applications" (append $intentGroups.applications $intent) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- range $vaultRef, $accessSpec := $applicationProducerAccess -}}
  {{- $accessIntent := include "covenant.intent" (list (printf "provider-access.%s" $accessSpec.name) "vault.provider-access" "0" (printf "organization.%s" $organizationName) $vaultRef $indexSource $accessSpec) | fromJson -}}
  {{- $_ := set $intentGroups "applications" (prepend $intentGroups.applications $accessIntent) -}}
{{- end -}}
{{- range $accessKey, $accessSpec := $applicationSinkAccess -}}
  {{- $vaultRef := $accessSpec.providerRef -}}
  {{- $source := $accessSpec.source -}}
  {{- $_ := unset $accessSpec "providerRef" -}}{{- $_ := unset $accessSpec "source" -}}
  {{- $accessIntent := include "covenant.intent" (list (printf "provider-access.%s" $accessKey) "vault.provider-access" "0" (printf "credential-sink.%s" $accessKey) $vaultRef $source $accessSpec) | fromJson -}}
  {{- $_ := set $intentGroups "applications" (append $intentGroups.applications $accessIntent) -}}
{{- end -}}

{{- $authorizationSpec := dict "realm" $realmName "roles" $authorizationRoles "bindings" $resolvedBindings -}}
{{- $authorizationIntent := include "covenant.intent" (list (printf "authorization.%s" $realmName) "covenant.authorization-report" "4" (printf "organization.%s" $organizationName) "covenant" $indexSource $authorizationSpec) | fromJson -}}
{{- $_ := set $intentGroups "authorization" (append $intentGroups.authorization $authorizationIntent) -}}
{{- $counts := dict "realmRoles" (len $realmRoles) "clientScopes" (len $clientScopes) "identityProviders" (len $identityProviders) "authenticationFlows" (len $authenticationFlows) "groups" (len $groups) "principals" (len $principals) "applications" (len $applications) "authorizationRoles" (len $authorizationRoles) "bindings" (len $bindings) -}}
{{- $reportSpec := dict "organization" $organizationName "realm" $realmName "counts" $counts -}}
{{- $reportIntent := include "covenant.intent" (list (printf "compile-report.%s" $realmName) "covenant.compile-report" "4" (printf "organization.%s" $organizationName) "covenant" $indexSource $reportSpec) | fromJson -}}
{{- $_ := set $intentGroups "report" (append $intentGroups.report $reportIntent) -}}

{{- $intents := concat $intentGroups.realm $intentGroups.identities $intentGroups.applications $intentGroups.authorization $intentGroups.report -}}
{{- dict "book" $book "organization" $organization "realm" $realm "providers" $providers "intents" $intents "applications" $applications "principalShards" $principalShards | toJson -}}
{{- end -}}
