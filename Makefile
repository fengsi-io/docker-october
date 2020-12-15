IMAGE			?= october
REGISTRY		?= fengsiio
OCTOBER_VERSION ?=v1.1.1

all: build push

.ONESHELL:
build:
	@docker build \
		--progress plain \
		--force-rm \
		--build-arg http_proxy \
		--build-arg https_proxy \
		--build-arg no_proxy \
		--build-arg OCTOBER_VERSION=$(OCTOBER_VERSION) \
		-t $(REGISTRY)/$(IMAGE):$(OCTOBER_VERSION) .

push:
	@docker push $(REGISTRY)/$(IMAGE):$(OCTOBER_VERSION)
