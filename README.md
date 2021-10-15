# Redis for Docker

A small Redis image that can be used to start a Redis server.

## Supported tags

- [`latest`](https://github.com/fscm/docker-redis/blob/master/Dockerfile)

## What is Redis?

> Redis is an open source (BSD licensed), in-memory data structure store, used as a database, cache, and message broker.

*from* [redis.io](https://redis.io/)

## Getting Started

There are a couple of things needed for the script to work.

### Prerequisites

Docker, either the Community Edition (CE) or Enterprise Edition (EE), needs to
be installed on your local computer.

#### Docker

Docker installation instructions can be found
[here](https://docs.docker.com/install/).

### Usage

This image has the following Redis utilities:

- `benchmark` - The Redis benchmark utility that simulates running several
commands at the same time.
- `check-aof` - The Redis AOF file checker and repairer utility.
- `check-rdb` - The Redis RDB file checker utility.
- `cli` - The Redis command line interface utility.
- `sentinel` - The monitoring utility for Redis instances.
- `server` - The Redis database server.

To use an utility from the image run the image with the utility name as the
first argument:

```shell
docker container run --rm --interactive --tty fscm/redis <UTILITY_NAME> [utility_options]
```

#### Starting a Redis Server

The quickest way to start a Redis server is with the following command:

```shell
docker container run --rm --detach --publish 6379:6379/tcp --name my_redis fscm/redis server
```

The server will then be available at the host ip address port 6379. You can
test it using the Redis `cli` utility from this same image:

```shell
docker container run --rm --interactive --tty fscm/redis cli -h <IPADDRESS> ping
```

#### Starting a Redis Server (persistent storage)

To start a Redis server with persistent storage use the following command:

```shell
docker container run --rm --detach --volume "${PWD}":/data:rw --publish 6379:6379/tcp --name my_redis fscm/redis server --save 60 1
```

The previous command uses the current folder for storage but a Docker volume
can also be used instead to store the data. See [below](#creating-volumes) how
to create docker volumes.

#### Starting a Redis Server (custom configuration file)

You can use a configuration file to set some of the Redis server options.

To do so you will need to create a valid configuration file and then use the
folder where that file is as the storage volume so that redis-server can access
that file.

Example for a configuration file located on the current folder:

```shell
docker container run --rm --detach --volume "${PWD}":/data:rw --publish 6379:6379/tcp --name my_redis fscm/redis server /data/<CONFIG_FILE>
```

#### Creating Volumes

Creating volumes can be done using the `docker` tool. To create a volume use
the following command:

```shell
docker volume create --name VOLUME_NAME
```

Two create the required volume the following command can be used:

```shell
docker volume create --name my_redis_data
```

**Note:** To use the a volume just write the volume name in place of the folder
path.

#### Stop the Redis Server

If needed the Redis server can be stopped and later started again (as long as
the command used to perform the initial start did not included the `--rm`
option).

To stop the server use the following command:

```shell
docker container stop CONTAINER_ID
```

To start the server again use the following command:

```shell
docker container start CONTAINER_ID
```

## Build

Build instructions can be found
[here](https://github.com/fscm/docker-redis/blob/master/README.build.md).

## Versioning

This project uses [SemVer](http://semver.org/) for versioning. For the versions
available, see the [tags on this repository](https://github.com/fscm/docker-redis/tags).

## Authors

- **Frederico Martins** - [fscm](https://github.com/fscm)

See also the list of [contributors](https://github.com/fscm/docker-redis/contributors)
who participated in this project.
