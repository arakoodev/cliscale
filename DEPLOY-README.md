GCP GKE Deployment Guide

This document explains how to provision infrastructure using Terraform and deploy the Cliscale application on Google Kubernetes Engine (GKE) with Skaffold.

1. Authenticate to Google Cloud

Before provisioning or deploying, authenticate with your GCP account and set your working project.

# Authenticate to your Google Cloud account
  gcloud auth application-default login

# Set the target project
  gcloud config set project <PROJECT_ID>


Confirm the active project:

  gcloud config get-value project

2. Create GCS Bucket for Terraform State
Terraform stores its remote state file in a Google Cloud Storage (GCS) bucket.
You must create the bucket first before initializing Terraform.

Example configuration in providers.tf:

  terraform {
    backend "gcs" {
      bucket  = "cliscale-tf-state-bucket"
      prefix  = "cliscale"
    }
  }

Create the GCS bucket:
# Replace <PROJECT_ID> and region
  PROJECT_ID=<your_project_id>
  BUCKET_NAME=cliscale-tf-state-buck
  REGION=us-central1

  gcloud storage buckets create gs://$BUCKET_NAME \
    --project=$PROJECT_ID \
    --location=$REGION \
    --uniform-bucket-level-access

=> Verify:

  gcloud storage buckets list --project=$PROJECT_ID

3. Provision Infrastructure with Terraform
Terraform will automatically create the following GCP resources: GKE cluster, Cloud SQL (Postgresql), Service Account (controller & gateway), IAM workload Identity bindings, GKE namespace ws-cli, secrets (API_KEY, DATABASE_URL, JWT key), etc

Steps:
# Navigate to your Terraform project
  cd infras folder

# Initialize Terraform
  terraform init

# Apply Terraform configuration
  terraform apply -var-file="terraform.tfvars" --auto-approve


Wait until Terraform completes provisioning (~5–10 minutes).

4. Verify Infrastructure Resources
After Terraform completes, verify that all resources were successfully created:

# Check cluster credentials
  gcloud container clusters get-credentials ws-cli-cluster \
    --region us-central1 \
    --project cliscale

# Check Cloud SQL instance
  gcloud sql instances list --project=cliscale

# Verify Kubernetes namespace and secrets
  kubectl get ns
  kubectl get secret -n ws-cli


You should see the following namespace and secrets:

NAMESPACE   STATUS
ws-cli      Active

NAME                  TYPE     DATA
cliscale-api-key       Opaque   1
pg                    Opaque   1
jwt                   Opaque   2

5. Import Database Schema to Cloud SQL
After Terraform creates your Cloud SQL instance and database, import the initial schema file.

Upload your schema file to a GCS bucket
You can reuse the same bucket you made for Terraform state, or create a new one (e.g. cliscale-sql-imports):

# Create a bucket (if not already)
gsutil mb -l us-central1 gs://cliscale-sql-imports/

Then upload your SQL file:
cd cliscale repo folder
gsutil cp ./db/schema.sql gs://cliscale-sql-imports/schema.sql

Grant Storage Object permissions
BUCKET="cliscale-sql-imports"
export SA_EMAIL=$(gcloud sql instances describe ws-cli-pg \
  --project=cliscale \
  --format="value(serviceAccountEmailAddress)")

gsutil iam ch serviceAccount:$SA_EMAIL:roles/storage.objectViewer gs://$BUCKET
gsutil iam ch serviceAccount:$SA_EMAIL:roles/storage.legacyBucketReader gs://$BUCKET

Now retry your import command:

gcloud sql import sql ws-cli-pg gs://cliscale-sql-imports/schema.sql \
  --database=wscli \
  --project=cliscale \
  --quiet

  
5. Deploy Application via Skaffold
Once the infrastructure is ready, build and deploy the Cliscale application using Skaffold.

Build & Deploy Steps
# Navigate to your application root folder
  cd cliscale root repository

# Build Docker images and push to Artifact Registry
  skaffold build --default-repo us-central1-docker.pkg.dev/cliscale/apps -p dev

# Render manifests for review (optional)
  skaffold render --default-repo us-central1-docker.pkg.dev/cliscale/apps -p dev

# Deploy the application to the GKE cluster
  skaffold run --default-repo us-central1-docker.pkg.dev/cliscale/apps -p dev

6. Verify Deployment on GKE
Use kubectl to confirm that pods, deployments, and services are running correctly in the ws-cli namespace.

  kubectl get pod -n ws-cli
  kubectl get deployment -n ws-cli
  kubectl get ingress -n ws-cli
  kubectl get svc -n ws-cli

Check logs for debugging:

  kubectl logs deployment/<DEPLOYMENT_NAME> -n ws-cli --tail=100
  kubectl logs pod/<POD_NAME> -n ws-cli --tail=100

noted: should wait to 5-10 mins, ensure GKE ingress done to created.

7. Test Application
Once the ingress load balancer is ready, obtain its public IP and API key.

# Get Load Balancer IP
export LB_IP=$(kubectl get ingress cliscale-ingress -n ws-cli -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"

# Get generated API key
export API_KEY=$(kubectl get secret cliscale-api-key -n ws-cli -o jsonpath='{.data.API_KEY}' | base64 -d)
echo "API Key: $API_KEY"

Run API test:

curl -X POST "http://$LB_IP/api/sessions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "code_url": "https://github.com/arakoodev/cliscale/tree/main/sample-cli",
    "command": "node index.js run",
    "prompt": "Hello!",
    "install_cmd": "npm install"
  }'

=> if successful, you’ll receive a JSON response containing session details.

8. Clean Up Resources
When testing is complete, you can safely destroy all resources:

  terraform destroy -var-file="terraform.tfvars" --auto-approve

9. Notes
Make sure your local or Cloud Shell environment has:
- gcloud SDK
- kubectl
- terraform >= 1.7.x
- skaffold >= 2.x
