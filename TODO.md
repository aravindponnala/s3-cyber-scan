# Manual Updates Required

## 1. Update terraform.tfvars
Replace the placeholder ECR image with your actual AWS account ID:
```
scanner_image = "<YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/scanner-worker:latest"
```

## 2. Update security_groups.tf (line 89)
Replace the hardcoded IP with your current IP:
```bash
# Get your current IP:
curl -s https://checkip.amazonaws.com

# Then update line 89 in security_groups.tf:
cidr_blocks = ["YOUR_IP/32"]
```

## 3. Create ECR repository and push image
```bash
aws ecr create-repository --repository-name scanner-worker --region us-east-1
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
cd ../scanner-worker
docker build -t scanner-worker .
docker tag scanner-worker:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/scanner-worker:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/scanner-worker:latest
```

## 4. Create S3 bucket
```bash
aws s3 mb s3://aravind-scanner-test-bucket-123
```

## 5. Apply Terraform
```bash
terraform init
terraform plan
terraform apply
```
