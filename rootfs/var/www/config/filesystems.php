<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Default Filesystem Disk
    |--------------------------------------------------------------------------
    |
    | Here you may specify the default filesystem disk that should be used
    | by the framework. A "local" driver, as well as a variety of cloud
    | based drivers are available for your choosing. Just store away!
    |
    | Supported: "local", "ftp", "sftp", "s3", "rackspace"
    |
    */

    'default' => env('FILESYSTEM_DEFAULT', 'local'),

    /*
    |--------------------------------------------------------------------------
    | Default Cloud Filesystem Disk
    |--------------------------------------------------------------------------
    |
    | Many applications store files both locally and in the cloud. For this
    | reason, you may specify a default "cloud" driver here. This driver
    | will be bound as the Cloud disk implementation in the container.
    |
    */

    'cloud' => env('FILESYSTEM_CLOUD', 's3'),

    /*
    |--------------------------------------------------------------------------
    | Filesystem Disks
    |--------------------------------------------------------------------------
    |
    | Here you may configure as many filesystem "disks" as you wish, and you
    | may even configure multiple disks of the same driver. Defaults have
    | been setup for each driver as an example of the required options.
    |
    */

    'disks' => [

        'local' => [
            'driver' => 'local',
            'root'   => storage_path('app'),
            'url'    => '/storage/app',
        ],

        's3' => [
            'driver'     => 's3',
            'key'        => env('FILESYSTEM_S3_KEY', 'your-key'),
            'secret'     => env('FILESYSTEM_S3_SECRET', 'your-secret'),
            'endpoint'   => env('FILESYSTEM_S3_ENDPOINT', 'your-endpoint'),
            'region'     => env('FILESYSTEM_S3_REGION', 'your-region'),
            'bucket'     => env('FILESYSTEM_S3_BUCKET', 'your-bucket'),
            'visibility' => 'public',
        ],

        'rackspace' => [
            'driver'    => 'rackspace',
            'username'  => 'your-username',
            'key'       => 'your-key',
            'container' => 'your-container',
            'endpoint'  => 'https://identity.api.rackspacecloud.com/v2.0/',
            'region'    => 'IAD',
        ],
    ],

];
