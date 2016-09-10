#!/bin/bash

# Purpose:
#     Stop MongoDB cluster.

version="1.0.1"

ps -ef | egrep '[m]ongod|[m]ongos' | awk '{print $2}' | xargs kill
