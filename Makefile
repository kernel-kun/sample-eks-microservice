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

.PHONY: infra-bootstrap infra-init infra-plan infra-apply infra-destroy
infra-bootstrap: ## Create the S3 state bucket (idempotent)
	infra/bootstrap/bootstrap.sh $(TFSTATE_BUCKET) $(AWS_REGION)

infra-init:     ## terraform init for envs/dev
	terraform -chdir=$(INFRA_DIR) init \
		-backend-config="bucket=$(TFSTATE_BUCKET)" \
		-backend-config="region=$(AWS_REGION)" \
		-backend-config="key=$(TFSTATE_KEY)"

infra-plan:     ## terraform plan for envs/dev
	terraform -chdir=$(INFRA_DIR) plan

infra-apply:    ## terraform apply for envs/dev
	terraform -chdir=$(INFRA_DIR) apply

infra-destroy:  ## terraform destroy for envs/dev
	terraform -chdir=$(INFRA_DIR) destroy

# ---------------------------------------------------------------- deploy
.PHONY: chart-lint deploy-local
chart-lint:     ## helm lint the microservice chart
	@echo "TODO: filled in by the deploy track"

deploy-local:   ## install all charts against the current kube context
	@echo "TODO: filled in by the deploy track"

# ---------------------------------------------------------------- meta
.PHONY: help
help:           ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Available targets:\n"} \
		/^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
