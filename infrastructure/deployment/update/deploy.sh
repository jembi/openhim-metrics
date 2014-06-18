#!/bin/bash

SOURCEDIR="/home/jembi/metrics-service"

cd $SOURCEDIR;
git pull && puppet apply infrastructure/deployment/update/deploy.pp
