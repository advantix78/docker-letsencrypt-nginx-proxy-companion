#!/usr/bin/env bash

## Test for private keys types

if [[ -z $TRAVIS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for key in "${!key_types[@]}"; do
    docker rm --force "${key}" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

declare -A key_types
key_types=( \
  ['1024']='RSA Public-Key: (1024 bit)' \
  ['2048']='RSA Public-Key: (2048 bit)' \
  ['4096']='RSA Public-Key: (4096 bit)' \
  ['ec256']='secp256r1' \
  ['ec384']='secp384r1' \
  ['ec512']='secp512r1' \
)

for key in "${!key_types[@]}"; do

  # Run an Nginx container with the wanted key type.
  if ! docker run --rm -d \
    --name "${key}" \
    -e "VIRTUAL_HOST=${domains[0]}" \
    -e "LETSENCRYPT_HOST=${domains[0]}" \
    -e "LETSENCRYPT_PRIVATE_KEY=${key}" \
    --network boulder_bluenet \
    nginx:alpine > /dev/null;
  then
    echo "Could not start test web server for ${key}"
  elif [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "Started test web server for ${key}"
  fi

  # Grep the expected string from the public key in text form.
  if wait_for_symlink "${domains[0]}" "$le_container_name"; then
    public_key=$(docker exec "$le_container_name" openssl pkey -in "/etc/nginx/certs/${domains[0]}.key" -noout -text_pub)
    if ! grep "${key_types[$key]}" <<< "$public_key"; then
      echo "Keys for test $key were not of the correct type, expected ${key_types[$key]} and got the following:"
      echo "$public_key"
    fi
  fi

  docker stop "${key}" &> /dev/null
  docker exec "$le_container_name" rm -rf /etc/nginx/certs/le?.wtf*
  docker exec "$le_container_name" rm -rf /etc/acme.sh/default/le?.wtf*

done
