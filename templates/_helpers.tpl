{{/* SPDX-License-Identifier: AGPL-3.0-only */}}

{{- define "covenant.labels" -}}
app.kubernetes.io/name: covenant
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
runik.io/component: covenant
{{- end -}}

{{- define "covenant.logical" -}}
{{- $value := required "covenant: logical name is required" . -}}
{{- if not (regexMatch "^[a-z0-9]+(-[a-z0-9]+)*$" $value) -}}
  {{- fail (printf "covenant: logical name %q must be lowercase kebab-case" $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{- define "covenant.physical" -}}
{{- $logical := include "covenant.logical" (index . 0) -}}
{{- $override := "" -}}
{{- if ge (len .) 2 -}}
  {{- $override = default "" (index . 1) -}}
{{- end -}}
{{- $name := default $logical $override | lower -}}
{{- if or (gt (len $name) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name)) -}}
  {{- fail (printf "covenant: physical name %q must be a DNS label of at most 63 characters" $name) -}}
{{- end -}}
{{- $name -}}
{{- end -}}

{{- define "covenant.principalShard" -}}
{{- $email := required "covenant: generated principal email is required for grouping" .email -}}
{{- $initial := substr 0 1 $email -}}
{{- if regexMatch "^[0-9]$" $initial -}}0-9{{- else -}}{{- $initial -}}{{- end -}}
{{- end -}}

{{- define "covenant.principal" -}}
{{- $principal := deepCopy (index . 0) -}}
{{- $domain := required "covenant: realm.domain is required" (index . 1) -}}
{{- $defaults := default dict (index . 2) -}}
{{- $source := index . 3 -}}
{{- range $derived := list "key" "id" "principalRef" "username" "email" -}}
  {{- if hasKey $principal $derived -}}
    {{- fail (printf "covenant: principal at %s cannot define derived field %s" $source.path $derived) -}}
  {{- end -}}
{{- end -}}
{{- $name := required (printf "covenant: principal.name is required at %s" $source.path) $principal.name | lower -}}
{{- if not (regexMatch "^[a-z0-9]+$" $name) -}}
  {{- fail (printf "covenant: principal name %q at %s must be one lowercase alphanumeric login segment" $name $source.path) -}}
{{- end -}}
{{- $lastName := default "" $principal.lastName | lower -}}
{{- if and $lastName (not (regexMatch "^[a-z0-9]+$" $lastName)) -}}
  {{- fail (printf "covenant: principal lastName %q at %s must be one lowercase alphanumeric login segment" $lastName $source.path) -}}
{{- end -}}
{{- $login := $name -}}
{{- $ref := $name -}}
{{- if $lastName -}}
  {{- $login = printf "%s.%s" $name $lastName -}}
  {{- $ref = printf "%s-%s" $name $lastName -}}
{{- end -}}
{{- $profile := default dict $principal.profile -}}
{{- $status := default "active" $defaults.status -}}
{{- if hasKey $principal "status" -}}{{- $status = $principal.status -}}{{- end -}}
{{- if not (has $status (list "active" "suspended")) -}}
  {{- fail (printf "covenant: principal %s status must be active or suspended" $ref) -}}
{{- end -}}
{{- $emailVerified := true -}}
{{- if hasKey $defaults "emailVerified" -}}{{- $emailVerified = $defaults.emailVerified -}}{{- end -}}
{{- if hasKey $principal "emailVerified" -}}{{- $emailVerified = $principal.emailVerified -}}{{- end -}}
{{- $initialPassword := deepCopy (default dict $defaults.initialPassword) -}}
{{- if hasKey $principal "initialPassword" -}}
  {{- $initialPassword = mergeOverwrite $initialPassword (deepCopy $principal.initialPassword) -}}
{{- end -}}
{{- $_ := set $principal "principalRef" $ref -}}
{{- $_ := set $principal "resourceName" (include "covenant.physical" (list $ref (default "" $principal.resourceName))) -}}
{{- $_ := set $principal "username" (printf "%s@%s" $login $domain) -}}
{{- $_ := set $principal "email" (printf "%s@%s" $login $domain) -}}
{{- $_ := set $principal "enabled" (eq $status "active") -}}
{{- $_ := set $principal "emailVerified" $emailVerified -}}
{{- $_ := set $principal "profile" $profile -}}
{{- $_ := set $principal "initialPassword" $initialPassword -}}
{{- $_ := set $principal "source" $source -}}
{{- $principal | toJson -}}
{{- end -}}

{{- define "covenant.provider" -}}
{{- $root := index . 0 -}}
{{- $ref := index . 1 -}}
{{- $type := index . 2 -}}
{{- $chapter := default "identity" (($root.Values.chapter).name) -}}
{{- $selector := dict "default" "book" -}}
{{- $matches := get (include "runic-system.runic-indexer" (list (default dict $root.Values.lexicon) $selector $type $chapter) | fromJson) "results" -}}
{{- if ne (len $matches) 1 -}}
  {{- fail (printf "covenant: Lexicon must contain exactly one book-default %s provider for %s, got %d" $type $ref (len $matches)) -}}
{{- end -}}
{{- $resolved := deepCopy (index $matches 0) -}}
{{- $_ := set $resolved "covenantRef" $ref -}}
{{- $resolved | toJson -}}
{{- end -}}

{{- define "covenant.intent" -}}
{{- $id := index . 0 -}}
{{- $type := index . 1 -}}
{{- $syncWave := index . 2 -}}
{{- $owner := index . 3 -}}
{{- $providerRef := index . 4 -}}
{{- $source := index . 5 -}}
{{- $spec := index . 6 -}}
{{- dict "id" $id "type" $type "syncWave" $syncWave "owner" $owner "providerRef" $providerRef "source" $source "spec" $spec | toJson -}}
{{- end -}}

{{- define "covenant.intentAnnotations" -}}
{{- $intent := . -}}
{{- $syncWave := "" -}}
{{- if kindIs "slice" . -}}
  {{- $intent = index . 0 -}}
  {{- if ge (len .) 2 -}}{{- $syncWave = index . 1 -}}{{- end -}}
{{- end -}}
{{- if not $syncWave -}}{{- $syncWave = required (printf "covenant: intent %s requires syncWave" $intent.id) $intent.syncWave -}}{{- end -}}
{{- $annotations := deepCopy (default dict $intent.spec.annotations) -}}
{{- $_ := set $annotations "argocd.argoproj.io/sync-wave" $syncWave -}}
{{- $annotations | toJson -}}
{{- end -}}

{{- define "covenant.applicationRoleGrant" -}}
{{- $applications := index . 0 -}}
{{- $applicationKey := include "covenant.logical" (index . 1) -}}
{{- $roleKey := include "covenant.logical" (index . 2) -}}
{{- $realmName := index . 3 -}}
{{- $application := required (printf "covenant: application %q is not published" $applicationKey) (get $applications $applicationKey) -}}
{{- $role := required (printf "covenant: application %q does not publish role %q" $applicationKey $roleKey) (get (default dict $application.roles) $roleKey) -}}
{{- $target := $role -}}
{{- if hasKey $role "claim" -}}
  {{- $target = required (printf "covenant: claim role %s.%s requires a definition" $applicationKey $roleKey) $role.claim -}}
{{- end -}}
{{- $targetTypes := list -}}
{{- range $candidate := list "realmRole" "group" "clientRole" -}}
  {{- if hasKey $target $candidate -}}{{- $targetTypes = append $targetTypes $candidate -}}{{- end -}}
{{- end -}}
{{- if ne (len $targetTypes) 1 -}}
  {{- fail (printf "covenant: application role %s.%s must define exactly one of realmRole, group, or clientRole" $applicationKey $roleKey) -}}
{{- end -}}
{{- $targetType := index $targetTypes 0 -}}
{{- $targetRef := include "covenant.logical" (required (printf "covenant: application role %s.%s %s is required" $applicationKey $roleKey $targetType) (get $target $targetType)) -}}
{{- if eq $targetType "realmRole" -}}
  {{- dict "realmRoles" (list $targetRef) | toJson -}}
{{- else if eq $targetType "group" -}}
  {{- dict "groups" (list $targetRef) | toJson -}}
{{- else if eq $targetType "clientRole" -}}
  {{- $matches := list -}}
  {{- range $clientKey, $client := default dict $application.clients -}}
    {{- $enabled := true -}}
    {{- if hasKey $client "enabled" -}}{{- $enabled = $client.enabled -}}{{- end -}}
    {{- if and (eq $clientKey $realmName) $enabled -}}
      {{- $matches = append $matches (dict "key" $clientKey "definition" $client) -}}
    {{- end -}}
  {{- end -}}
  {{- if ne (len $matches) 1 -}}
    {{- fail (printf "covenant: clientRole target %s.%s requires exactly one client for realm %s" $applicationKey $roleKey $realmName) -}}
  {{- end -}}
  {{- $client := (index $matches 0).definition -}}
  {{- if not (has $targetRef (default list $client.clientRoles)) -}}
    {{- fail (printf "covenant: client %s/%s does not declare client role %q" $applicationKey $realmName $targetRef) -}}
  {{- end -}}
  {{- dict "clientRoles" (dict (default $applicationKey $client.clientId) (list $targetRef)) | toJson -}}
{{- else -}}
  {{- fail (printf "covenant: unsupported explicit target type %q for %s.%s" $targetType $applicationKey $roleKey) -}}
{{- end -}}
{{- end -}}

{{- define "covenant.applyGrant" -}}
{{- $subject := index . 0 -}}
{{- $grant := index . 1 -}}
{{- $realmRoles := concat (default list $subject.resolvedRealmRoles) (default list $grant.realmRoles) | uniq -}}
{{- $groups := concat (default list $subject.resolvedGroups) (default list $grant.groups) | uniq -}}
{{- $_ := set $subject "resolvedRealmRoles" $realmRoles -}}
{{- $_ := set $subject "resolvedGroups" $groups -}}
{{- if $grant.clientRoles -}}
  {{- $current := deepCopy (default dict $subject.resolvedClientRoles) -}}
  {{- range $clientId, $roles := $grant.clientRoles -}}
    {{- $_ := set $current $clientId (concat (default list (get $current $clientId)) $roles | uniq) -}}
  {{- end -}}
  {{- $_ := set $subject "resolvedClientRoles" $current -}}
{{- end -}}
{{- end -}}

{{- define "covenant.resolveRole" -}}
{{- $role := index . 0 -}}
{{- $applications := index . 1 -}}
{{- $realmName := index . 2 -}}
{{- $grants := required (printf "covenant: authorization role %q requires grants" $role.key) $role.grants -}}
{{- range $forbidden := list "realmRoles" "applicationRoles" "roles" "entitlements" "packages" "groups" -}}
  {{- if hasKey $role $forbidden -}}
    {{- fail (printf "covenant: authorization role %q must put permissions under grants, not %s" $role.key $forbidden) -}}
  {{- end -}}
{{- end -}}
{{- range $grantType, $_ := $grants -}}
  {{- if not (has $grantType (list "realmRoles" "applicationRoles")) -}}{{- fail (printf "covenant: authorization role %q has unsupported grant type %s" $role.key $grantType) -}}{{- end -}}
{{- end -}}
{{- $realmRoles := list -}}
{{- range $realmRole := default list $grants.realmRoles -}}
  {{- $realmRoles = append $realmRoles (include "covenant.logical" $realmRole) | uniq -}}
{{- end -}}
{{- $accumulator := dict "resolvedRealmRoles" $realmRoles "resolvedGroups" (list) "resolvedClientRoles" (dict) -}}
{{- range $applicationRole := default list $grants.applicationRoles -}}
  {{- $resolved := include "covenant.applicationRoleGrant" (list $applications $applicationRole.application $applicationRole.role $realmName) | fromJson -}}
  {{- $_ := include "covenant.applyGrant" (list $accumulator $resolved) -}}
{{- end -}}
{{- dict "realmRoles" $accumulator.resolvedRealmRoles "groups" $accumulator.resolvedGroups "clientRoles" $accumulator.resolvedClientRoles | toJson -}}
{{- end -}}
