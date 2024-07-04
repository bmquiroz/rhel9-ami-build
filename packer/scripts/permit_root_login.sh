#!/bin/bash
conf=$(grep -l PermitRootLogin /etc/ssh/sshd_config.d/*)
if [ "$conf" != "" ] ; then 
  sed -i -e 's/PermitRootLogin.*$/PermitRootLogin yes/' $conf
fi
   
