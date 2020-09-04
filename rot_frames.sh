#!/bin/bash

grep -A 2 -B 8 "(0xfd6f)" hcitrace.txt > en.txt

grep "Service Data" en.txt | uniq > rpi.txt

while read -r line
do
  echo "==============================================================================="
  echo "Rotation for RPI: ${line:28}"
  echo "==============================================================================="
  rpi=${line:28}
  grep -A 26 -B 9 $rpi en.txt | tail -n 48  
done < rpi.txt

 
