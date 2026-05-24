.DEFAULT_GOAL := help

# ---------------------------------------------------------------- microservice
.PHONY: app-install app-run app-test image
app-install:    ## Install Python deps for local dev
	@echo "TODO: filled in by the microservice track"

app-run:        ## Run the service locally
	@echo "TODO: filled in by the microservice track"

app-test:       ## Run pytest
	@echo "TODO: filled in by the microservice track"

image:          ## Build the container image locally
	@echo "TODO: filled in by the microservice track"

# ---------------------------------------------------------------- infra
.PHONY: infra-bootstrap infra-init infra-plan infra-apply infra-destroy
infra-bootstrap: ## Create the S3 state bucket (idempotent)
	@echo "TODO: filled in by the infra track"

infra-init:     ## terraform init for envs/dev
	@echo "TODO: filled in by the infra track"

infra-plan:     ## terraform plan for envs/dev
	@echo "TODO: filled in by the infra track"

infra-apply:    ## terraform apply for envs/dev
	@echo "TODO: filled in by the infra track"

infra-destroy:  ## terraform destroy for envs/dev
	@echo "TODO: filled in by the infra track"

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
