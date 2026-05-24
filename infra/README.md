# infra

Terraform that provisions the AWS network and EKS cluster the microservice
runs on. The deploy track (`deploy/`) consumes the outputs from here.

## Layout

```
infra/
├── bootstrap/
│   └── bootstrap.sh        # one-time S3 state bucket setup
└── envs/
    └── dev/
        ├── backend.tf      # S3 backend, partial config
        ├── main.tf         # vpc + eks + eks-pod-identity modules
        ├── outputs.tf      # what the deploy pipeline reads
        ├── providers.tf    # aws + kubernetes + helm providers
        ├── variables.tf
        ├── versions.tf
        └── terraform.tfvars.example
```

Only one environment ships (`envs/dev/`). Promotion to staging/prod is
out of scope.

## What gets created

- A `10.0.0.0/16` VPC across 3 AZs with one NAT gateway per AZ.
- Three public `/20` subnets (for ALBs and the NATs) and three private `/19`
  subnets (for the worker nodes). Both sets carry the
  `kubernetes.io/role/{elb,internal-elb}` and `kubernetes.io/cluster/*=shared`
  tags the AWS Load Balancer Controller looks for.
- An EKS cluster on Kubernetes 1.34, public + private API endpoint, KMS
  secret encryption, CloudWatch logs for `api`, `audit`, `authenticator`.
- A managed node group on AL2023 (`t3.medium`, min/desired/max = 2/2/4) in
  the private subnets.
- The `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`, and
  `eks-pod-identity-agent` add-ons.
- An IAM role + EKS Pod Identity association for the AWS Load Balancer
  Controller. The controller itself is **not** installed by Terraform — that
  belongs to the deploy track.

## Prerequisites

- Terraform `>= 1.9`
- AWS CLI v2, authenticated against the target account (`aws sts get-caller-identity` works)
- Permissions to create VPCs, EKS clusters, IAM roles, KMS keys, S3 buckets

## Bootstrap (one-time per AWS account)

The S3 bucket that holds Terraform state must exist before
`terraform init` can configure the backend. `bootstrap.sh` creates it
with versioning, SSE-S3 encryption, and public access blocked.

```bash
infra/bootstrap/bootstrap.sh sample-eks-microservice-tfstate us-east-1
```

The script is idempotent — re-running it is a no-op.

## Init, plan, apply

```bash
# Replace bucket/region with whatever you used above.
terraform -chdir=infra/envs/dev init \
  -backend-config="bucket=sample-eks-microservice-tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="key=envs/dev/terraform.tfstate"

terraform -chdir=infra/envs/dev plan
terraform -chdir=infra/envs/dev apply
```

Wall-clock time on a clean account: ~15 minutes (cluster + node group
warmup dominates).

When the apply finishes, point `kubectl` at it:

```bash
$(terraform -chdir=infra/envs/dev output -raw kubeconfig_command)
kubectl get nodes
kubectl get pods -A
```

## Destroy

```bash
terraform -chdir=infra/envs/dev destroy
```

Terraform tears down the cluster, node group, and VPC. The state bucket
itself is left behind on purpose — drop it manually if you really want
zero footprint:

```bash
aws s3 rb s3://sample-eks-microservice-tfstate --force
```

## Common pitfalls

- **Subnet tagging missing**: if the ALB controller can't find subnets, the
  `kubernetes.io/role/elb` and `kubernetes.io/cluster/<name>=shared` tags
  are likely off. They're set in `main.tf` — double-check the cluster name
  matches what the chart references.
- **NAT Gateway costs**: the per-AZ NAT pattern is right for production but
  costs ~$32/mo per AZ. For long-running dev clusters set
  `single_nat_gateway = true` in the `vpc` module to drop to a single NAT.
- **`use_lockfile` requires Terraform 1.10+**: the backend uses S3-native
  locking instead of DynamoDB. Older Terraform versions silently skip the
  lock — pin `>= 1.9` (this repo) and prefer `>= 1.10` to be safe.
- **First-run permissions**: whoever runs `terraform apply` becomes a
  cluster-admin via `enable_cluster_creator_admin_permissions = true`.
  Plan accordingly if you're applying from CI.
