Terraform Infrastructure Deployment

This repository contains Terraform configurations to provision and manage infrastructure.
We use a variables.tfvars file to keep environment-specific values separate from the core codebase.

📁 Project Structure
.
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
└── README.md


main.tf: Main Terraform configuration

variables.tf: Definition of input variables

*.tfvars: Can environment-specific values (e.g., dev, uat, prod)


⚙️ Usage
1. Initialize Terraform

Before applying any configuration, initialize the working directory:

terraform init

2. Validate the Configuration

Check syntax and structure:

terraform validate

3. Plan with Variables File

Run a plan with your .tfvars file to preview infrastructure changes:

terraform plan -var-file="terraform.tfvars"


You can replace dev.tfvars with prod.tfvars or any other environment file.

4. Apply the Changes

To create or update resources:

terraform apply -var-file="terraform.tfvars"


Or auto-approve:

terraform apply -var-file="terraform.tfvars" -auto-approve

🧼 Cleanup (Destroy Infrastructure)

To remove all resources managed by Terraform:

terraform destroy -var-file="terraform.tfvars"