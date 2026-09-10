{{/* SPDX-License-Identifier: AGPL-3.0-only */}}

{{- define "covenant.adapters" -}}
{{- dict
  "keycloak.cluster-realm" "covenant.meta.realm"
  "keycloak.realm" "covenant.meta.realm"
  "keycloak.realm-role" "keycloak.realmRole"
  "keycloak.client-scope" "keycloak.clientScope"
  "keycloak.identity-provider" "covenant.meta.identityProvider"
  "keycloak.authentication-flow" "keycloak.flow"
  "keycloak.group" "keycloak.group"
  "keycloak.principal" "covenant.meta.principal"
  "keycloak.oidc-client" "covenant.meta.oidcClient"
  "keycloak.service-account-client" "covenant.meta.serviceAccountClient"
  "keycloak.saml-client" "covenant.meta.samlClient"
  "vault.provider-access" "covenant.meta.providerAccess"
  "covenant.authorization-report" "covenant.meta.report"
  "covenant.compile-report" "covenant.meta.report"
  | toJson -}}
{{- end -}}

{{- define "covenant.renderIntent" -}}
{{- $root := index . 0 -}}
{{- $intent := index . 1 -}}
{{- $providers := index . 2 -}}
{{- $adapters := include "covenant.adapters" $root | fromJson -}}
{{- $adapter := required (printf "covenant: no adapter registered for intent type %q" $intent.type) (get $adapters $intent.type) -}}
{{- if hasPrefix "covenant.meta." $adapter -}}
{{ include $adapter (list $root $intent $providers) }}
{{- else -}}
  {{- $glyph := deepCopy $intent.spec -}}
  {{- $_ := set $glyph "name" $intent.spec.resourceName -}}
  {{- $_ := set $glyph "annotations" (include "covenant.intentAnnotations" $intent | fromJson) -}}
{{ include $adapter (list $root $glyph) }}
{{- end -}}
{{- end -}}
