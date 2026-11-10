locals {
  # Fixed list (not a data source) so the subnets never shift if AWS adds a zone. 2 AZs keeps the sandbox cheap.
  azs = ["${var.region}a", "${var.region}b"]
}

# ---------- Network ----------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.cluster_name
  cidr = var.vpc_cidr
  azs  = local.azs

  # 10.0.0.0/20, 10.0.16.0/20 for nodes and pods (VPC CNI gives pods VPC IPs, so keep these big)
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  # 10.0.48.0/24, 10.0.49.0/24 for load balancers and the NAT gateway
  public_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  enable_nat_gateway      = true
  single_nat_gateway      = true # one NAT for the sandbox; one per AZ for prod
  map_public_ip_on_launch = false

  # Default SG with no rules (CKV2_AWS_12)
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # VPC flow logs to CloudWatch (CKV2_AWS_11)
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 30

  # Lets the AWS Load Balancer Controller find the right subnets later
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ---------- EKS ----------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # API endpoint: private for nodes, public only for your IP
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Control plane logs to CloudWatch
  enabled_log_types = ["api", "audit", "authenticator"]

  # Who can use kubectl: the pipeline's apply role (creator) + the people you list
  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for arn in var.admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # No IRSA: it needs an IAM OIDC provider, which this org's SCP blocks.
  # Pods get AWS access through EKS Pod Identity instead (eks-pod-identity-agent add-on below).
  enable_irsa = false

  # Core add-ons. Swap vpc-cni/kube-proxy for Cilium later if you want.
  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes live in private subnets only

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_count.min
      max_size     = var.node_count.max
      desired_size = var.node_count.desired
    }
  }
}
