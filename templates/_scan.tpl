{{/* SPDX-License-Identifier: AGPL-3.0-only */}}

{{- define "covenant.scanNamed" -}}
{{- $root := index . 0 -}}
{{- $glob := index . 1 -}}
{{- $field := index . 2 -}}
{{- $result := dict -}}
{{- range $path, $_ := $root.Files.Glob $glob -}}
  {{- $document := $root.Files.Get $path | fromYaml -}}
  {{- if or (ne (len $document) 1) (not (hasKey $document $field)) -}}
    {{- fail (printf "covenant: %s must contain exactly one %s definition" $path $field) -}}
  {{- end -}}
  {{- $entry := deepCopy (required (printf "covenant: %s.%s is required" $path $field) (get $document $field)) -}}
  {{- $logical := include "covenant.logical" (required (printf "covenant: %s.key is required at %s" $field $path) $entry.key) -}}
  {{- if hasKey $result $logical -}}
    {{- fail (printf "covenant: duplicate %s %q at %s" $field $logical $path) -}}
  {{- end -}}
  {{- $_ := set $entry "key" $logical -}}
  {{- $_ := set $entry "resourceName" (include "covenant.physical" (list $logical (default "" $entry.resourceName))) -}}
  {{- $_ := set $entry "source" (dict "path" $path "entry" $logical) -}}
  {{- $_ := set $result $logical $entry -}}
{{- end -}}
{{- $result | toJson -}}
{{- end -}}

{{- define "covenant.scanPrincipals" -}}
{{- $root := index . 0 -}}
{{- $glob := index . 1 -}}
{{- $domain := index . 2 -}}
{{- $defaults := index . 3 -}}
{{- $result := dict -}}
{{- range $path, $_ := $root.Files.Glob $glob -}}
  {{- $document := $root.Files.Get $path | fromYaml -}}
  {{- if or (ne (len $document) 1) (not (hasKey $document "principal")) -}}
    {{- fail (printf "covenant: %s must contain exactly one principal definition" $path) -}}
  {{- end -}}
  {{- $source := dict "path" $path "entry" "principal" -}}
  {{- $principal := include "covenant.principal" (list (required (printf "covenant: principal is required at %s" $path) $document.principal) $domain $defaults $source) | fromJson -}}
  {{- $ref := $principal.principalRef -}}
  {{- if hasKey $result $ref -}}
    {{- fail (printf "covenant: duplicate derived principalRef %q at %s" $ref $path) -}}
  {{- end -}}
  {{- $_ := set $principal.source "entry" $ref -}}
  {{- $_ := set $result $ref $principal -}}
{{- end -}}
{{- $result | toJson -}}
{{- end -}}

{{- define "covenant.scanApplications" -}}
{{- $root := index . 0 -}}
{{- $sources := default list (index . 1) -}}
{{- $applications := dict -}}
{{- range $source := $sources -}}
  {{- $book := required "covenant: sources.applicationBooks[].name is required" $source.name -}}
  {{- $_ := include "covenant.logical" $book -}}
  {{- $indexPath := printf "bookrack/%s/index.yaml" $book -}}
  {{- if not ($root.Files.Glob $indexPath) -}}
    {{- fail (printf "covenant: application book index not found: %s" $indexPath) -}}
  {{- end -}}
  {{- $bookIndex := $root.Files.Get $indexPath | fromYaml -}}
  {{- range $chapter := required (printf "covenant: application book %s requires chapters" $book) $bookIndex.chapters -}}
    {{- $glob := printf "bookrack/%s/%s/*.yaml" $book $chapter -}}
    {{- range $path, $_ := $root.Files.Glob $glob -}}
      {{- $spell := $root.Files.Get $path | fromYaml -}}
      {{- with $spell.covenant -}}
        {{- if hasKey . "schemaVersion" -}}{{- fail (printf "covenant: %s must not declare schemaVersion; the chart version owns the contract" $path) -}}{{- end -}}
        {{- if hasKey . "application" -}}{{- fail (printf "covenant: %s must declare key and roles directly under covenant; application is not valid" $path) -}}{{- end -}}
        {{- $spellName := required (printf "covenant: application spell %s requires name" $path) $spell.name -}}
        {{- $clients := dict -}}
        {{- range $clientRealm, $client := default dict .clients -}}
          {{- $clientRealmRef := include "covenant.logical" $clientRealm -}}
          {{- $_ := set $clients $clientRealmRef (deepCopy $client) -}}
        {{- end -}}
        {{- $application := dict "roles" (deepCopy (default dict .roles)) "clients" $clients -}}
        {{- $key := include "covenant.logical" (default $spellName .key) -}}
        {{- if hasKey $applications $key -}}
          {{- fail (printf "covenant: duplicate application contract %q at %s" $key $path) -}}
        {{- end -}}
        {{- $_ := set $application "key" $key -}}
        {{- $_ := set $application "namespace" (default $spellName $spell.namespace) -}}
        {{- $_ := set $application "source" (dict "book" $book "chapter" $chapter "path" $path "entry" $key) -}}
        {{- $_ := set $applications $key $application -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $applications | toJson -}}
{{- end -}}
