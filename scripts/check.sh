#!/usr/bin/env bash
# Checks of the onicost-agent chart, run by the ci and release workflows: lint, rendering and schema refusals.
set -euo pipefail

chart=charts/onicost-agent
endpoint=(--set endpoint=https://ingest.example.test)

# refuses WANT ARGS...: helm template with ARGS must fail with an error that contains WANT.
refuses() {
  local want=$1 err
  shift
  if err=$(helm template onicost-agent "$chart" "$@" 2>&1 > /dev/null); then
    echo "accepted: $*" >&2
    exit 1
  fi
  if [[ $err != *"$want"* ]]; then
    echo "refused without '$want': $*: $err" >&2
    exit 1
  fi
}

helm lint "$chart" --strict
helm template onicost-agent "$chart" "${endpoint[@]}" > /dev/null

# Every optional value set: each optional branch is rendered, and podLabels never change the selector labels.
helm lint "$chart" --strict -f scripts/values-all.yaml
manifests=$(helm template onicost-agent "$chart" -f scripts/values-all.yaml)
if grep -q 'app.kubernetes.io/name: other' <<< "$manifests"; then
  echo 'podLabels override the selector labels' >&2
  exit 1
fi

# podLabels may be null.
helm template onicost-agent "$chart" "${endpoint[@]}" --set podLabels=null > /dev/null
helm template onicost-agent "$chart" "${endpoint[@]}" --set-json podLabels=null > /dev/null

# The notes name the image tag that is deployed.
notes=$(helm install onicost-agent "$chart" --dry-run=client "${endpoint[@]}" --set image.tag=9.9.9)
if [[ $notes != *'Onicost agent 9.9.9 is installed'* ]]; then
  echo 'NOTES.txt does not name the deployed image tag' >&2
  exit 1
fi

refuses 'endpoint is required'
refuses 'endpoint is required' --set endpoint=
refuses schema --set endpoint=ingest.example.test
refuses schema "${endpoint[@]}" --set proxy.url=socks5://proxy:1080
refuses schema "${endpoint[@]}" --set unknown=1
refuses schema "${endpoint[@]}" --set token.value=x
refuses schema "${endpoint[@]}" --set token.existingSecrets=x
refuses schema "${endpoint[@]}" --set kubelet.insecureSkipVerfy=true
refuses schema "${endpoint[@]}" --set 'exclude.namespace={a}'
refuses schema "${endpoint[@]}" --set proxy.uri=x
refuses schema "${endpoint[@]}" --set image.tags=x
refuses schema "${endpoint[@]}" --set scrapeInterval=45s
refuses schema "${endpoint[@]}" --set image.pullPolicy=Sometimes
refuses schema "${endpoint[@]}" --set token.existingSecret=
refuses schema "${endpoint[@]}" --set token.secretKey=
refuses schema "${endpoint[@]}" --set image.repository=
