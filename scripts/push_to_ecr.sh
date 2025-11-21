#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID="725889403313"
REGION="us-east-1"
REPO_NAME="scanner-worker"

cd ../scanner-worker

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker build -t $REPO_NAME .
docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

echo "Image pushed successfully!"
