#!/bin/bash

sui move build --skip-fetch-latest-git-deps

sui client publish . --gas-budget 300000000

sui client upgrade --gas-budget 300000000 --upgrade-capability 0x68e6ae08784b824c733feff03b7a59c69bf2cfed1951565306beb4cdcf3cd880
