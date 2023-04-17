OCTOBER_VERSION ?= v1.1.12
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
		--build-arg OCTOBER_VERSION=$(OCTOBER_VERSION) \
		-t $(TAG) .

push:
	@docker tag $(TAG) $(REGISTRY)/$(IMAGE):latest
	@docker push $(TAG)
	@docker push $(REGISTRY)/$(IMAGE):latest
