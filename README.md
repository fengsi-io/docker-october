# Dockerized OctoberCMS

OctoberCms docker image with PHP 7.4 and Caddy server.

### Useage

```shell
docker run \
    --rm \
    -v $(pwd)/plugins:/var/www/plugins \
    -v $(pwd)/config:/var/www/config \
    -v $(pwd)/themes:/var/www/themes \
    # Support apply patch to directus or plugins when first start.
    -v $(pwd)/patches:/var/patches \
    -e "CADDY_VERSION=1.0.5" \
    -e "CADDY_PLUGINS=\
        github.com/epicagency/caddy-expires@v1.1.1\
        github.com/captncraig/caddy-realip \
        " \
    fengsiio/october:latest
```

### custom plugins

place your custom plugins to `/docker-entrypoint.d/plugins` will install on
system boot.

You can also use build in config with environments variable:

```shell
# Application Debug Mode
APP_DEBUG=true

# Application URL
APP_URL=http://example.com

# Database Connections
DB_HOST=db
DB_PORT=3306
DB_DATABASE=YOUR_DATABASE
DB_USERNAME=YOUR_DATABASE_USERNAME
DB_PASSWORD=opUcc+N3t3g8/oUm90I=

# for initalize script
THEME=YOUR_THEME_CODE
PLUGINS=Ompmega.MixHelper, Martin.Forms, Mohsin.txt, ToughDeveloper.ImageResizer, VojtaSvoboda.TwigExtensions

# for s3 disks
FILESYSTEM_DEFAULT: "s3"
FILESYSTEM_S3_ROOT: "your_root_path"
FILESYSTEM_S3_ENDPOINT: "https://your-region.digitaloceanspaces.com"
FILESYSTEM_S3_URL: "https://cdn.domain.example"
FILESYSTEM_S3_KEY: "your-s3-key"
FILESYSTEM_S3_SECRET: "your-s3-secret"
FILESYSTEM_S3_REGION: "your-region"
FILESYSTEM_S3_BUCKET: "your-bucket"
```
