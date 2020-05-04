BUILD_PROXY_PORT ?= 1080
BUILD_SERVICE =

REMOTE ?= false

.ONESHELL:
build: build.yml
	@command="docker-compose -f $< build --force-rm --pull"
	@if [ "$(REMOTE)" != "false" ]; then
		echo use remote docker environment bandwagon02
		eval "$$(docker-machine env bandwagon02 --shell bash)"
	else
		proxy=http://$$(powershell "(Get-NetIPAddress -PrefixOrigin Dhcp -AddressState Preferred -AddressFamily IPv4).IPAddress"):$(BUILD_PROXY_PORT)
		command="$$command \
			--build-arg HTTP_PROXY=$$proxy \
			--build-arg HTTPS_PROXY=$$proxy \
			--build-arg HTTP_PROXY_REQUEST_FULLURI=0 \
			--build-arg HTTPS_PROXY_REQUEST_FULLURI=0"
	fi
	@eval "$$command $(BUILD_SERVICE)";

TAGS ?= dev-latest
REGISTRY ?= registry.us-west-1.aliyuncs.com/fengsi

.ONESHELL:
push: build.yml build
	@echo "use remote docker: $$DOCKER_HOST"
	@image=$$(yq r $< 'services.(build==*).image')
	@for tag in $(TAGS); do
		registry_image=$(REGISTRY)/$$image:$$tag;
		docker tag $$image:latest $$registry_image;
		echo "Successfully tagged $$registry_image";
		docker push $$registry_image;
	done

.ONESHELL:
dev: dev.yml build
	@docker-compose -f $< up;

.ONESHELL:
app_key:
	@date +%s | md5sum | cut -d ' ' -f1

.PHONY: clean
clean:
	@if [ -e dev.yml ]; then
		docker-compose -f dev.yml down;
	fi
