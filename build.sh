#!/bin/bash

export VERSION=`cat version`

# Set up environment
docker version
docker buildx ls
docker buildx create --name phpbuilder
docker buildx use phpbuilder

echo "Building: PHP Container"
docker buildx build --platform linux/amd64,linux/arm64 -t "flosabre/nginx-php-fpm:${VERSION}" -t flosabre/nginx-php-fpm:latest --push .

