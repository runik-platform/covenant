{{/* SPDX-License-Identifier: AGPL-3.0-only */}}

{{- define "covenant.meta.realm" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $providers := index . 2 -}}
{{- $provider := required (printf "covenant: providerRef %q is missing" $intent.providerRef) (get $providers $intent.providerRef) -}}
{{- $glyph := deepCopy $intent.spec -}}
{{- $_ := set $glyph "name" $intent.spec.resourceName -}}
{{- $_ := set $glyph "annotations" (include "covenant.intentAnnotations" $intent | fromJson) -}}
{{- if eq $intent.type "keycloak.cluster-realm" -}}
  {{- $_ := set $glyph "clusterKeycloakRef" (required "keycloak provider requires keycloakCrdName" $provider.keycloakCrdName) -}}
{{ include "keycloak.clusterRealm" (list $root $glyph) }}
{{- else -}}
  {{- $_ := set $glyph "keycloakRef" (required "keycloak provider requires keycloakCrdName" $provider.keycloakCrdName) -}}
{{ include "keycloak.realm" (list $root $glyph) }}
{{- end -}}
{{- end -}}

{{- define "covenant.meta.providerAccess" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $providers := index . 2 -}}{{- $spec := $intent.spec -}}
{{- $provider := required (printf "covenant: providerRef %q is missing" $intent.providerRef) (get $providers $intent.providerRef) -}}
{{- $selector := dict "name" $provider.name -}}
{{- $annotations := include "covenant.intentAnnotations" $intent | fromJson -}}
{{- if $spec.createServiceAccount -}}
{{ include "summon.serviceAccount" (list $root (dict "enabled" true "name" $spec.serviceAccount "namespace" $spec.namespace "labels" (dict "covenant.runik.io/owner" $intent.owner) "annotations" $annotations)) }}
{{- end -}}
{{ include "vault.policy" (list $root (dict "nameOverride" $spec.name "selector" $selector "paths" $spec.paths "labels" (dict "covenant.runik.io/owner" $intent.owner) "annotations" $annotations)) }}
{{ include "vault.role" (list $root (dict "nameOverride" $spec.name "selector" $selector "policies" (list $spec.name) "serviceAccount" $spec.serviceAccount "targetNamespace" $spec.namespace "labels" (dict "covenant.runik.io/owner" $intent.owner) "annotations" $annotations)) }}
{{- end -}}

{{- define "covenant.meta.identityProvider" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $providers := index . 2 -}}{{- $spec := deepCopy $intent.spec -}}
{{- with $spec.credentialContext -}}
  {{- $provider := required (printf "identity provider %s credential providerRef %q is missing" $spec.alias .providerRef) (get $providers .providerRef) -}}
  {{- $secretGlyph := dict "name" .secretName "namespace" $root.Release.Namespace "path" .path "random" false "keys" (list .secretKey) "format" "plain" "serviceAccount" .serviceAccount "customRole" .role "selector" (dict "name" $provider.name) "labels" (dict "covenant.runik.io/identity-provider" $spec.alias) "annotations" (include "covenant.intentAnnotations" (list $intent "1") | fromJson) -}}
{{ include "vault.secret" (list $root $secretGlyph) }}
  {{- $config := deepCopy (default dict $spec.config) -}}
  {{- $_ := set $config .configKey (printf "$%s:%s" .secretName .secretKey) -}}
  {{- $_ := set $spec "config" $config -}}
{{- end -}}
{{- $_ := set $spec "name" $spec.resourceName -}}
{{- $_ := set $spec "annotations" (include "covenant.intentAnnotations" $intent | fromJson) -}}
{{ include "keycloak.idp" (list $root $spec) }}
{{- end -}}

{{- define "covenant.meta.principal" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $spec := $intent.spec -}}
{{- $passwordSecret := dict -}}
{{- $passwordEnabled := false -}}
{{- if hasKey $spec.initialPassword "enabled" -}}{{- $passwordEnabled = $spec.initialPassword.enabled -}}{{- end -}}
{{- if $passwordEnabled -}}
  {{- $context := required (printf "principal %s requires credentialContext" $spec.principalRef) $spec.credentialContext -}}
  {{- $secretName := printf "principal-password-%s" $spec.resourceName | trunc 63 | trimSuffix "-" -}}
  {{- $glyph := dict "name" $secretName "namespace" $root.Release.Namespace "path" $context.path "random" true "randomKey" "password" "keys" (list) "format" "plain" "serviceAccount" $context.serviceAccount "customRole" $context.role "passPolicyName" (default "simple-password-policy" $spec.initialPassword.passwordPolicy) "labels" (dict "covenant.runik.io/principal" $spec.principalRef) "annotations" (include "covenant.intentAnnotations" (list $intent "2") | fromJson) -}}
{{ include "vault.secret" (list $root $glyph) }}
  {{- $temporary := false -}}{{- if hasKey $spec.initialPassword "temporary" -}}{{- $temporary = $spec.initialPassword.temporary -}}{{- end -}}
  {{- $passwordSecret = dict "name" $secretName "key" "password" "temporary" $temporary -}}
{{- end -}}
{{- $profile := default dict $spec.profile -}}
{{- $annotations := include "covenant.intentAnnotations" $intent | fromJson -}}
{{- $_ := set $annotations "covenant.runik.io/principal-ref" $spec.principalRef -}}
{{- $glyph := dict "name" $spec.resourceName "realmRef" $spec.realmRef "realmRefKind" $spec.realmRefKind "username" $spec.username "email" $spec.email "firstName" (default $spec.name $profile.firstName) "enabled" $spec.enabled "emailVerified" $spec.emailVerified "groups" (default list $spec.groups) "realmRoles" (default list $spec.realmRoles) "clientRoles" (default list $spec.clientRoles) "requiredUserActions" (default list $spec.requiredActions) "annotations" $annotations -}}
{{- if or $profile.lastName $spec.lastName -}}{{- $_ := set $glyph "lastName" (default $spec.lastName $profile.lastName) -}}{{- end -}}
{{- if $passwordEnabled -}}{{- $_ := set $glyph "passwordSecret" $passwordSecret -}}{{- end -}}
{{ include "keycloak.user" (list $root $glyph) }}
{{- end -}}

{{- define "covenant.meta.oidcClient" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $spec := $intent.spec -}}
{{- $public := false -}}{{- if hasKey $spec "public" -}}{{- $public = $spec.public -}}{{- end -}}
{{- $secretName := "" -}}
{{- if not $public -}}
  {{- $credentials := required (printf "confidential client %s requires credentials" $spec.clientId) $spec.credentials -}}
  {{- $context := required (printf "confidential client %s requires credentialContext" $spec.clientId) $spec.credentialContext -}}
  {{- $secretName = printf "client-credentials-%s" $spec.resourceName | trunc 63 | trimSuffix "-" -}}
  {{- $secretPath := printf "%s%s" $context.path $secretName -}}
  {{- $producer := dict "name" $secretName "namespace" $root.Release.Namespace "path" $context.path "random" true "randomKey" "client_secret" "keys" (list) "staticData" (dict "client_id" $spec.clientId) "format" "plain" "serviceAccount" $context.serviceAccount "customRole" $context.role "passPolicyName" (default "simple-password-policy" $credentials.passwordPolicy) "labels" (dict "covenant.runik.io/application" $spec.applicationKey) "annotations" (include "covenant.intentAnnotations" (list $intent "1") | fromJson) -}}
{{ include "vault.secret" (list $root $producer) }}
  {{- range $sink := default list $credentials.sinks -}}
    {{- $sinkSecret := required (printf "credential sink %s requires secret" $sink.name) $sink.secret -}}
    {{- $sinkKeys := list "client_secret" -}}
    {{- $includeClientID := true -}}
    {{- if and (hasKey $sinkSecret "includeStandardKeys") (not $sinkSecret.includeStandardKeys) -}}
      {{- $sinkKeys = list -}}
      {{- $includeClientID = false -}}
    {{- else if hasKey $sinkSecret "keys" -}}
      {{- $includeClientID = has "client_id" $sinkSecret.keys -}}
      {{- $sinkKeys = without $sinkSecret.keys "client_id" -}}
    {{- end -}}
    {{- $sinkStaticData := deepCopy (default dict $sinkSecret.staticData) -}}
    {{- if $includeClientID -}}{{- $_ := set $sinkStaticData "client_id" $spec.clientId -}}{{- end -}}
    {{- $sinkAnnotations := mergeOverwrite (deepCopy (default dict $sinkSecret.annotations)) (include "covenant.intentAnnotations" (list $intent "1") | fromJson) -}}
    {{- $sinkGlyph := dict "name" (required (printf "credential sink %s secret.name is required" $sink.name) $sinkSecret.name) "namespace" $sink.namespace "path" $secretPath "random" false "keys" $sinkKeys "staticData" $sinkStaticData "templateData" (default dict $sinkSecret.templateData) "format" (default "plain" $sinkSecret.format) "secretType" (default "Opaque" $sinkSecret.type) "serviceAccount" $sink.serviceAccount "customRole" (default (printf "covenant-%s-%s" $spec.resourceName $sink.name | trunc 63 | trimSuffix "-") $sink.role) "labels" (mergeOverwrite (dict "covenant.runik.io/application" $spec.applicationKey) (deepCopy (default dict $sinkSecret.labels))) "annotations" $sinkAnnotations -}}
{{ include "vault.secret" (list $root $sinkGlyph) }}
  {{- end -}}
{{- end -}}
{{- $directAccess := true -}}{{- if hasKey $spec "directAccess" -}}{{- $directAccess = $spec.directAccess -}}{{- end -}}
{{- $standardFlow := true -}}{{- if hasKey $spec "standardFlowEnabled" -}}{{- $standardFlow = $spec.standardFlowEnabled -}}{{- end -}}
{{- $glyph := dict "name" $spec.resourceName "clientId" $spec.clientId "realmRef" $spec.realmRef "realmRefKind" $spec.realmRefKind "webUrl" $spec.webUrl "protocol" "openid-connect" "public" $public "directAccess" $directAccess "stdFlow" $standardFlow "redirectUris" (default list $spec.redirectUris) "webOrigins" (default list $spec.webOrigins) "defaultClientScopes" (default list $spec.defaultClientScopes) "optionalClientScopes" (default list $spec.optionalClientScopes) "clientRoles" (default list $spec.clientRoles) "attributes" (default dict $spec.attributes) "rawAttributes" (default dict $spec.rawAttributes) "annotations" (include "covenant.intentAnnotations" $intent | fromJson) -}}
{{- if $secretName -}}{{- $_ := set $glyph "secret" $secretName -}}{{- end -}}
{{ include "keycloak.client" (list $root $glyph) }}
{{- end -}}

{{- define "covenant.meta.serviceAccountClient" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $providers := index . 2 -}}{{- $spec := deepCopy $intent.spec -}}
{{- $_ := set $spec "public" false -}}{{- $_ := set $spec "standardFlowEnabled" false -}}{{- $_ := set $spec "directAccess" false -}}
{{- $_ := set $spec "serviceAccount" (dict "enabled" true "clientRoles" (default list $spec.serviceAccountRoles)) -}}
{{- $_ := set $intent "spec" $spec -}}
{{ include "covenant.meta.oidcClient" (list $root $intent $providers) }}
{{- end -}}

{{- define "covenant.meta.samlClient" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}{{- $providers := index . 2 -}}{{- $spec := $intent.spec -}}
{{- with $spec.certificate -}}
  {{- $providerRef := required (printf "SAML client %s certificate.providerRef is required" $spec.clientId) .providerRef -}}
  {{- $provider := required (printf "SAML certificate providerRef %q is missing" $providerRef) (get $providers $providerRef) -}}
  {{- $certificateAnnotations := include "covenant.intentAnnotations" (list $intent "1") | fromJson -}}
  {{- $_ := set $certificateAnnotations "covenant.runik.io/saml-client" $spec.resourceName -}}
  {{- $certificate := dict "name" .resourceName "resourceName" .resourceName "namespace" .namespace "commonName" .commonName "dnsNames" .dnsNames "secretName" .secretName "issuerRef" (dict "name" $provider.name "kind" (default "ClusterIssuer" $provider.kind) "group" (default "cert-manager.io" $provider.group)) "usages" (default (list "digital signature") .usages) "privateKey" (default dict .privateKey) "labels" (dict "covenant.runik.io/application" $spec.applicationKey) "annotations" $certificateAnnotations -}}
  {{- with .duration -}}{{- $_ := set $certificate "duration" . -}}{{- end -}}
  {{- with .renewBefore -}}{{- $_ := set $certificate "renewBefore" . -}}{{- end -}}
  {{- with .subject -}}{{- $_ := set $certificate "subject" . -}}{{- end -}}
  {{- with .secretTemplate -}}{{- $_ := set $certificate "secretTemplate" . -}}{{- end -}}
{{ printf "\n" }}{{ include "cert-manager.clientCertificate" (list $root $certificate) }}
{{- end -}}
{{- $clientAnnotations := include "covenant.intentAnnotations" $intent | fromJson -}}
{{- with $spec.certificate -}}{{- $_ := set $clientAnnotations "covenant.runik.io/certificate-secret" (printf "%s/%s" .namespace .secretName) -}}{{- end -}}
{{- $glyph := dict "name" $spec.resourceName "clientId" $spec.clientId "realmRef" $spec.realmRef "realmRefKind" $spec.realmRefKind "webUrl" $spec.webUrl "protocol" "saml" "public" true "directAccess" false "stdFlow" true "redirectUris" (default list $spec.redirectUris) "rawAttributes" (default dict $spec.attributes) "annotations" $clientAnnotations -}}
{{ include "keycloak.client" (list $root $glyph) }}
{{- end -}}

{{- define "covenant.meta.report" -}}
{{- $root := index . 0 -}}{{- $intent := index . 1 -}}
{{- $name := include "covenant.physical" (list ($intent.id | replace "." "-") "") -}}
{{ include "summon.configMap" (list $root (dict "name" $name "definition" (dict "contentType" "yaml" "content" $intent.spec "labels" (dict "covenant.runik.io/report" $intent.type) "annotations" (include "covenant.intentAnnotations" $intent | fromJson)))) }}
{{- end -}}
