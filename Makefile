.DEFAULT_GOAL := help

# ---------------------------------------------------------------- microservice
APP_DIR    ?= app
IMAGE_NAME ?= sample-service
IMAGE_TAG  ?= dev

.PHONY: app-install app-run app-test image
app-install:    ## Create venv and install app + dev deps
	cd $(APP_DIR) && python3 -m venv .venv && .venv/bin/pip install --upgrade pip && .venv/bin/pip install -e ".[dev]"

app-run:        ## Run the service locally on 127.0.0.1:8080
	cd $(APP_DIR) && .venv/bin/uvicorn sample_service.main:app --host 127.0.0.1 --port 8080

app-test:       ## Run pytest
	cd $(APP_DIR) && .venv/bin/pytest -q

image:          ## Build the container image locally for the host arch
	docker buildx build --load -t $(IMAGE_NAME):$(IMAGE_TAG) $(APP_DIR)

# ---------------------------------------------------------------- infra
INFRA_DIR        ?= infra/envs/dev
TFSTATE_BUCKET   ?= sample-eks-microservice-tfstate
AWS_REGION       ?= us-east-1
TFSTATE_KEY      ?= envs/dev/terraform.tfstate

.PHONY: infra-bootstrap infra-init infra-validate infra-plan infra-apply infra-verify infra-destroy
infra-bootstrap: ## Create the S3 state bucket (idempotent)
	infra/bootstrap/bootstrap.sh $(TFSTATE_BUCKET) $(AWS_REGION)

infra-init:     ## terraform init for envs/dev
	terraform -chdir=$(INFRA_DIR) init \
		-backend-config="bucket=$(TFSTATE_BUCKET)" \
		-backend-config="region=$(AWS_REGION)" \
		-backend-config="key=$(TFSTATE_KEY)"

infra-validate: ## terraform fmt -check + validate (run after infra-init)
	terraform -chdir=$(INFRA_DIR) fmt -check -recursive
	terraform -chdir=$(INFRA_DIR) validate

infra-plan:     ## terraform plan for envs/dev
	terraform -chdir=$(INFRA_DIR) plan

infra-apply:    ## terraform apply for envs/dev
	terraform -chdir=$(INFRA_DIR) apply

infra-verify:  ## Post-apply sanity: nodes Ready, system pods Running, ALB controller role wired
	kubectl get nodes
	kubectl get pods -A
	@echo
	@echo "ALB controller ServiceAccount role-arn annotation:"
	@kubectl -n kube-system get sa aws-load-balancer-controller \
	  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}' \
	  2>/dev/null || echo "  (ServiceAccount not created yet — that's the deploy track's job)"

infra-destroy:  ## terraform destroy for envs/dev
	terraform -chdir=$(INFRA_DIR) destroy

# ---------------------------------------------------------------- deploy
CHART_DIR    ?= deploy/charts/microservice
CLUSTER_NAME ?= sample-eks
VPC_ID       ?=

.PHONY: chart-lint chart-template deploy-local
chart-lint:     ## helm lint + template render the microservice chart
	helm lint $(CHART_DIR)
	helm template test $(CHART_DIR) > /dev/null

chart-template: ## Render the chart to stdout (helpful for diffing)
	helm template test $(CHART_DIR)

deploy-local:   ## Install ALB controller + monitoring + microservice against the current kube context (auto-discovers VPC + role ARN, auto-recovers stuck pending-install)
	@set -e; \
	vpc_id="$(VPC_ID)"; \
	if [ -z "$$vpc_id" ]; then \
	  echo "Discovering VPC ID for cluster $(CLUSTER_NAME)..."; \
	  vpc_id=$$(aws eks describe-cluster --name "$(CLUSTER_NAME)" --region "$(AWS_REGION)" \
	    --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true); \
	fi; \
	if [ -z "$$vpc_id" ] || [ "$$vpc_id" = "None" ]; then \
	  echo "Could not determine VPC ID for cluster $(CLUSTER_NAME). Is the cluster up?"; exit 1; \
	fi; \
	echo "VPC: $$vpc_id"; \
	echo "Discovering ALB controller IAM role ARN..."; \
	role_arn=$$(aws iam get-role --role-name "$(CLUSTER_NAME)-alb-controller" --query 'Role.Arn' --output text 2>/dev/null || true); \
	if [ -z "$$role_arn" ] || [ "$$role_arn" = "None" ]; then \
	  role_arn=$$(aws iam list-roles \
	    --query "Roles[?starts_with(RoleName, 'aws-load-balancer-controller') || ends_with(RoleName, '-alb-controller')] | [0].Arn" \
	    --output text); \
	fi; \
	if [ -z "$$role_arn" ] || [ "$$role_arn" = "None" ]; then \
	  echo "Could not find ALB controller IAM role. Did 'terraform apply' run?"; exit 1; \
	fi; \
	echo "Role: $$role_arn"; \
	helm repo add eks https://aws.github.io/eks-charts; \
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts; \
	helm repo update; \
	for pair in "aws-load-balancer-controller:kube-system" "monitoring:monitoring" "microservice:app"; do \
	  rel=$${pair%:*}; ns=$${pair#*:}; \
	  status=$$(helm status $$rel -n $$ns -o json 2>/dev/null | grep -o '"status":"[^"]*"' || true); \
	  case "$$status" in \
	    *pending-install*|*pending-upgrade*|*pending-rollback*) \
	      echo "release $$rel/$$ns is $$status — uninstalling so we can retry"; \
	      helm uninstall $$rel -n $$ns || true ;; \
	  esac; \
	done; \
	helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
		-n kube-system --version 1.14.0 \
		-f deploy/ingress-controller/values.yaml \
		--set clusterName=$(CLUSTER_NAME) --set region=$(AWS_REGION) --set vpcId=$$vpc_id \
		--set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$$role_arn" \
		--wait --timeout 5m; \
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		-n monitoring --create-namespace --version 85.3.0 \
		-f deploy/monitoring/values.yaml --wait --timeout 10m; \
	helm upgrade --install microservice $(CHART_DIR) \
		-n app --create-namespace --wait --timeout 5m

# ---------------------------------------------------------------- meta
.PHONY: help
help:           ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Available targets:\n"} \
		/^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
