# infra

Terraform that provisions the VPC and EKS cluster the microservice runs on.
Outputs here are consumed by `deploy/`. Only one environment ships
(`envs/dev/`); promotion to staging/prod is out of scope.

The architecture diagram and per-resource design notes live in the root
`README.md`. This file covers what to run and what each output is for.

## What gets created

- A `10.0.0.0/16` VPC across 3 AZs, three public `/20` subnets and three
  private `/19` subnets, one NAT gateway per AZ.
- EKS cluster on Kubernetes 1.34, public + private API endpoint, KMS secret
  encryption, CloudWatch logs for `api`/`audit`/`authenticator`.
- Managed node group on AL2023 (`t3.medium`, 2/2/4) in private subnets only.
- The `vpc-cni`, `kube-proxy`, `coredns` add-ons. EBS CSI is omitted (the
  demo never asks for a PV) and `eks-pod-identity-agent` is omitted on
  purpose — the ALB controller uses **IRSA**, and adding the agent injects
  Pod Identity env vars that override the IRSA credential path.
- An IAM role + IAM policy for the AWS Load Balancer Controller. Trust is
  scoped to `system:serviceaccount:kube-system:aws-load-balancer-controller`
  via the cluster's OIDC provider. The IAM policy is vendored from the
  upstream chart's matching tag (`infra/policies/alb-controller.json`,
  refresh when bumping the chart `--version`).

## Run

```bash
# 0. Authenticate. The aws provider also accepts allowed_account_ids — set
#    it in terraform.tfvars to harden against pointing at the wrong account.
aws sts get-caller-identity

# 1. State bucket. S3 names are global, so embed the account id.
export TFSTATE_BUCKET=sample-eks-tfstate-$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1
make infra-bootstrap                       # idempotent

# 2. Init / validate / plan / apply.
make infra-init
make infra-validate                        # fmt + validate (after init)
make infra-plan
make infra-apply                           # ~15 min on a clean account

# 3. Wire kubectl and verify.
$(terraform -chdir=infra/envs/dev output -raw kubeconfig_command)
make infra-verify

# 4. Idempotency probe — must say "No changes".
make infra-plan
```

`make infra-destroy` tears the cluster and VPC back down. The S3 state bucket
is left behind on purpose; drop it manually with `aws s3 rb s3://$TFSTATE_BUCKET --force`
when you really want zero footprint.

## Outputs the deploy track reads

| Output                    | Used for                                                          |
| ------------------------- | ----------------------------------------------------------------- |
| `cluster_name`            | `aws eks update-kubeconfig`, helm `--set clusterName`             |
| `region`                  | helm `--set region`                                               |
| `vpc_id`                  | helm `--set vpcId` for the ALB controller                         |
| `alb_controller_role_arn` | annotation on the controller's ServiceAccount (IRSA)              |
| `oidc_provider_arn` / `oidc_provider_url` | building further IRSA roles                       |
| `kubeconfig_command`      | shell-eval to point `kubectl` at the cluster                      |

## Notes

- Whoever runs `terraform apply` first becomes cluster-admin — the module
  is configured with `enable_cluster_creator_admin_permissions = true`.
  Worth knowing if you're planning to apply from CI under a different role.
- The S3 backend uses `use_lockfile = true` (Terraform 1.10+). Older
  versions silently skip the lock and will eventually corrupt state if two
  applies overlap.
- Per-AZ NAT runs ~$32/mo per AZ. Flip `single_nat_gateway = true` in
  `main.tf` if you don't care about AZ-level egress isolation.
- EIPs default to a soft quota of 5 per region; this stack asks for 3. If
  apply errors there, request a quota bump or set `single_nat_gateway = true`.
