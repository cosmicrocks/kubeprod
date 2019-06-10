#!/usr/bin/env bash
set -e
set -o pipefail

# Make sure to start with a clean 'manifests' dir
rm -rf manifests/
mkdir -p manifests/aws
mkdir -p manifests/digitalocean

docker run --rm -v $(pwd):$(pwd) --workdir $(pwd) quay.io/coreos/jsonnet-ci jsonnet -J vendor -m manifests/aws ./platforms/aws.jsonnet | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml; rm -f {}' -- {}
docker run --rm -v $(pwd):$(pwd) --workdir $(pwd) quay.io/coreos/jsonnet-ci jsonnet -J vendor -m manifests/digitalocean ./platforms/digitalocean.jsonnet | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml; rm -f {}' -- {}