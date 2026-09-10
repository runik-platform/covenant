{{/* SPDX-License-Identifier: AGPL-3.0-only */}}

{{- define "covenant.principalApplicationSet" -}}
{{- $root := index . 0 -}}
{{- $plan := index . 1 -}}
{{- if $plan.principalShards -}}
{{- $applicationSet := required "covenant: applicationSet is required when the IAM book contains principals" $root.Values.applicationSet -}}
{{- $source := required "covenant: applicationSet.source is required" $applicationSet.source -}}
{{- $repository := required "covenant: applicationSet.source.repository is required" $source.repository -}}
{{- $revision := required "covenant: applicationSet.source.revision is required" $source.revision -}}
{{- $path := default "" $source.path -}}
{{- $chart := default "" $source.chart -}}
{{- if eq (empty $path) (empty $chart) -}}
  {{- fail "covenant: applicationSet.source requires exactly one of path or chart" -}}
{{- end -}}
{{- $applicationNamespace := default "argocd" $applicationSet.applicationNamespace -}}
{{- $project := default (default $plan.book ($root.Values.spellbook).name) $applicationSet.project -}}
{{- $targetNamespace := default $root.Release.Namespace $root.Values.namespace -}}
{{- $destination := deepCopy (default dict $applicationSet.destination) -}}
{{- if not (hasKey $destination "namespace") -}}{{- $_ := set $destination "namespace" $targetNamespace -}}{{- end -}}
{{- if and (not (hasKey $destination "server")) (not (hasKey $destination "name")) -}}
  {{- $_ := set $destination "server" "https://kubernetes.default.svc" -}}
{{- end -}}
{{- $syncPolicy := deepCopy (default dict $applicationSet.syncPolicy) -}}
{{- if not (hasKey $syncPolicy "automated") -}}
  {{- $_ := set $syncPolicy "automated" (dict "prune" true "selfHeal" true) -}}
{{- end -}}
{{- if not (hasKey $syncPolicy "syncOptions") -}}
  {{- $_ := set $syncPolicy "syncOptions" (list "CreateNamespace=true" "PrunePropagationPolicy=foreground" "PruneLast=true") -}}
{{- end -}}
{{- $applicationSetName := printf "%s-principals" $root.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- printf "\n---\n" }}apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: {{ $applicationSetName }}
  namespace: {{ $applicationNamespace }}
  labels:
    app.kubernetes.io/name: covenant
    app.kubernetes.io/instance: {{ $root.Release.Name }}
    app.kubernetes.io/managed-by: covenant
    runik.io/component: covenant-principals
    covenant.runik.io/realm: {{ $plan.realm.realmName }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ default "5" $applicationSet.syncWave | quote }}
spec:
  goTemplate: true
  goTemplateOptions:
    - missingkey=error
  generators:
    - list:
        elements:
          {{- range $shard := $plan.principalShards }}
          {{- $intentCount := 0 }}
          {{- $manifests := "" }}
          {{- range $intent := $plan.intents }}
            {{- if eq $shard (default "" $intent.principalShard) }}
              {{- $intentCount = add1 $intentCount }}
              {{- $manifests = printf "%s\n%s" $manifests (include "covenant.renderIntent" (list $root $intent $plan.providers)) }}
            {{- end }}
          {{- end }}
          {{- if eq (int $intentCount) 0 }}{{- fail (printf "covenant: principal shard %q has no compiled intents" $shard) }}{{- end }}
          - shard: {{ $shard | quote }}
            intentCount: {{ $intentCount | quote }}
            manifests: {{ $manifests | trim | b64enc | quote }}
          {{- end }}
  syncPolicy:
    preserveResourcesOnDeletion: false
  template:
    metadata:
      name: '{{ $applicationSetName }}-{{`{{ .shard }}`}}'
      namespace: {{ $applicationNamespace }}
      finalizers:
        - resources-finalizer.argocd.argoproj.io
      labels:
        app.kubernetes.io/name: covenant
        app.kubernetes.io/instance: {{ $root.Release.Name }}
        app.kubernetes.io/managed-by: applicationset
        runik.io/component: covenant-principals
        covenant.runik.io/realm: {{ $plan.realm.realmName }}
        covenant.runik.io/principal-shard: '{{`{{ .shard }}`}}'
        covenant.runik.io/intent-count: '{{`{{ .intentCount }}`}}'
    spec:
      project: {{ $project }}
      source:
        repoURL: {{ $repository }}
        {{- if $path }}
        path: {{ $path }}
        {{- else }}
        chart: {{ $chart }}
        {{- end }}
        targetRevision: {{ $revision }}
        helm:
          valuesObject:
            _covenant:
              manifests: '{{`{{ .manifests }}`}}'
      destination:
        {{- toYaml $destination | nindent 8 }}
      syncPolicy:
        {{- toYaml $syncPolicy | nindent 8 }}
      {{- with $applicationSet.ignoreDifferences }}
      ignoreDifferences:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
{{- end -}}
