data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# ---------------------------------------------------------------------- vpc
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 3, i + 2)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags the AWS Load Balancer Controller looks for when picking which subnets
  # to wire up. cluster/<name>=shared on every subnet, plus role tags so it
  # only puts internet-facing ALBs in public subnets and internal NLBs/ALBs in
  # private subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ---------------------------------------------------------------------- eks
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # Whoever runs `terraform apply` becomes a cluster-admin. Without this we'd
  # have to add an aws-auth entry by hand the first time.
  enable_cluster_creator_admin_permissions = true

  enabled_log_types = ["api", "audit", "authenticator"]

  encryption_config = {
    resources = ["secrets"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Versions are left unset on purpose so EKS picks the default that ships
  # with this Kubernetes version. Pinning them here is a portability trap.
  #
  # before_compute = true tells the module to install the addon before the
  # node group is created. vpc-cni is required for kubelet to register the
  # node as Ready (no CNI → NetworkPluginNotReady → node group hangs in
  # CREATING until its 35m timeout). kube-proxy is in the same boat for any
  # workload that talks to a Service. coredns can install after the nodes are
  # up.
  #
  # eks-pod-identity-agent is intentionally NOT installed — we use IRSA (see
  # the ALB controller role below). Adding the agent here would cause its
  # mutating webhook to inject Pod Identity env vars on any pod with a
  # registered association, which interferes with the IRSA credential path.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    coredns = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      subnet_ids = module.vpc.private_subnets
    }
  }
}

# ----------------------------------------------------------- alb controller
# IRSA. Trust is scoped to a specific (namespace, sa_name) so only the ALB
# controller pod can assume this role. The IAM policy is vendored from the
# upstream chart's matching version tag — refresh
# infra/policies/alb-controller.json when bumping the chart `--version` in
# the helm install. Source URL:
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
locals {
  oidc_provider_host = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller"
  policy = file("${path.module}/../../policies/alb-controller.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

