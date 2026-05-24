output "region" {
  description = "AWS region the cluster is in."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA bundle for the cluster API server."
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider. Trust principal for IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Issuer URL of the cluster's IAM OIDC provider."
  value       = module.eks.cluster_oidc_issuer_url
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller. The deploy pipeline annotates the controller's ServiceAccount with this via eks.amazonaws.com/role-arn."
  value       = aws_iam_role.alb_controller.arn
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where worker nodes live)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (where internet-facing ALBs live)."
  value       = module.vpc.public_subnets
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
