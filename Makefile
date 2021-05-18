OCTOBER_VERSION ?= v1.1.5
IMAGE			?= october
REGISTRY		?= fengsiio
TAG				?= $(REGISTRY)/$(IMAGE):$(patsubst v%,%,$(OCTOBER_VERSION))

all: build push

test:
	@echo 

.ONESHELL:
build:
	@docker build \
		--progress plain \
		--force-rm \
		--build-arg http_proxy \
		--build-arg https_proxy \
		--build-arg no_proxy \
		--build-arg all_proxy \
		--build-arg OCTOBER_VERSION=$(OCTOBER_VERSION) \
		-t $(TAG) .
	@docker tag $(TAG) $(REGISTRY)/$(IMAGE):latest

push:
	@docker push $(TAG)
