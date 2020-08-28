IMAGE				?= october
REGISTRY			?= fengsiio
TMP_DOCKERFILE 		?= Dockerfile.tmp

.ONESHELL:
push:
	@cp -f Dockerfile $(TMP_DOCKERFILE)
	@sed -i '/^FROM composer/a\\nRUN composer config -g repo.packagist composer https://packagist.phpcomposer.com' $(TMP_DOCKERFILE)
	@docker build --pull \
		--build-arg HTTP_PROXY=$$HTTP_PROXY \
		--build-arg http_proxy=$$HTTP_PROXY \
		--build-arg HTTPS_PROXY=$$HTTP_PROXY \
		--build-arg https_proxy=$$HTTP_PROXY \
		--build-arg ALL_PROXY=$$HTTP_PROXY \
		--build-arg all_proxy=$$HTTP_PROXY \
		-t $(REGISTRY)/$(IMAGE):develop \
		-f $(TMP_DOCKERFILE) .
	@docker push $(REGISTRY)/$(IMAGE):develop
	@rm $(TMP_DOCKERFILE)