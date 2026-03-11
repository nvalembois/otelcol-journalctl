$1 == "ARG" && $2 ~ /^[A-Z]+_VERSION=/ { 
  print $2
}
