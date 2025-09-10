# set quiet # Recipes are silent by default
set export # Just variables are exported to environment variables

rock_name := `echo ${PWD##*/} | sed 's/-rock//'`
latest_version := `find . -maxdepth 1 -type d | sort -V | tail -n1 | sed 's@./@@'`

[private]
default:
  just --list

# Push an OCI image to a local registry
[private]
push-to-registry version:
  echo "Pushing $rock_name $version to local registry"
  rockcraft.skopeo --insecure-policy copy --dest-tls-verify=false \
    "oci-archive:${version}/${rock_name}_${version}_amd64.rock" \
    "docker://localhost:32000/${rock_name}-dev:${version}"

# Pack a rock of a specific version
pack version:
  cd "$version" && rockcraft pack

# `rockcraft clean` for a specific version
clean version:
  cd "$version" && rockcraft clean

# Run a rock and open a shell into it with `kgoss`
run version=latest_version: (push-to-registry version)
  kgoss edit -i localhost:32000/${rock_name}-dev:${version}


test version=latest_version: (push-to-registry version)
  # litmuschaos-authserver needs a MongoDB database to work. deploy one
  docker run -d -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD=password -p 27017:27017 mongo:7
  docker run -d --network host -p 3000:3000 --name litmuschaos-server \
      -e DB_USER=root- \
      -e VERSION=ci \
      -e DB_PASSWORD=password \
      -e REST_PORT=3000 \
      -e GRPC_PORT=3030 \
      -e DB_SERVER=mongodb://localhost:27017 \
      -e ADMIN_USERNAME=admin \
      -e ADMIN_PASSWORD=password \
      -e INFRA_DEPLOYMENTS='["app=chaos-exporter"]' \
      -e SUBSCRIBER_IMAGE="litmuschaos/litmusportal-subscriber:ci" \
      -e EVENT_TRACKER_IMAGE="litmuschaos/litmusportal-event-tracker:ci" \
      -e ARGO_WORKFLOW_CONTROLLER_IMAGE="litmuschaos/workflow-controller:v3.3.1" \
      -e ARGO_WORKFLOW_EXECUTOR_IMAGE="litmuschaos/argoexec:v3.3.1" \
      -e LITMUS_CHAOS_OPERATOR_IMAGE="litmuschaos/chaos-operator:ci" \
      -e LITMUS_CHAOS_RUNNER_IMAGE="litmuschaos/chaos-runner:ci" \
      -e LITMUS_CHAOS_EXPORTER_IMAGE="litmuschaos/chaos-exporter:ci" \
      -e CONTAINER_RUNTIME_EXECUTOR="k8sapi" \
      -e WORKFLOW_HELPER_IMAGE_VERSION="ci" \
      -e INFRA_COMPATIBLE_VERSIONS="ci" \
      -e DEFAULT_HUB_BRANCH_NAME="master" \
      "localhost:32000/litmuschaos-server-dev:$version"
  docker rm -f litmuschaos-server