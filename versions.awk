$1 == "FROM" && $3 == "AS" && $4 == "prep" { 
   gsub("@.*","",$2)
   gsub(".*:","",$2)
   print "OTEL_VERSION="$2
}
$1 == "ARG" && $2 ~ /^SYSTEMD_VERSION=/ { 
  print $2
}
