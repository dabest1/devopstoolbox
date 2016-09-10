#!/bin/bash

# Purpose:
#     Stop MongoDB cluster and delete all database files and logs.

version="1.0.1"

./stop.sh

rm -rf a1 a2 a3 b1 b2 b3 c1 c2 c3 d1 d2 d3 cfg1 cfg2 cfg3 log.*
