provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # refuse to run against any other account

  default_tags {
    tags = {
      Project     = "eks-infra"
      Environment = "sandbox"
      ManagedBy   = "terraform"
    }
  }
}
