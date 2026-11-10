variable "account_id" {
  type        = string
  description = "AWS account this bootstrap is allowed to run in"
  default     = "610331149376"
}

variable "region" {
  type        = string
  description = "Region for the state bucket"
  default     = "us-east-2"
}

variable "github_owner" {
  type        = string
  description = "GitHub username (or org) that owns the infra repo"
}

variable "github_repo" {
  type        = string
  description = "Name of the infra repo"
  default     = "eks-infra"
}
