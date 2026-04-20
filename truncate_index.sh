#!/bin/bash
INDEX="${1:-sim-auth-brute-force}"
curl -X POST "localhost:9200/${INDEX}/_delete_by_query" -H 'Content-Type: application/json' -d'{"query":{"match_all":{}}}'
