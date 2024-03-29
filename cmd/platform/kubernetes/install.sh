#!/bin/bash

# which env to deploy to. does not yet switch k8s context
ENV=$1
# default to size for platform
DB_SIZE=100Gi

arrayGet() {
    local array=$1 index=$2
    local i="${array}_$index"
    printf '%s' "${!i}"
}

# Run this script to install the platform on a kubernetes cluster. 

# NOTE: This script will not set the cloudflare or slack tokens in the secret. Hence, the 
# clients (http, api, proxy, bot) will have a status of "CreateContainerConfigError" until these
# secrets are manually added.

# expect an env to be specified
if [ "$ENV" == "" ]; then
  echo "Must specify env e.g ./install.sh {dev|staging|platform}"
  exit 1
fi

if [ "$ENV" != "dev" ]; then
  envvars=$(grep -hr "^# REQUIRED MICRO ENV " resource | sed 's/# REQUIRED MICRO ENV //')
  echo "Required env vars"
  echo "${envvars}"
  echo "Have you specified all the required secrets as env vars? [y/N]"
  read -r ans
  if [ "$ans" != "y" ]; then
    exit 1
  fi
fi

## Set DB to smaller size for staging
if [ "$ENV" != "platform" ]; then
  DB_SIZE=25Gi
fi

# Generate keys for JWT auth.
which ssh-keygen > /dev/null
if [ $? -eq 1 ]; then
  echo "Missing ssh-keygen command"
  exit 1
fi

which openssl > /dev/null
if [ $? -eq 1 ]; then
  echo "Missing openssl command"
fi

# generate new PEM key
ssh-keygen -t rsa -b 2048 -m PEM -f /tmp/jwt -q -N "";
# Don't add passphrase
openssl rsa -in /tmp/jwt -pubout -outform PEM -out /tmp/jwt.pub
# Base64 encode
base64 /tmp/jwt > /tmp/jwt-base64
base64 /tmp/jwt.pub > /tmp/jwt-base64.pub


# Create the k8s secret
kubectl create secret generic micro-secrets \
  --namespace=default \
  --from-file=auth_public_key=/tmp/jwt-base64.pub \
  --from-file=auth_private_key=/tmp/jwt-base64 \
  --from-literal=cloudflare=$CF_API_KEY

###create micro_user key
openssl genrsa -out rsa_private_key.pem 1024
openssl rsa -in rsa_private_key.pem  -pubout -out rsa_public_key.pem

###deploy k8s secret for micro_user key
kubectl create secret generic micro-user-secrets \
  --namespace=default \
  --from-file=micro_user_private_key=./rsa_private_key.pem \
  --from-file=micro_user_public_key=./rsa_public_key.pem

#Crate gitee private key
kubectl create secret generic gitee-ssh-private-key \
  --namespace=default \
  --from-file=id_rsa=/Users/wolfplus/.ssh/id_rsa
kubectl create configmap git-config --namespace=default --from-file=.gitconfig=/Users/wolfplus/.gitconfig
# Remove the files from tmp
rm /tmp/jwt /tmp/jwt.pub /tmp/jwt-base64 /tmp/jwt-base64.pub

# declare any args you want to pass to the install script here as resource_args_<dir name>
declare resource_args_cockroachdb="$DB_SIZE"

#svc=("cockroachdb", "etcd", "ingress", "mongodb", "nats", "prometheus")
## install the resources
#for d in ./resource/*/; do
#  pushd $d
#  MICRO_ENV=$ENV bash install.sh $(arrayGet resource_args $(basename $d))
#  popd
#done

# execute the yaml
kubectl apply -f service

# go back to the top level
cd ..;
