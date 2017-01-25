PROJECT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PARENT_DIR := $(shell dirname $(PROJECT_DIR))
PROJECT_NAME := $(shell basename $(PROJECT_DIR))
BASE := $(shell basename $(PARENT_DIR))

# Artifact information
CI_BUILD_NUMBER ?= $(USER)-snapshot

VERSION = $(CI_BUILD_NUMBER)
PUBLISH_TAG ?= $(BASE)/$(PROJECT_NAME):$(VERSION)
ECR_TAG ?= ${AWS_ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/$(PUBLISH_TAG)
GIT_TAG=${AWS_ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/$(BASE)/$(PROJECT_NAME):$(shell git log --pretty=format:'%h' -n 1) 

DEPLOY_VERSION ?= $(VERSION)

ECR_LOGIN := $(shell aws ecr get-login --region us-east-1)

# lists all available targets
list:
	@sh -c "$(MAKE) -p no_targets__ | \
		awk -F':' '/^[a-zA-Z0-9][^\$$#\/\\t=]*:([^=]|$$)/ {split(\$$1,A,/ /);\
		for(i in A)print A[i]}' | \
		grep -v '__\$$' | \
		grep -v 'make\[1\]' | \
		grep -v 'Makefile' | \
		sort"
# required for list
no_targets__:

package:
	docker build -t $(PUBLISH_TAG) .
	docker tag $(PUBLISH_TAG) $(ECR_TAG) 
	docker tag $(PUBLISH_TAG) $(GIT_TAG) 

__run: package
	@docker run -it -P --rm \
		-h $(PROJECT_NAME) \
		--name $(PROJECT_NAME)_run \
		$(PUBLISH_TAG)

# test your application (tests in the tests/ directory)
test: package
	bundle install --path vendor/bundle
	bundle exec rspec

version:
	@echo "           tag: $(PUBLISH_TAG)"
	@echo "deploy version: $(DEPLOY_VERSION)"
	@echo "       git tag: $(GIT_TAG)"
	

__get-credentials:
	$(ECR_LOGIN)

publish: package __get-credentials
	docker push $(ECR_TAG)
	docker push $(GIT_TAG)

docs:
	@cat README.md
