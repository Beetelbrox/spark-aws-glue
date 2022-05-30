.PHONY: build
.DEFAULT_GLOBAL: help

IMAGE_NAME ?= spark-glue

build:
	DOCKER_BUILDKIT=0  docker build docker/spark -t $(IMAGE_NAME)