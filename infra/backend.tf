terraform {
  backend "s3" {
    bucket       = "eks-infra-tfstate-610331149376-us-east-2" # created by bootstrap/
    key          = "eks-sandbox/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true # S3-native locking, no DynamoDB table
  }
}
