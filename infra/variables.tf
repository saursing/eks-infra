variable "account_id" {
  type        = string
  description = "AWS account the cluster lives in"
  default     = "610331149376"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-2"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (also used for the VPC name)"
  default     = "devsecops-demo"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version. Upgrade one minor version at a time."
  default     = "1.36"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the cluster VPC"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR, e.g. 10.0.0.0/16."
  }
}

variable "node_instance_type" {
  type        = string
  description = "Instance type for the managed node group"
  default     = "t3.medium"
}

variable "node_count" {
  type = object({
    min     = number
    max     = number
    desired = number
  })
  description = "Managed node group size"
  default = {
    min     = 2
    max     = 3
    desired = 2
  }
}

variable "endpoint_public_access_cidrs" {
  type        = list(string)
  description = "Who may reach the EKS API from the internet. Use your own IP as x.x.x.x/32."

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Use real CIDRs, and not 0.0.0.0/0 (that opens the Kubernetes API to the whole internet)."
  }
}

variable "admin_principal_arns" {
  type        = list(string)
  description = "IAM users/roles that get cluster-admin via EKS access entries (e.g. your own IAM user or SSO role)"
  default     = []
}
