variable "region" {
  description = "AWS region the cluster lives in."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Used as a prefix for many other names and tags."
  type        = string
  default     = "sample-eks"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes minor version."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count for the managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count for the managed node group."
  type        = number
  default     = 4
}

variable "allowed_account_ids" {
  description = "AWS account IDs the aws provider is allowed to operate against. Belt-and-braces guard against pointing this at the wrong account."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Default tags applied to every resource the aws provider creates."
  type        = map(string)
  default = {
    Project   = "sample-eks-microservice"
    ManagedBy = "terraform"
    Env       = "dev"
  }
}
