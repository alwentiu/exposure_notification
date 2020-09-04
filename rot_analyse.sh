#!/bin/bash

grep -A 2 -B 8 "(0xfd6f)" hcitrace.txt > en.txt

pmac=""
prpi=""

while read -r line
do
  if [[ $line == *"Address:"* ]]; then
   # echo -n "MAC: ${line:9:17}, " 
     mac=${line:9:17}
  fi
  if [[ $line == *"Service Data"* ]]; then
    # echo "RPI: ${line:28}"
     rpi=${line:28}


     # Type 1 OoS: MAC rotates, but not RPI    
     if [[ $mac != $pmac && $rpi == $prpi ]]; then
        echo "[1] MAC: $mac, RPI: $rpi"
     fi

     # Type 2 OoS: RPI rotates but not MAC    
     if [[ $mac == $pmac && $rpi != $prpi ]]; then
        echo "[2] MAC: $mac, RPI: $rpi"
     fi

     # MAC and RPI rotate at the same time
     if [[ $mac != $pmac && $rpi != $prpi ]]; then
        echo "[-] MAC: $mac, RPI: $rpi"
     fi
     
     pmac=$mac
     prpi=$rpi 
  fi

done < en.txt

 
