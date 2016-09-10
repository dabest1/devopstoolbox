ps -ef | egrep '[m]ongod|[m]ongos' | awk '{print $2}' | xargs kill
